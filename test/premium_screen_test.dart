import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:rotalink_flutter/billing/premium_presentation.dart';
import 'package:rotalink_flutter/billing/pro_products.dart';
import 'package:rotalink_flutter/screens/pro_screen.dart';
import 'package:rotalink_flutter/theme/app_theme.dart';
import 'package:rotalink_flutter/widgets/premium_usage_widgets.dart';

class _Controller extends PremiumUiController {
  _Controller(this.state);
  @override
  PremiumUiState state;
  int restoreCalls = 0, refreshCalls = 0, manageCalls = 0;
  PremiumPlan? purchased;
  @override
  Stream<String> get messages => const Stream.empty();
  @override
  Future<void> refresh() async {
    refreshCalls++;
  }

  @override
  Future<void> restore() async {
    restoreCalls++;
  }

  @override
  Future<void> manageSubscription() async {
    manageCalls++;
  }

  @override
  Future<void> purchase(PremiumPlan plan) async {
    purchased = plan;
  }
}

GooglePlayProductDetails _androidProduct(
  PremiumPlan plan, {
  String? period,
  String? offerId,
  RecurrenceMode recurrence = RecurrenceMode.infiniteRecurring,
}) => GooglePlayProductDetails.fromProductDetails(
  ProductDetailsWrapper(
    description: 'Monthly test subscription',
    name: 'Store ${plan.label}',
    productId: plan.productId,
    productType: ProductType.subs,
    title: 'Mağaza ${plan.label}',
    subscriptionOfferDetails: [
      SubscriptionOfferDetailsWrapper(
        basePlanId: 'monthly',
        offerId: offerId,
        offerTags: const [],
        offerIdToken: 'test-only-offer',
        pricingPhases: [
          PricingPhaseWrapper(
            billingCycleCount: 0,
            billingPeriod: period ?? (plan.yearly ? 'P1Y' : 'P1M'),
            formattedPrice: '€12,34',
            priceAmountMicros: 12340000,
            priceCurrencyCode: 'EUR',
            recurrenceMode: recurrence,
          ),
        ],
      ),
    ],
  ),
).single;

AppStoreProductDetails _appleProduct({int months = 1}) =>
    AppStoreProductDetails.fromSKProduct(
      SKProductWrapper(
        productIdentifier: PremiumPlan.gold.productId,
        localizedTitle: 'Store Gold',
        localizedDescription: 'Test monthly',
        priceLocale: SKPriceLocaleWrapper(
          currencySymbol: '€',
          currencyCode: 'EUR',
          countryCode: 'DE',
        ),
        price: '12.34',
        subscriptionPeriod: SKProductSubscriptionPeriodWrapper(
          numberOfUnits: months,
          unit: SKSubscriptionPeriodUnit.month,
        ),
      ),
    );

AppStoreProduct2Details _apple2Product({bool renewable = true}) =>
    AppStoreProduct2Details.fromSK2Product(
      SK2Product(
        id: PremiumPlan.gold.productId,
        displayName: 'Store Platinum',
        displayPrice: r'$19.87',
        description: 'Test subscription',
        price: 19.87,
        type: renewable
            ? SK2ProductType.autoRenewable
            : SK2ProductType.nonRenewable,
        priceLocale: SK2PriceLocale(currencyCode: 'USD', currencySymbol: r'$'),
        subscription: const SK2SubscriptionInfo(
          subscriptionGroupID: 'test-group',
          promotionalOffers: [],
          subscriptionPeriod: SK2SubscriptionPeriod(
            value: 1,
            unit: SK2SubscriptionPeriodUnit.month,
          ),
        ),
      ),
    );

Map<PremiumPlan, PremiumStoreOffer> _offers() => {
  for (final plan in PremiumPlan.values)
    if (plan.offered)
      plan: PremiumStoreOffer.fromProduct(_androidProduct(plan))!,
};

Future<void> _show(
  WidgetTester tester,
  _Controller controller, {
  bool dark = false,
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? buildRotalinkDarkTheme() : buildRotalinkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ProScreen(controller: controller),
    ),
  );
  await tester.pump();
}

void main() {
  test('new product IDs do not replace the two legacy IDs', () {
    expect(PremiumPlan.productIds, {
      'rotalink_silver_monthly',
      'rotalink_gold_monthly',
      'rotalink_platinum_yearly',
    });
    expect(PremiumPlan.legacyPlatinum.productId, 'rotalink_platinum_monthly');
    expect(ProProducts.ids, {'rotalink_pro_monthly', 'rotalink_pro_yearly'});
  });

  test('monthly base plan uses native localized price and period', () {
    final product = _androidProduct(PremiumPlan.gold);
    final offer = PremiumStoreOffer.fromProduct(product)!;
    expect(offer.product.price, '€12,34');
    expect(offer.product.currencyCode, 'EUR');
    expect(offer.periodLabel, '1 ay');
    expect(
      PremiumStoreOffer.fromProduct(_androidProduct(PremiumPlan.platinum))
          ?.periodLabel,
      '1 yıl',
    );
    expect(
      PremiumStoreOffer.fromProduct(
        _androidProduct(PremiumPlan.platinum, period: 'P1M'),
      ),
      isNull,
    );
    expect(
      PremiumStoreOffer.fromProduct(
        _androidProduct(PremiumPlan.gold, period: 'P1Y'),
      ),
      isNull,
    );
    expect(
      PremiumStoreOffer.fromProduct(
        _androidProduct(PremiumPlan.gold, offerId: 'trial'),
      ),
      isNull,
    );
    expect(
      PremiumStoreOffer.fromProduct(
        _androidProduct(
          PremiumPlan.gold,
          recurrence: RecurrenceMode.nonRecurring,
        ),
      ),
      isNull,
    );
  });

  test(
    'StoreKit 1 and 2 read periods instead of assuming monthly from SKU',
    () {
      expect(
        PremiumStoreOffer.fromProduct(_appleProduct())?.periodLabel,
        '1 ay',
      );
      expect(PremiumStoreOffer.fromProduct(_appleProduct(months: 12)), isNull);
      expect(
        PremiumStoreOffer.fromProduct(_apple2Product())?.product.price,
        r'$19.87',
      );
      expect(
        PremiumStoreOffer.fromProduct(_apple2Product(renewable: false)),
        isNull,
      );
    },
  );

  test('store prices alone cannot enable unverified new purchases', () {
    final offers = _offers();
    final state = PremiumUiState(
      catalogPhase: PremiumCatalogPhase.ready,
      offers: offers,
      purchasablePlans: PremiumPlan.values.toSet(),
    );
    for (final plan in PremiumPlan.values) {
      expect(state.canPurchase(plan), isFalse);
    }
  });

  for (final dark in [false, true]) {
    for (final layout in [(320.0, 1.0), (320.0, 1.8), (1024.0, 1.4)]) {
      testWidgets('plans fit ${layout.$1} scale ${layout.$2}, dark=$dark', (
        tester,
      ) async {
        final controller = _Controller(
          PremiumUiState(
            catalogPhase: PremiumCatalogPhase.ready,
            offers: _offers(),
          ),
        );
        addTearDown(controller.dispose);
        await _show(
          tester,
          controller,
          dark: dark,
          width: layout.$1,
          textScale: layout.$2,
        );
        expect(find.text('Rotalink Pro'), findsOneWidget);
        expect(find.text('Gümüş Pro'), findsOneWidget);
        expect(find.text('Altın Pro'), findsOneWidget);
        expect(find.text('Platin Pro'), findsOneWidget);
        expect(find.text('ÖNERİLEN PAKET'), findsOneWidget);
        expect(find.text('€12,34'), findsNWidgets(3));
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('Aboneliği başlat'), findsOneWidget);
        final buy = tester.widget<FilledButton>(
          find.byKey(const ValueKey('premium-buy-gold')),
        );
        expect(buy.onPressed, isNull);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('missing products and catalog errors never invent a price', (
    tester,
  ) async {
    final controller = _Controller(
      const PremiumUiState(
        catalogPhase: PremiumCatalogPhase.error,
        catalogMessage: 'Paket fiyatları yüklenemedi.',
      ),
    );
    addTearDown(controller.dispose);
    await _show(tester, controller);
    expect(find.text('Fiyat şu anda alınamıyor'), findsNWidgets(3));
    expect(find.text('99 TL'), findsNothing);
    expect(find.text('12/35 kullanıldı'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('premium-buy-gold')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('account service supplies usage and correct purchase callback', (
    tester,
  ) async {
    final controller = _Controller(
      PremiumUiState(
        catalogPhase: PremiumCatalogPhase.ready,
        offers: _offers(),
        account: PremiumAccountSnapshot(
          plan: PremiumPlan.gold,
          status: PremiumSubscriptionStatus.active,
          periodEndsAt: DateTime(2026, 12, 10),
          priceUsage: const PremiumQuotaSnapshot(
            total: 35,
            used: 12,
            remaining: 23,
          ),
          nearbyUsage: const PremiumQuotaSnapshot(
            total: 7,
            used: 3,
            remaining: 4,
          ),
        ),
        purchasablePlans: {PremiumPlan.platinum},
      ),
    );
    addTearDown(controller.dispose);
    await _show(tester, controller);
    expect(
      find.text('Fiyat görüntüleme: 35 hakkınız var. 12 kullandınız, 23 kaldı.'),
      findsOneWidget,
    );
    expect(
      find.text('Yakın tesis araması: 7 hakkınız var. 3 kullandınız, 4 kaldı.'),
      findsOneWidget,
    );
    expect(find.textContaining('10.12.2026'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('premium-buy-gold')))
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('Platin Pro'));
    await tester.tap(find.text('Platin Pro'));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('premium-buy-platinum')),
    );
    await tester.tap(find.byKey(const ValueKey('premium-buy-platinum')));
    await tester.pump();
    expect(controller.purchased, PremiumPlan.platinum);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy Pro and gifts retain their presentation and restore action',
    (tester) async {
      final controller = _Controller(
        PremiumUiState(
          catalogPhase: PremiumCatalogPhase.ready,
          offers: _offers(),
          legacy: LegacyProSnapshot(
            active: true,
            productId: ProProducts.yearly,
            estimatedEnd: DateTime(2027, 1, 10),
            giftEnd: DateTime(2026, 12, 2),
          ),
        ),
      );
      addTearDown(controller.dispose);
      await _show(tester, controller);
      expect(
        find.byKey(const ValueKey('legacy-pro-membership')),
        findsOneWidget,
      );
      expect(find.textContaining('Yıllık Pro'), findsOneWidget);
      expect(
        find.textContaining('Hediye Pro erişiminiz 02.12.2026'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('premium-restore')));
      await tester.tap(find.byKey(const ValueKey('premium-restore')));
      await tester.pump();
      expect(controller.restoreCalls, 1);
      expect(controller.purchased, isNull);
    },
  );

  testWidgets(
    'nearby quota notice appears only for an exhausted service quota',
    (tester) async {
      const account = PremiumAccountSnapshot(
        plan: null,
        status: PremiumSubscriptionStatus.active,
        nearbyUsage: PremiumQuotaSnapshot(total: 1, used: 0, remaining: 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PremiumLimitNotice(
              account: account,
              feature: PremiumLimitedFeature.nearby,
              onChoosePlan: () {},
            ),
          ),
        ),
      );
      expect(find.text('Daha Fazla Konum Keşfedin'), findsNothing);
      const exhausted = PremiumAccountSnapshot(
        plan: null,
        status: PremiumSubscriptionStatus.active,
        nearbyUsage: PremiumQuotaSnapshot(total: 1, used: 1, remaining: 0),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PremiumLimitNotice(
              account: exhausted,
              feature: PremiumLimitedFeature.nearby,
              onChoosePlan: () {},
            ),
          ),
        ),
      );
      expect(find.text('Daha Fazla Konum Keşfedin'), findsOneWidget);
    },
  );

  testWidgets('existing pro route pops back without changing navigation', (
    tester,
  ) async {
    final controller = _Controller(
      const PremiumUiState(catalogPhase: PremiumCatalogPhase.unavailable),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.pushNamed(context, '/pro'),
              child: const Text('Paketler'),
            ),
          ),
        ),
        routes: {'/pro': (_) => ProScreen(controller: controller)},
      ),
    );
    await tester.tap(find.text('Paketler'));
    await tester.pumpAndSettle();
    expect(find.text('Rotalink Pro'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Paketler'), findsOneWidget);
  });
}
