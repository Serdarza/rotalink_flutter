import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pro_products.dart';

/// Rotalink Pro (reklamsız) abonelik durumu.
///
/// Hak sahipliği mağaza satın alma akışından okunur; çevrimdışı açılışlar
/// için yerel saklanır. Dönem bitişi plan türüne göre (aylık/yıllık)
/// hesaplanır; süre dolunca [isPro] false olur ve reklamlar geri gelir.
class ProService {
  ProService._();
  static final ProService instance = ProService._();

  static const String _keyActive = 'rotalink_pro_active';
  static const String _keyProductId = 'rotalink_pro_product_id';
  static const String _keyExpiryMs = 'rotalink_pro_expiry_ms';

  /// Mağaza yanıtı beklenirken hak sahipliği kararı için tanınan süre.
  static const Duration _restoreWindow = Duration(seconds: 4);

  /// Dönem sonu ile mağaza yenilemesinin bize ulaşması arasındaki pay.
  /// Yenileme gecikirse kullanıcı haksız yere reklam görmesin.
  static const Duration _renewalGrace = Duration(days: 3);

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Timer? _expiryTimer;

  /// Reklamsız hak — `AdService` ve arayüz bunu dinler.
  final ValueNotifier<bool> isPro = ValueNotifier<bool>(false);

  /// Mevcut dönemin tahmini bitiş anı (geri sayım için).
  final ValueNotifier<DateTime?> expiryAt = ValueNotifier<DateTime?>(null);

  /// Mağazadan okunan planlar (fiyat/başlık dahil).
  final ValueNotifier<List<ProductDetails>> products =
      ValueNotifier<List<ProductDetails>>(const []);

  /// Satın alma akışı sürüyor — buton kilidi için.
  final ValueNotifier<bool> purchasePending = ValueNotifier<bool>(false);

  final StreamController<String> _messages =
      StreamController<String>.broadcast();

  /// Kullanıcıya gösterilecek hata / bilgi mesajları.
  Stream<String> get messages => _messages.stream;

  bool _initialized = false;
  bool _storeAvailable = false;
  String? _activeProductId;
  bool _restoring = false;
  bool _sawEntitlementDuringRestore = false;
  bool _restoreQueryFailed = false;
  bool _expiring = false;

  /// Mağaza (Play / App Store) kullanılabilir mi.
  bool get storeAvailable => _storeAvailable;

  /// Kullanıcının aboneliği hangi plan üzerinden.
  String? get activeProductId => _activeProductId;

  /// Aylık mı yıllık mı.
  bool get isYearlyPlan => _activeProductId == ProProducts.yearly;

  /// Reklamlar şu an kapalı olmalı mı?
  ///
  /// Aktif abonelik + (varsa) dönem bitişi gelecekte.
  /// Süre dolmuşsa anında false döner ve arka planda hak düşürülür.
  bool get isAdFree {
    if (!isPro.value) return false;
    final end = expiryAt.value;
    if (end != null && !end.isAfter(DateTime.now())) {
      unawaited(_expireLocally(reason: 'period_ended'));
      return false;
    }
    return true;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _loadCachedEntitlement();
    _scheduleExpiryTimer();

    try {
      _storeAvailable = await _iap.isAvailable();
    } catch (e) {
      debugPrint('[Pro] mağaza erişilemedi: $e');
      _storeAvailable = false;
    }
    if (!_storeAvailable) {
      debugPrint('[Pro] mağaza kullanılamıyor — önbellek durumu korunuyor');
      return;
    }

    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object e) => debugPrint('[Pro] satın alma akışı hatası: $e'),
    );

    await loadProducts();
    await restore(silent: true);
    _scheduleExpiryTimer();
  }

  /// Mağazadan plan ayrıntılarını çeker.
  Future<void> loadProducts() async {
    if (!_storeAvailable) return;
    try {
      final response = await _iap.queryProductDetails(ProProducts.ids);
      if (response.error != null) {
        debugPrint('[Pro] plan sorgusu hatası: ${response.error}');
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('[Pro] bulunamayan plan: ${response.notFoundIDs}');
      }
      final list = [...response.productDetails]
        ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
      products.value = list;
    } catch (e) {
      debugPrint('[Pro] planlar okunamadı: $e');
    }
  }

  /// Aboneliği geri yükler. [silent] açılış senkronizasyonu içindir.
  Future<void> restore({bool silent = false}) async {
    if (!_storeAvailable) {
      if (!silent) _emit('Mağazaya ulaşılamadı. İnternetinizi kontrol edin.');
      return;
    }

    final before = isPro.value;
    _sawEntitlementDuringRestore = false;
    _restoreQueryFailed = false;
    _restoring = true;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await _restoreAndroidPurchases();
      }
      await _iap.restorePurchases();
      await Future<void>.delayed(_restoreWindow);
    } catch (e) {
      debugPrint('[Pro] geri yükleme hatası: $e');
      if (!silent) _emit('Abonelik geri yüklenemedi.');
      _restoring = false;
      return;
    }
    _restoring = false;

    // Sessiz açılışta boş yanıt önbelleği silmesin.
    // Sorgu hata verdiyse de "abonelik yok" sonucuna varmayız; aksi halde
    // geçici ağ/mağaza sorununda ödeme yapan kullanıcı hakkını kaybeder.
    if (!_sawEntitlementDuringRestore && !silent && !_restoreQueryFailed) {
      await _setEntitlement(false, productId: null, expiry: null);
    }

    _scheduleExpiryTimer();

    if (silent) return;
    if (isPro.value) {
      _emit('Pro aboneliğiniz geri yüklendi.');
    } else if (before) {
      _emit('Aktif bir Pro aboneliği bulunamadı.');
    } else {
      _emit('Bu hesapta aktif Pro aboneliği yok.');
    }
  }

  Future<void> _restoreAndroidPurchases() async {
    try {
      final addition = _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();
      if (response.error != null) {
        _restoreQueryFailed = true;
        debugPrint('[Pro] Android geçmiş sorgu hatası: ${response.error}');
      }
      for (final purchase in response.pastPurchases) {
        await _handlePurchase(purchase);
      }
    } catch (e) {
      _restoreQueryFailed = true;
      debugPrint('[Pro] Android geçmiş sorgu başarısız: $e');
    }
  }

  /// Seçilen planı satın alır.
  Future<void> buy(ProductDetails product) async {
    if (!_storeAvailable) {
      _emit('Mağazaya ulaşılamadı. İnternetinizi kontrol edin.');
      return;
    }
    if (purchasePending.value) return;

    purchasePending.value = true;
    try {
      final PurchaseParam param;
      if (!kIsWeb &&
          Platform.isAndroid &&
          product is GooglePlayProductDetails) {
        param = GooglePlayPurchaseParam(
          productDetails: product,
          offerToken: product.offerToken,
        );
      } else {
        param = PurchaseParam(productDetails: product);
      }
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      debugPrint('[Pro] satın alma başlatılamadı: $e');
      purchasePending.value = false;
      _emit('Satın alma başlatılamadı. Lütfen tekrar deneyin.');
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      unawaited(_handlePurchase(purchase));
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    if (!ProProducts.ids.contains(purchase.productID)) {
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      return;
    }

    switch (purchase.status) {
      case PurchaseStatus.pending:
        purchasePending.value = true;
        return;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        final expiry = _resolveExpiry(purchase);

        // Geri yüklemede dönemi çoktan bitmiş işlem gelirse (iOS geçmişi tüm
        // yenilemeleri döndürür) hak verilmez.
        if (purchase.status == PurchaseStatus.restored &&
            expiry != null &&
            !expiry.isAfter(DateTime.now())) {
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          debugPrint('[Pro] süresi geçmiş işlem yok sayıldı: ${purchase.productID}');
          return;
        }

        _sawEntitlementDuringRestore = true;
        await _setEntitlement(
          true,
          productId: purchase.productID,
          expiry: expiry,
        );
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        purchasePending.value = false;
        if (purchase.status == PurchaseStatus.purchased && !_restoring) {
          final kind = purchase.productID == ProProducts.yearly
              ? 'yıllık'
              : 'aylık';
          _emit('Rotalink Pro ($kind) etkin. Tüm reklamlar kaldırıldı.');
        }
        return;

      case PurchaseStatus.error:
        debugPrint('[Pro] satın alma hatası: ${purchase.error}');
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        purchasePending.value = false;
        _emit('Satın alma tamamlanamadı. Ücret yansımadıysa tekrar deneyin.');
        return;

      case PurchaseStatus.canceled:
        purchasePending.value = false;
        return;
    }
  }

  Future<void> _setEntitlement(
    bool active, {
    required String? productId,
    required DateTime? expiry,
  }) async {
    final nextExpiry = active ? expiry : null;
    final changed = isPro.value != active ||
        _activeProductId != productId ||
        expiryAt.value != nextExpiry;
    isPro.value = active;
    _activeProductId = productId;
    expiryAt.value = nextExpiry;
    _scheduleExpiryTimer();
    if (!changed) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyActive, active);
      if (productId == null) {
        await prefs.remove(_keyProductId);
      } else {
        await prefs.setString(_keyProductId, productId);
      }
      final expiryMs = nextExpiry?.millisecondsSinceEpoch;
      if (expiryMs == null) {
        await prefs.remove(_keyExpiryMs);
      } else {
        await prefs.setInt(_keyExpiryMs, expiryMs);
      }
    } catch (e) {
      debugPrint('[Pro] durum kaydedilemedi: $e');
    }
  }

  Future<void> _loadCachedEntitlement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var active = prefs.getBool(_keyActive) ?? false;
      _activeProductId = prefs.getString(_keyProductId);
      final expiryMs = prefs.getInt(_keyExpiryMs);
      DateTime? end;
      if (expiryMs != null) {
        end = DateTime.fromMillisecondsSinceEpoch(expiryMs);
      } else if (active && _activeProductId != null) {
        end = _periodEnd(DateTime.now(), _activeProductId!);
      }

      // Yerel süre dolmuşsa reklamları hemen aç.
      if (active && end != null && !end.isAfter(DateTime.now())) {
        active = false;
        end = null;
        _activeProductId = null;
        await prefs.setBool(_keyActive, false);
        await prefs.remove(_keyProductId);
        await prefs.remove(_keyExpiryMs);
        debugPrint('[Pro] önbellek süresi dolmuş — reklamlar açılacak');
      }

      isPro.value = active;
      expiryAt.value = end;
    } catch (e) {
      debugPrint('[Pro] önbellek okunamadı: $e');
    }
  }

  void _scheduleExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (!isPro.value) return;
    final end = expiryAt.value;
    if (end == null) return;
    final wait = end.difference(DateTime.now());
    if (wait.isNegative || wait == Duration.zero) {
      unawaited(_expireLocally(reason: 'timer_due'));
      return;
    }
    // Timer.periodic üst sınırı yok; çok uzun sürelerde (yıllık) güvenli dilimle.
    final slice = wait > const Duration(days: 1) ? const Duration(days: 1) : wait;
    _expiryTimer = Timer(slice, () {
      if (!isPro.value) return;
      final still = expiryAt.value;
      if (still == null) return;
      if (!still.isAfter(DateTime.now())) {
        unawaited(_expireLocally(reason: 'timer_fired'));
      } else {
        _scheduleExpiryTimer();
      }
    });
  }

  /// Dönem bitti: önce mağazadan yenileme var mı bak, yoksa hakkı düşür.
  Future<void> _expireLocally({required String reason}) async {
    if (_expiring) return;
    final end = expiryAt.value;
    if (end != null && end.isAfter(DateTime.now())) return;
    if (!isPro.value) return;

    _expiring = true;
    try {
      debugPrint('[Pro] dönem sonu ($reason) — yenileme kontrolü');
      if (_storeAvailable) {
        _sawEntitlementDuringRestore = false;
        _restoring = true;
        try {
          if (!kIsWeb && Platform.isAndroid) {
            await _restoreAndroidPurchases();
          }
          await _iap.restorePurchases();
          await Future<void>.delayed(const Duration(seconds: 3));
        } catch (e) {
          debugPrint('[Pro] yenileme kontrolü hatası: $e');
        }
        _restoring = false;
        if (_sawEntitlementDuringRestore &&
            expiryAt.value != null &&
            expiryAt.value!.isAfter(DateTime.now())) {
          debugPrint('[Pro] abonelik yenilenmiş — reklamlar kapalı kalacak');
          _scheduleExpiryTimer();
          return;
        }
      }
      await _setEntitlement(false, productId: null, expiry: null);
      debugPrint('[Pro] abonelik süresi doldu — reklamlar açıldı');
    } finally {
      _expiring = false;
    }
  }

  /// Satın alma zamanı + plan süresinden dönem bitişini üretir.
  ///
  /// Android: Play yalnızca **aktif** (veya ödeme bekleyen) abonelikleri
  /// döndürür ve yenilemelerde ilk satın alma zamanı değişmez; bu yüzden dönem
  /// bugüne taşınır.
  ///
  /// iOS: StoreKit geri yüklemede geçmiş yenilemeleri de verir. Dönemi ileriye
  /// taşımak süresi bitmiş aboneliği sonsuza kadar geçerli gösterirdi; en yeni
  /// işlemin dönem sonu esas alınır.
  DateTime? _resolveExpiry(PurchaseDetails purchase) {
    final start = _purchaseStart(purchase) ?? DateTime.now();
    final productId = purchase.productID;
    final now = DateTime.now();
    var end = _periodEnd(start, productId);

    final rollForward = kIsWeb || Platform.isAndroid;
    if (rollForward) {
      while (!end.isAfter(now)) {
        end = _periodEnd(end, productId);
      }
    } else {
      end = end.add(_renewalGrace);
    }

    // Aynı geri yükleme turunda birden fazla işlem gelirse en yenisi kazanır.
    final cached = expiryAt.value;
    if (isPro.value && cached != null && cached.isAfter(end)) {
      return cached;
    }
    return end;
  }

  DateTime? _purchaseStart(PurchaseDetails purchase) {
    final raw = purchase.transactionDate;
    if (raw != null && raw.isNotEmpty) {
      final ms = int.tryParse(raw);
      if (ms != null && ms > 0) {
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    return null;
  }

  /// Aylık → +1 ay, yıllık → +1 yıl.
  static DateTime _periodEnd(DateTime start, String productId) {
    if (productId == ProProducts.yearly) {
      return DateTime(
        start.year + 1,
        start.month,
        start.day,
        start.hour,
        start.minute,
        start.second,
      );
    }
    return DateTime(
      start.year,
      start.month + 1,
      start.day,
      start.hour,
      start.minute,
      start.second,
    );
  }

  void _emit(String message) {
    if (_messages.isClosed) return;
    _messages.add(message);
  }

  void dispose() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _sub?.cancel();
    _sub = null;
    _messages.close();
  }
}
