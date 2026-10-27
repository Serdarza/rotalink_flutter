import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotalink_flutter/billing/price_access.dart';
import 'package:rotalink_flutter/data/facility_price_repository.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';
import 'package:rotalink_flutter/theme/app_theme.dart';
import 'package:rotalink_flutter/utils/best_value_facility.dart';
import 'package:rotalink_flutter/widgets/best_value_pro_card.dart';
import 'package:rotalink_flutter/widgets/custom_search_bar.dart';
import 'package:rotalink_flutter/widgets/main_map_search_chrome.dart';
import 'package:rotalink_flutter/widgets/search_results_ui.dart';
import 'package:rotalink_flutter/widgets/facility_location_filter_bar.dart';
import 'package:rotalink_flutter/screens/search_hub_screen.dart';
import 'package:rotalink_flutter/data/favorites_repository.dart';
import 'package:rotalink_flutter/data/firebase_rota_repository.dart';
import 'package:rotalink_flutter/map_location_state.dart';
import 'package:rotalink_flutter/models/gezi_yemek_item.dart';
import 'package:rotalink_flutter/providers/facility_filter_provider.dart';
import 'package:rotalink_flutter/widgets/misafirhane_search_results_sheet.dart';

const fixture = Misafirhane(
  isim: 'Test Öğretmenevi',
  il: 'Düzce',
  ilce: 'Merkez',
  adres: '',
  telefon: '',
  latitude: 40.83,
  longitude: 31.16,
  tip: 'Öğretmenevi',
);
Misafirhane namedFixture(String name) => Misafirhane(
  isim: name,
  il: fixture.il,
  ilce: fixture.ilce,
  adres: '',
  telefon: '',
  latitude: fixture.latitude,
  longitude: fixture.longitude,
  tip: fixture.tip,
);

class SearchRepository extends FirebaseRotaRepository {
  @override
  RotaDataState get currentState => const RotaDataState(
    misafirhaneler: [fixture],
    initialLoadCompleted: true,
  );
  @override
  Stream<RotaDataState> watchRoot() => Stream.value(currentState);
}

Widget app(Widget child, {bool dark = false, double scale = 1}) =>
    ProviderScope(
      child: MaterialApp(
        theme: dark ? buildRotalinkDarkTheme() : buildRotalinkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Düzce sonuçlarında dört tür, sabit yakınlık, ilçe ve kategori bağlantıları',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FacilityPriceRepository.instance.applyJsonString('{"tesisler":[]}');
      SharedPreferences.setMockInitialValues({
        'rotalink_facility_sort_by_price': true,
      });
      const second = Misafirhane(
        isim: 'Akçakoca Test Polisevi',
        il: 'Düzce',
        ilce: 'Akçakoca',
        adres: '',
        telefon: '',
        latitude: 41.08,
        longitude: 31.13,
        tip: 'Polisevi',
      );
      final container = ProviderContainer();
      container.read(searchPanelFacilitiesSourceProvider.notifier).state = [
        fixture,
        second,
      ];
      final location = MapLocationState();
      var listVisible = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildRotalinkTheme(),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, update) => SizedBox.expand(
                  child: MisafirhaneSearchResultsPanel(
                    listVisible: listVisible,
                    topInset: 0,
                    onViewModeChanged: (value) =>
                        update(() => listVisible = value),
                    rotaData: const RotaDataState(
                      misafirhaneler: [fixture, second],
                      gezi: [
                        GeziYemekItem(
                          il: 'Düzce',
                          isim: 'Düzce Test Gezi',
                          adres: 'Merkez',
                          aciklama: '',
                          enlem: 40.83,
                          boylam: 31.16,
                        ),
                        GeziYemekItem(
                          il: 'Ankara',
                          isim: 'Ankara Test Gezi',
                          adres: '',
                          aciklama: '',
                          enlem: 39.9,
                          boylam: 32.8,
                        ),
                      ],
                      yemek: [
                        GeziYemekItem(
                          il: 'Düzce',
                          isim: 'Düzce Test Yemek',
                          adres: '',
                          aciklama: '',
                        ),
                      ],
                    ),
                    mapLocationState: location,
                    favoritesRepo: FavoritesRepository(),
                    onFavoritesChanged: () async {},
                    onTesisSelect: (_) async {},
                    onClosePanel: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text("Düzce'de Konaklama"), findsOneWidget);
      expect(find.text('2 tesis bulundu'), findsOneWidget);
      expect(find.text(fixture.isim), findsOneWidget);
      expect(find.text(second.isim), findsOneWidget);
      await tester.tap(find.text('Filtrele'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'panel adımı 1');
      expect(
        tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .map((chip) => (chip.label as Text).data)
            .toList(),
        ['Tümü', 'Orduevi', 'Öğretmenevi', 'Polisevi'],
      );
      expect(find.textContaining('Sıralama:'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'Polisevi'));
      await tester.pump();
      expect(
        container.read(filteredTesisListProvider).single.isim,
        second.isim,
      );
      await tester.tap(find.text('Sonuçları Göster'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'panel adımı 2');
      expect(find.text('1 tesis bulundu'), findsOneWidget);
      await tester.tap(find.text('Filtrele'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'panel adımı 3');
      await tester.ensureVisible(find.text('Filtreleri Temizle'));
      await tester.tap(find.text('Filtreleri Temizle'));
      await tester.pump();
      await tester.tap(find.text('Sonuçları Göster'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'panel adımı 4');
      await tester.tap(find.text('Tüm ilçeler'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'panel adımı 5');
      await tester.tap(find.text('Akçakoca').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'panel adımı 6');
      expect(
        container.read(filteredTesisListProvider).single.isim,
        second.isim,
      );
      container.read(facilityIlceFilterProvider.notifier).state = null;
      await tester.pump();
      expect(find.textContaining('Sıralama:'), findsNothing);
      location.update(const LatLng(41.09, 31.14), true);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text(second.isim)).dy,
        lessThan(tester.getTopLeft(find.text(fixture.isim)).dy),
      );
      location.update(const LatLng(40.83, 31.16), true);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text(fixture.isim)).dy,
        lessThan(tester.getTopLeft(find.text(second.isim)).dy),
      );
      location.update(null, false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Konumunuzdan'), findsNothing);
      await tester.tap(find.text('Harita'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'panel adımı 7');
      expect(listVisible, false);
      await tester.tap(find.text('Liste'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'panel adımı 8');
      expect(listVisible, true);
      await tester.tap(find.text('Gezi').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'panel adımı 9');
      expect(find.text("Düzce'de Gezi"), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ViewToggle',
        ),
        findsNothing,
      );
      expect(find.text('Düzce Test Gezi'), findsOneWidget);
      expect(find.text('Ankara Test Gezi'), findsNothing);
      await tester.tap(find.text('Yemek').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'panel adımı 10');
      expect(find.text('Düzce Test Yemek'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ViewToggle',
        ),
        findsNothing,
      );
      await tester.tap(find.text('Tesisler').first);
      await tester.pumpAndSettle();
      expect(find.text("Düzce'de Tesisler"), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ViewToggle',
        ),
        findsNothing,
      );
      await tester.tap(find.text('Daha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hediyelik').last);
      await tester.pumpAndSettle();
      expect(find.text("Düzce'de Hediyelik"), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ViewToggle',
        ),
        findsNothing,
      );
      await tester.tap(find.text('Konaklama').first);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ViewToggle',
        ),
        findsOneWidget,
      );
      expect(find.text('Sıralama:\nÖnerilen'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      container.dispose();
      location.dispose();
    },
  );

  test('İl başlığı Türkçe ek kullanır; arama verisine dokunmaz', () {
    expect(searchProvinceLocative('Düzce'), "Düzce'de");
    expect(searchProvinceLocative('Ankara'), "Ankara'da");
    expect(searchProvinceLocative('Zonguldak'), "Zonguldak'ta");
  });

  testWidgets('Mesafe yalnız gerçek konum ve izinle görünür; kart açılır', (
    tester,
  ) async {
    var opened = 0;
    Widget card(bool permission, LatLng? point) => SearchFacilityResultCard(
      name: fixture.isim,
      location: 'Düzce / Merkez',
      hasPrice: true,
      locationPermissionGranted: permission,
      userLocation: const LatLng(40.8, 31.1),
      facilityPoint: point,
      onTap: () => opened++,
    );
    await tester.pumpWidget(app(card(false, const LatLng(40.83, 31.16))));
    expect(find.textContaining('(Kuş Uçuşu)'), findsNothing);
    expect(find.text('Fiyat Bilgisi'), findsOneWidget);
    await tester.tap(find.text(fixture.isim));
    expect(opened, 1);
    await tester.pumpWidget(app(card(true, const LatLng(40.83, 31.16))));
    expect(find.textContaining('Konumunuzdan · (Kuş Uçuşu)'), findsOneWidget);
    await tester.pumpWidget(app(card(true, null)));
    expect(find.textContaining('(Kuş Uçuşu)'), findsNothing);
    await tester.pumpWidget(app(card(true, const LatLng(0, 0))));
    expect(find.textContaining('(Kuş Uçuşu)'), findsNothing);
  });

  testWidgets('Dar ekran / büyük yazı / temalarda normal ve PRO kart taşmaz', (
    tester,
  ) async {
    for (final width in [320.0, 390.0, 600.0]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            app(
              Column(
                children: [
                  SearchFacilityResultCard(
                    name: 'Çok Uzun İsimli Kamu Konaklama ve Eğitim Tesisi',
                    location: 'Düzce / Akçakoca',
                    hasPrice: true,
                    locationPermissionGranted: true,
                    userLocation: const LatLng(38.7, 35.4),
                    facilityPoint: const LatLng(40.8, 31.1),
                    onTap: () {},
                  ),
                  BestValueProCard(
                    pick: const BestValuePick(
                      facility: fixture,
                      price: 1234,
                      basis: BestValueBasis.sivil,
                      comparedCount: 2,
                      il: 'Düzce',
                    ),
                    onOpenFacility: () {},
                  ),
                ],
              ),
              dark: dark,
              scale: scale,
            ),
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$width / $dark / $scale',
          );
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'Arama tek yüzey, sabit doğru ipucu; temizle ve mikrofon korunur',
    (tester) async {
      final controller = TextEditingController();
      var cleared = 0;
      var closeRequests = 0;
      await tester.pumpWidget(
        app(
          CustomSearchBar(
            controller: controller,
            restrained: true,
            onSearchCleared: () => cleared++,
            onClearPressed: () => closeRequests++,
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.hintText, 'İl veya misafirhane ara...');
      expect(field.decoration!.filled, false);
      expect(field.decoration!.enabledBorder, InputBorder.none);
      expect(find.byTooltip('Sesli ara'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Düzce');
      await tester.pump();
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(closeRequests, 0);
      await tester.enterText(find.byType(TextField), 'Düzce');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(cleared, 2);
      expect(closeRequests, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'kompakt filtrede il ilçe solundadır ve il seçimi mevcut aramaya gider',
    (tester) async {
      const ankara = Misafirhane(
        isim: 'Ankara Test',
        il: 'Ankara',
        ilce: 'Çankaya',
        adres: '',
        telefon: '',
        latitude: 39.9,
        longitude: 32.8,
        tip: 'Öğretmenevi',
      );
      final container = ProviderContainer();
      container.read(searchPanelFacilitiesSourceProvider.notifier).state = [
        fixture,
      ];
      String? selected;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildRotalinkTheme(),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: FacilityLocationFilterBar(
                  allFacilities: const [fixture, ankara],
                  districtOnly: true,
                  onSelectIl: (il) => selected = il,
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('İl')).dx,
        lessThan(tester.getTopLeft(find.text('İlçe')).dx),
      );
      expect(find.text('Düzce'), findsOneWidget);
      expect(find.text('Tüm ilçeler'), findsOneWidget);
      await tester.tap(find.text('Düzce'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ankara'));
      await tester.pumpAndSettle();
      expect(selected, 'Ankara');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  testWidgets(
    'Ara başlangıcında çarpı sorguyu temizler ve ana sayfa dönüşünü çağırır',
    (tester) async {
      var home = 0;
      var queries = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildRotalinkTheme(),
          home: Scaffold(
            body: SearchHubScreen(
              repository: SearchRepository(),
              onBack: () => home++,
              onQuery: (_) => queries++,
              onCategory: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Düzce');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(home, 1);
      expect(queries, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Sonuç kromunda tür satırı yok; normal haritada korunur', (
    tester,
  ) async {
    final controller = TextEditingController();
    Widget chrome(bool compact) => app(
      SizedBox(
        height: 150,
        child: Stack(
          children: [
            MainMapSearchChrome(
              top: 0,
              searchBarSession: 0,
              controller: controller,
              ilOptionsSorted: null,
              compactResults: compact,
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(chrome(true));
    expect(find.text('Orduevi'), findsNothing);
    await tester.pumpWidget(chrome(false));
    expect(find.text('Orduevi'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('PRO kilidinde gerçek ad ve fiyat widget/semantiğe sızmaz', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        BestValueProCard(
          pick: const BestValuePick(
            facility: fixture,
            price: 1234,
            basis: BestValueBasis.sivil,
            comparedCount: 2,
            il: 'Düzce',
          ),
          onOpenFacility: () {},
        ),
      ),
    );
    if (PriceAccess.unlocked) {
      expect(find.text(fixture.isim), findsOneWidget);
      expect(find.text('Tesisi İncele'), findsOneWidget);
    } else {
      expect(find.text(fixture.isim), findsNothing);
      expect(find.textContaining('1.234'), findsNothing);
    }
  });

  test(
    'Fiyat yönü değişince eşit fiyat sırası korunur, fiyatsızlar ayrı kalır',
    () {
      final records = [
        fixture,
        namedFixture('İkinci'),
        namedFixture('Üçüncü'),
        namedFixture('Bilinmeyen'),
      ];
      FacilityPriceRepository.instance.applyJsonString(
        jsonEncode({
          'tesisler': [
            for (final (index, record) in records.take(3).indexed)
              {
                'il': record.il,
                'isim': record.isim,
                'tarife': {
                  'kategoriler': [
                    {'id': 'sivil', 'ad': 'Sivil misafir'},
                  ],
                  'tablolar': [
                    {
                      'satirlar': [
                        {
                          'ad': 'Tek Kişilik Oda',
                          'kisi': 1,
                          'fiyatlar': {'sivil': index == 0 ? 100 : 200},
                        },
                      ],
                    },
                  ],
                },
              },
          ],
        }),
      );
      final asc = splitFacilitiesByPrice(
        records,
        BestValueBasis.sivil,
        sortByPrice: true,
      );
      final desc = splitFacilitiesByPrice(
        records,
        BestValueBasis.sivil,
        sortByPrice: true,
        descending: true,
      );
      expect(asc.priced.map((e) => e.$2.amount), [100, 200, 200]);
      expect(desc.priced.map((e) => e.$1.isim), [
        'İkinci',
        'Üçüncü',
        fixture.isim,
      ]);
      expect(desc.unpriced.single.isim, 'Bilinmeyen');
    },
  );
}
