import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import 'premium_auth_service.dart';
import 'premium_presentation.dart';
import 'pro_products.dart';

class ServerPremiumAccountBridge extends PremiumAccountBridge {
  ServerPremiumAccountBridge._({
    http.Client? client,
    InAppPurchase? store,
    PremiumAuthService? auth,
  }) : _client = client ?? http.Client(),
       _store = store ?? InAppPurchase.instance,
       _auth = auth ?? PremiumAuthService.instance {
    _purchaseSubscription = _store.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error, StackTrace stack) {
        debugPrint('[Premium] mağaza akışı hatası: $error');
      },
    );
  }

  static final ServerPremiumAccountBridge instance =
      ServerPremiumAccountBridge._();
  static final Uri _origin = Uri.parse('https://admin.rotalink.tr');

  final http.Client _client;
  final InAppPurchase _store;
  final PremiumAuthService _auth;
  late final StreamSubscription<List<PurchaseDetails>> _purchaseSubscription;
  PremiumAccountSnapshot? _account;
  Set<PremiumPlan> _purchasablePlans = const {};
  Future<void>? _refreshTask;

  @override
  PremiumAccountSnapshot? get account => _account;

  @override
  Set<PremiumPlan> get purchasablePlans => _purchasablePlans;

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
  }) async {
    final token = await _auth.freshIdToken();
    final uri = _origin.replace(path: path);
    final headers = <String, String>{
      'authorization': 'Bearer $token',
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
    };
    final response = method == 'POST'
        ? await _client
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 30))
        : await _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('Pro sunucu yanıtı geçersiz.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        decoded['error'] is String
            ? decoded['error'] as String
            : 'Pro sunucusuna ulaşılamadı.',
      );
    }
    return decoded;
  }

  PremiumQuotaSnapshot? _quota(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final total = raw['total'],
        used = raw['used'],
        remaining = raw['remaining'];
    if (raw['unlimited'] == true) {
      return PremiumQuotaSnapshot(
        total: 0,
        used: used is num ? used.toInt() : 0,
        remaining: 0,
        unlimited: true,
      );
    }
    if (total is! num || used is! num || remaining is! num) return null;
    return PremiumQuotaSnapshot(
      total: total.toInt(),
      used: used.toInt(),
      remaining: remaining.toInt(),
    );
  }

  PremiumPlan? _plan(Object? sku) {
    if (sku == null) return null;
    if (sku is! String) return null;
    final plan = PremiumPlan.fromSku(sku);
    if (plan == null) {
      throw StateError('Sunucu bilinmeyen bir Pro paketi döndürdü.');
    }
    return plan;
  }

  PremiumAccountSnapshot _snapshot(Map<String, dynamic> data) {
    final plan = _plan(data['sku']);
    final state = switch (data['state']) {
      'active' => PremiumSubscriptionStatus.active,
      'renewalOff' => PremiumSubscriptionStatus.renewalOff,
      _ => PremiumSubscriptionStatus.expired,
    };
    return PremiumAccountSnapshot(
      plan: plan,
      status: state,
      periodEndsAt: data['expiresAt'] is String
          ? DateTime.tryParse(data['expiresAt'] as String)?.toLocal()
          : null,
      priceUsage: _quota(data['prices']),
      nearbyUsage: _quota(data['nearby']),
    );
  }

  @override
  Future<void> refresh() {
    final current = _refreshTask;
    if (current != null) return current;
    final task = _refreshNow();
    _refreshTask = task;
    return task.whenComplete(() {
      if (identical(_refreshTask, task)) _refreshTask = null;
    });
  }

  Future<void> _refreshNow() async {
    try {
      if (_auth.currentUser == null || _auth.currentUser?.isAnonymous == true) {
        _account = null;
        _purchasablePlans = const {};
        return;
      }
      _account = _snapshot(await _request('/api/premium/account'));
      _purchasablePlans =
          !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.android)
          ? Set.unmodifiable(
              PremiumPlan.values.where((plan) => plan.offered),
            )
          : const {};
    } finally {
      notifyListeners();
    }
  }

  Future<String> _appleAccountToken() async {
    final response = await _request('/api/premium/apple/account-token');
    final token = response['appAccountToken'];
    if (token is! String || token.isEmpty) {
      throw StateError('App Store ödeme bağlantısı alınamadı.');
    }
    return token;
  }

  @override
  Future<void> purchase(PremiumStoreOffer offer) async {
    if (kIsWeb || !ProProducts.premiumIds.contains(offer.product.id)) {
      throw StateError('Pro satın alma bu cihazda kullanılamıyor.');
    }
    final String accountToken;
    final PurchaseParam purchaseParam;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      accountToken = await _appleAccountToken();
      purchaseParam = AppStorePurchaseParam(
        productDetails: offer.product,
        applicationUserName: accountToken,
      );
    } else if (defaultTargetPlatform == TargetPlatform.android &&
        offer.product is GooglePlayProductDetails) {
      accountToken = _auth.obfuscatedAccountId();
      final product = offer.product as GooglePlayProductDetails;
      purchaseParam = GooglePlayPurchaseParam(
        productDetails: product,
        offerToken: product.offerToken,
        applicationUserName: accountToken,
      );
    } else {
      throw StateError('Pro satın alma bu cihazda kullanılamıyor.');
    }
    final started = await _store.buyNonConsumable(purchaseParam: purchaseParam);
    if (!started) {
      throw StateError('${ProProducts.storeName} ödeme sayfası açılamadı.');
    }
  }

  @override
  Future<void> restore() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      throw StateError('Mağaza geri yükleme bu cihazda kullanılamıyor.');
    }
    final accountToken = defaultTargetPlatform == TargetPlatform.iOS
        ? await _appleAccountToken()
        : _auth.obfuscatedAccountId();
    await _store.restorePurchases(applicationUserName: accountToken);
  }

  void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (ProProducts.premiumIds.contains(purchase.productID)) {
        unawaited(_verifyPurchase(purchase));
      }
    }
  }

  Future<void> _verifyPurchase(PurchaseDetails purchase) async {
    if (purchase.status == PurchaseStatus.pending) {
      final current = _account;
      if (current != null) {
        _account = PremiumAccountSnapshot(
          plan: current.plan,
          status: PremiumSubscriptionStatus.pending,
          periodEndsAt: current.periodEndsAt,
          priceUsage: current.priceUsage,
          nearbyUsage: current.nearbyUsage,
        );
        notifyListeners();
      }
      return;
    }
    if (purchase.status == PurchaseStatus.error ||
        purchase.status == PurchaseStatus.canceled) {
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
      await refresh();
      return;
    }
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        if (purchase is! GooglePlayPurchaseDetails) {
          debugPrint('[Premium] Google Play işlem ayrıntısı eksik.');
          return;
        }
        final purchaseToken = purchase.billingClientPurchase.purchaseToken;
        if (purchaseToken.isEmpty) {
          debugPrint('[Premium] Google Play satın alma belirteci eksik.');
          return;
        }
        await _request(
          '/api/premium/google/verify',
          method: 'POST',
          body: {'purchaseToken': purchaseToken},
        );
      } else {
        final transactionId = purchase.purchaseID;
        if (transactionId == null || transactionId.isEmpty) {
          debugPrint('[Premium] App Store işlem kimliği eksik.');
          return;
        }
        await _request(
          '/api/premium/apple/verify',
          method: 'POST',
          body: {'transactionId': transactionId},
        );
      }
      await refresh();
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
    } catch (error) {
      // Do not finish an unverified transaction; the store will redeliver it.
      debugPrint('[Premium] sunucu doğrulaması başarısız: $error');
    }
  }

  @override
  void dispose() {
    unawaited(_purchaseSubscription.cancel());
    _client.close();
    super.dispose();
  }
}
