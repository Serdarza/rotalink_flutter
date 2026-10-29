import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pro_products.dart';
import 'pro_service.dart';
import 'free_price_quota.dart';

/// Presentation of the future plans, not an entitlement or quota authority.
enum PremiumPlan {
  silver('Gümüş', 'rotalink_silver_monthly', 7, 3, false, 'Tek seyahat için'),
  gold('Altın', 'rotalink_gold_monthly', 25, 7, false, 'Detaylı karşılaştırma'),
  platinum(
    'Platin',
    'rotalink_platinum_yearly',
    null,
    12,
    true,
    'Yıl boyu kullanım',
  ),
  legacyPlatinum(
    'Platin',
    'rotalink_platinum_monthly',
    150,
    20,
    false,
    'Mevcut aylık abonelik',
  );

  const PremiumPlan(
    this.label,
    this.productId,
    this.priceViews,
    this.nearbySearches,
    this.yearly,
    this.pitch,
  );
  final String label;
  final String productId;

  /// Null means price views are unlimited.
  final int? priceViews;
  final int nearbySearches;
  final bool yearly;
  final String pitch;

  bool get offered => this != legacyPlatinum;
  String get title => '$label Pro';

  static Set<String> get productIds => ProProducts.premiumIds;

  static PremiumPlan? fromSku(String sku) {
    for (final plan in values) {
      if (plan.productId == sku) return plan;
    }
    return null;
  }
}

/// Admin ekranından değişen hak sayıları. Mağaza fiyatı burada yoktur.
class PremiumPlanRights {
  const PremiumPlanRights({
    required this.priceViews,
    required this.nearbySearches,
  });

  final int? priceViews;
  final int nearbySearches;

  String get line {
    final prices = priceViews == null
        ? 'Sınırsız tesis fiyatı'
        : 'Ayda $priceViews tesis fiyatı';
    return '$prices · Ayda $nearbySearches yakın arama';
  }
}

class PremiumRightsCatalog {
  PremiumRightsCatalog._();

  static final PremiumRightsCatalog instance = PremiumRightsCatalog._();
  static final Uri _uri = Uri.parse(
    'https://admin.rotalink.tr/api/premium/plans',
  );
  final Map<String, PremiumPlanRights> _remote = {};
  int _freePrices = 1;
  int _freeNearby = 1;
  DateTime? _loadedAt;
  Future<void>? _loading;

  int get freePrices => _freePrices;
  int get freeNearby => _freeNearby;

  PremiumPlanRights of(PremiumPlan plan) =>
      _remote[plan.productId] ??
      PremiumPlanRights(
        priceViews: plan.priceViews,
        nearbySearches: plan.nearbySearches,
      );

  Future<void> refresh({bool force = false}) {
    final loaded = _loadedAt;
    if (!force &&
        loaded != null &&
        DateTime.now().difference(loaded) < const Duration(minutes: 5)) {
      return Future<void>.value();
    }
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      final response = await http
          .get(_uri, headers: const {'accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final value = jsonDecode(response.body);
      if (value is! Map || value['plans'] is! List) return;
      final next = <String, PremiumPlanRights>{};
      for (final item in value['plans'] as List) {
        if (item is! Map) continue;
        final sku = item['sku'];
        final nearby = item['nearby'];
        final prices = item['prices'];
        if (sku is! String || nearby is! num) continue;
        if (prices != null && prices is! num) continue;
        next[sku] = PremiumPlanRights(
          priceViews: prices is num ? prices.toInt() : null,
          nearbySearches: nearby.toInt(),
        );
      }
      final free = value['free'];
      if (free is Map) {
        final prices = free['prices'];
        final nearby = free['nearby'];
        if (prices is num && prices >= 0 && prices <= 100) {
          _freePrices = prices.toInt();
        }
        if (nearby is num && nearby >= 0 && nearby <= 100) {
          _freeNearby = nearby.toInt();
        }
      }
      _remote
        ..clear()
        ..addAll(next);
      _loadedAt = DateTime.now();
      FreePriceQuota.instance.applyServerLimit(_freePrices);
    } catch (error) {
      debugPrint('[Premium] hak listesi alınamadı: $error');
    }
  }
}

enum PremiumCatalogPhase { loading, ready, unavailable, error }

enum PremiumSubscriptionStatus { active, renewalOff, pending, expired }

enum PremiumLimitedFeature { prices, nearby }

/// All three values come from the account service. No consumption/reset here.
@immutable
class PremiumQuotaSnapshot {
  const PremiumQuotaSnapshot({
    required this.total,
    required this.used,
    required this.remaining,
    this.unlimited = false,
  }) : assert(total >= 0),
       assert(used >= 0),
       assert(remaining >= 0);

  final int total;
  final int used;
  final int remaining;
  final bool unlimited;
  double get progress =>
      unlimited || total == 0 ? 0 : (used / total).clamp(0.0, 1.0);
}

/// Kullanıcının kaç hakkı olduğunu ve kaçını kullandığını düz Türkçe söyler.
abstract final class RightsWording {
  static String balance({
    required String kind,
    int? total,
    int? remaining,
    int? used,
    bool unlimited = false,
  }) {
    if (unlimited) return '$kind: sınırsız hakkınız var.';
    final allowance = total ?? remaining ?? 0;
    final left = (remaining ?? allowance).clamp(0, allowance);
    final spent = (used ?? (allowance - left)).clamp(0, allowance);
    if (spent == 0) {
      return '$kind: $allowance hakkınız var. Henüz kullanmadınız.';
    }
    if (left == 0) {
      return '$kind: $allowance hakkınız var. $spent kullandınız.';
    }
    return '$kind: $allowance hakkınız var. $spent kullandınız, $left kaldı.';
  }
}

/// Filled only by the future verified account adapter; null means unknown.
@immutable
class PremiumAccountSnapshot {
  const PremiumAccountSnapshot({
    required this.plan,
    required this.status,
    this.periodEndsAt,
    this.priceUsage,
    this.nearbyUsage,
  });

  /// Null represents a Free account, not an unknown account.
  final PremiumPlan? plan;
  final PremiumSubscriptionStatus status;
  final DateTime? periodEndsAt;
  final PremiumQuotaSnapshot? priceUsage;
  final PremiumQuotaSnapshot? nearbyUsage;
  String get name => plan == null ? 'Ücretsiz' : '${plan!.label} Pro';
}

@immutable
class LegacyProSnapshot {
  const LegacyProSnapshot({
    this.active = false,
    this.productId,
    this.estimatedEnd,
    this.giftEnd,
  });
  final bool active;
  final String? productId;
  final DateTime? estimatedEnd;
  final DateTime? giftEnd;
  bool get hasAccess => active || giftEnd != null;
}

@immutable
class PremiumStoreOffer {
  const PremiumStoreOffer({required this.product, required this.periodLabel});
  final ProductDetails product;
  final String periodLabel;

  /// The store reports the billing period. A yearly product must be one year,
  /// and a monthly product must be one month.
  static PremiumStoreOffer? fromProduct(ProductDetails product) {
    final plan = PremiumPlan.fromSku(product.id);
    if (plan == null ||
        !plan.offered ||
        product.price.trim().isEmpty ||
        product.currencyCode.trim().isEmpty ||
        !product.rawPrice.isFinite ||
        product.rawPrice <= 0) {
      return null;
    }
    if (product is GooglePlayProductDetails) {
      final index = product.subscriptionIndex;
      final offers = product.productDetails.subscriptionOfferDetails;
      if (index == null ||
          offers == null ||
          index < 0 ||
          index >= offers.length) {
        return null;
      }
      final offer = offers[index];
      if (offer.offerId?.isNotEmpty == true ||
          offer.pricingPhases.length != 1) {
        return null;
      }
      final phase = offer.pricingPhases.single;
      final period = plan.yearly ? 'P1Y' : 'P1M';
      if (phase.billingPeriod != period ||
          phase.recurrenceMode != RecurrenceMode.infiniteRecurring) {
        return null;
      }
      return PremiumStoreOffer(
        product: product,
        periodLabel: plan.yearly ? '1 yıl' : '1 ay',
      );
    }
    if (product is AppStoreProductDetails) {
      final period = product.skProduct.subscriptionPeriod;
      final unit = plan.yearly ? 'year' : 'month';
      if (period?.unit.name != unit || period?.numberOfUnits != 1) {
        return null;
      }
      return PremiumStoreOffer(
        product: product,
        periodLabel: plan.yearly ? '1 yıl' : '1 ay',
      );
    }
    if (product is AppStoreProduct2Details) {
      final period = product.sk2Product.subscription?.subscriptionPeriod;
      final unit = plan.yearly ? 'year' : 'month';
      if (product.sk2Product.type.name != 'autoRenewable' ||
          period?.unit.name != unit ||
          period?.value != 1) {
        return null;
      }
      return PremiumStoreOffer(
        product: product,
        periodLabel: plan.yearly ? '1 yıl' : '1 ay',
      );
    }
    return null;
  }
}

@immutable
class PremiumUiState {
  const PremiumUiState({
    this.catalogPhase = PremiumCatalogPhase.loading,
    this.offers = const {},
    this.catalogMessage,
    this.account,
    this.legacy = const LegacyProSnapshot(),
    this.purchasablePlans = const {},
    this.purchasePending = false,
    this.restoring = false,
  });
  final PremiumCatalogPhase catalogPhase;
  final Map<PremiumPlan, PremiumStoreOffer> offers;
  final String? catalogMessage;
  final PremiumAccountSnapshot? account;
  final LegacyProSnapshot legacy;
  final Set<PremiumPlan> purchasablePlans;
  final bool purchasePending;
  final bool restoring;

  bool canPurchase(PremiumPlan plan) =>
      catalogPhase == PremiumCatalogPhase.ready &&
      offers[plan]?.product.id == plan.productId &&
      account != null &&
      account?.status != PremiumSubscriptionStatus.pending &&
      purchasablePlans.contains(plan) &&
      !purchasePending &&
      !restoring &&
      !legacy.hasAccess;
}

/// Stage 3 implements this with verified account/checkout services. The UI
/// does not write memberships, grant quotas, or change the existing Pro flag.
abstract class PremiumAccountBridge extends ChangeNotifier {
  PremiumAccountSnapshot? get account;
  Set<PremiumPlan> get purchasablePlans;
  Future<void> refresh();
  Future<void> purchase(PremiumStoreOffer offer);
  Future<void> restore();
}

abstract class PremiumUiController extends ChangeNotifier {
  PremiumUiState get state;
  Stream<String> get messages;
  Future<void> refresh();
  Future<void> purchase(PremiumPlan plan);
  Future<void> restore();
  Future<void> manageSubscription();
}

/// Read-only catalog integration. It intentionally never calls ProService.buy
/// with a new SKU: the legacy handler cannot grant the new products yet.
class StorePremiumUiController extends PremiumUiController {
  StorePremiumUiController({PremiumAccountBridge? accountBridge})
    : _legacy = ProService.instance,
      _bridge = accountBridge {
    _legacy.isPro.addListener(_changed);
    _legacy.expiryAt.addListener(_changed);
    _legacy.legacyGiftEndsAt.addListener(_changed);
    _legacy.purchasePending.addListener(_changed);
    _bridge?.addListener(_changed);
  }
  final ProService _legacy;
  final PremiumAccountBridge? _bridge;
  PremiumCatalogPhase _phase = PremiumCatalogPhase.loading;
  Map<PremiumPlan, PremiumStoreOffer> _offers = const {};
  String? _catalogMessage;
  bool _disposed = false, _restoring = false, _purchasing = false;
  Future<void>? _refreshTask;

  @override
  Stream<String> get messages => _legacy.messages;

  @override
  PremiumUiState get state => PremiumUiState(
    catalogPhase: _phase,
    offers: _offers,
    catalogMessage: _catalogMessage,
    account: _bridge?.account,
    purchasablePlans: _bridge?.purchasablePlans ?? const {},
    legacy: LegacyProSnapshot(
      active: _legacy.hasProAccess && _legacy.isPro.value,
      productId: _legacy.activeProductId,
      estimatedEnd: _legacy.expiryAt.value,
      giftEnd: _legacy.legacyGiftActive ? _legacy.legacyGiftEndsAt.value : null,
    ),
    purchasePending: _purchasing || _legacy.purchasePending.value,
    restoring: _restoring,
  );

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final current = _refreshTask;
    if (current != null) return current;
    final task = _refreshNow();
    _refreshTask = task;
    return task.whenComplete(() {
      if (identical(_refreshTask, task)) _refreshTask = null;
    });
  }

  Future<void> _refreshNow() async {
    _phase = PremiumCatalogPhase.loading;
    _offers = const {};
    _catalogMessage = null;
    _changed();
    try {
      await PremiumRightsCatalog.instance.refresh(force: true);
      if (kIsWeb ||
          (defaultTargetPlatform != TargetPlatform.android &&
              defaultTargetPlatform != TargetPlatform.iOS &&
              defaultTargetPlatform != TargetPlatform.macOS)) {
        _phase = PremiumCatalogPhase.unavailable;
        _catalogMessage =
            'Paket fiyatlarını Android veya iOS uygulamasında görebilirsiniz.';
        return;
      }
      final store = InAppPurchase.instance;
      if (!await store.isAvailable().timeout(const Duration(seconds: 15))) {
        _phase = PremiumCatalogPhase.unavailable;
        _catalogMessage =
            'Mağazaya ulaşılamıyor. Bağlantınızı kontrol edip tekrar deneyin.';
        return;
      }
      final response = await store
          .queryProductDetails(PremiumPlan.productIds)
          .timeout(const Duration(seconds: 20));
      if (response.error != null) throw StateError('catalog query failed');
      final offers = <PremiumPlan, PremiumStoreOffer>{};
      for (final plan in PremiumPlan.values.where((plan) => plan.offered)) {
        final matches = response.productDetails
            .where((p) => p.id == plan.productId)
            .map(PremiumStoreOffer.fromProduct)
            .whereType<PremiumStoreOffer>()
            .toList();
        // Multiple monthly base plans need an explicit choice by the adapter.
        if (matches.length == 1) offers[plan] = matches.single;
      }
      _offers = Map.unmodifiable(offers);
      _phase = PremiumCatalogPhase.ready;
      if (_offers.length !=
          PremiumPlan.values.where((plan) => plan.offered).length) {
        _catalogMessage = 'Bazı paketlerin fiyatı mağazadan alınamadı.';
      }
    } catch (_) {
      _phase = PremiumCatalogPhase.error;
      _offers = const {};
      _catalogMessage = 'Paket fiyatları yüklenemedi. Lütfen tekrar deneyin.';
    } finally {
      if (_bridge != null && !_disposed) {
        try {
          await _bridge.refresh();
        } catch (_) {
          _catalogMessage ??=
              'Kullanım bilgileri yenilenemedi. Lütfen tekrar deneyin.';
        }
      }
      _changed();
    }
  }

  @override
  Future<void> purchase(PremiumPlan plan) async {
    if (_bridge == null) {
      throw StateError('Bu paket şu anda satın alınamıyor.');
    }
    if (!state.canPurchase(plan)) await refresh();
    if (!state.canPurchase(plan)) {
      throw StateError('Bu paket şu anda satın alınamıyor.');
    }
    _purchasing = true;
    _changed();
    try {
      await _bridge.purchase(_offers[plan]!);
    } finally {
      _purchasing = false;
      _changed();
    }
  }

  @override
  Future<void> restore() async {
    if (_restoring || state.purchasePending) return;
    _restoring = true;
    _changed();
    try {
      if (_bridge != null) {
        await _bridge.restore();
      } else {
        await _legacy.restore();
      }
    } finally {
      _restoring = false;
      _changed();
    }
  }

  @override
  Future<void> manageSubscription() async {
    final id = state.account?.plan?.productId ?? _legacy.activeProductId;
    if (!await launchUrl(
      Uri.parse(ProProducts.manageUrl(id)),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Abonelik yönetim sayfası açılamadı.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _legacy.isPro.removeListener(_changed);
    _legacy.expiryAt.removeListener(_changed);
    _legacy.legacyGiftEndsAt.removeListener(_changed);
    _legacy.purchasePending.removeListener(_changed);
    _bridge?.removeListener(_changed);
    super.dispose();
  }
}
