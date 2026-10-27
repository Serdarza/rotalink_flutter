import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotalink_flutter/billing/price_access.dart';
import 'package:rotalink_flutter/data/facility_compare_selection.dart';
import 'package:rotalink_flutter/data/facility_price_repository.dart';
import 'package:rotalink_flutter/map_location_state.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';
import 'package:rotalink_flutter/services/weather_service.dart';
import 'package:rotalink_flutter/theme/app_theme.dart';
import 'package:rotalink_flutter/widgets/facility_detail_card.dart';
import 'package:rotalink_flutter/widgets/facility_tariff_view.dart';
import 'package:rotalink_flutter/widgets/facility_weather_badge.dart';
import 'package:rotalink_flutter/widgets/facility_overnight_price_box.dart';
import 'package:rotalink_flutter/widgets/stay_cost_calculator_sheet.dart';
import 'package:rotalink_flutter/theme/weather_badge_palette.dart';

const facility = Misafirhane(
  isim: 'Uzun İsimli Örnek Kamu Konaklama ve Eğitim Tesisi',
  il: 'Kayseri',
  ilce: 'Bünyan',
  adres: 'Örnek Mahallesi, Test Caddesi No: 1, Bünyan / Kayseri',
  telefon: '03520000000',
  latitude: 38.85,
  longitude: 35.86,
  tip: 'Öğretmenevi',
);
final tariffFixture = {
  'birim': 'kişi başı / gece',
  'kategoriler': [
    {'id': 'uye', 'ad': 'Üye misafir'},
    {'id': 'diger', 'ad': 'Diğer misafir'},
  ],
  'tablolar': [
    {
      'satirlar': [
        {
          'ad': 'Tek Kişilik Oda',
          'kisi': 1,
          'birim': 'kişi başı',
          'fiyatlar': {'uye': 1234, 'diger': 2345},
        },
      ],
    },
  ],
};
void seedPrices() => FacilityPriceRepository.instance.applyJsonString(
  jsonEncode({
    'tesisler': [
      {'il': facility.il, 'isim': facility.isim, 'tarife': tariffFixture},
    ],
  }),
);

Widget app(Widget child, {bool dark = false}) => MaterialApp(
  theme: dark ? buildRotalinkDarkTheme() : buildRotalinkTheme(),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('tr', 'TR')],
  home: Scaffold(body: child),
);
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FacilityCompareSelection.instance.clear();
    seedPrices();
  });
  tearDown(() {
    FacilityCompareSelection.instance.clear();
    FacilityPriceRepository.instance.applyJsonString('{"tesisler":[]}');
  });
  testWidgets(
    'özet fiyatlar taşmadan minimumu gösterir; kaynak yalnızca ayrıntıda görünür',
    (tester) async {
      if (!PriceAccess.unlocked) return;
      FacilityPriceRepository.instance.applyJsonString(
        jsonEncode({
          'tesisler': [
            {
              'il': facility.il,
              'isim': facility.isim,
              'fiyat_sivil': '1.150 – 3.475 TL',
              'fiyat_kamu_personeli': '850 – 2.650 TL',
              'fiyat_kurum_personeli': '700 – 2.237,50 TL',
              'kaynak': 'https://example.com/official',
              'gecerlilik': '2026 tarifesi',
              'tarife': {
                ...tariffFixture,
                'dogrulama': 'resmi_kaynak',
                'guncelleme': '27.09.2026',
              },
            },
          ],
        }),
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final scale in [1.0, 1.6, 2.0]) {
        tester.view.physicalSize = const Size(320, 900);
        await tester.pumpWidget(
          app(
            MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: SingleChildScrollView(
                child: FacilityOvernightPriceBox(
                  facility: facility,
                  detailPresentation: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final amount in ['1.150 TL', '850 TL', '700 TL']) {
          expect(find.text(amount), findsOneWidget);
        }
        expect(find.text('1.150 – 3.475 TL'), findsNothing);
        expect(find.byType(PriceMetaFooter), findsNothing);
        expect(find.text('Resmî kaynaktan alındı'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      final details = find.text('Detaylı tarifeyi göster');
      await Scrollable.ensureVisible(tester.element(details));
      await tester.tap(details);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(PriceMetaFooter),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byType(PriceMetaFooter), findsOneWidget);
      expect(find.text('Resmî kaynaktan alındı'), findsOneWidget);
      expect(
        FacilityPriceRepository.instance
            .lookup(facility.il, facility.isim)!
            .fiyatSivil,
        '1.150 – 3.475 TL',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'hesaplayıcı modalı alt navigasyonu da kapsar ve arka sayfayı değiştirmez',
    (tester) async {
      final root = GlobalKey<NavigatorState>(),
          nested = GlobalKey<NavigatorState>();
      var navTaps = 0;
      final priced = FacilityPriceRepository.instance.resolveFacility(facility);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: root,
          home: Scaffold(
            bottomNavigationBar: TextButton(
              onPressed: () => navTaps++,
              child: const Text('Rota'),
            ),
            body: Navigator(
              key: nested,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () => showStayCostCalculator(context, priced),
                    child: const Text('Hesapla'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Hesapla'));
      await tester.pumpAndSettle();
      expect(root.currentState!.canPop(), true);
      expect(nested.currentState!.canPop(), false);
      expect(find.text('Tahmini toplam'), findsWidgets);
      await tester.tap(find.text('Rota'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(navTaps, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'detay küçük/büyük ekran ve iki temada uzun metinleri taşırmaz, fotoğraf eklenmez',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const channel =
          'dev.flutter.pigeon.in_app_purchase_android.InAppPurchaseApi.startConnection';
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        channel,
        (_) => Completer<ByteData?>().future,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          channel,
          null,
        ),
      );
      final location = MapLocationState()
        ..update(const LatLng(38.7, 35.5), true);
      addTearDown(location.dispose);
      if (const bool.fromEnvironment('DETAIL_SCREENSHOTS')) {
        await tester.runAsync(() async {
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          final fonts = '${Platform.environment['WINDIR']}/Fonts';
          await (FontLoader('Roboto')
                ..addFont(
                  File(
                    '$fonts/segoeui.ttf',
                  ).readAsBytes().then(ByteData.sublistView),
                )
                ..addFont(
                  File(
                    '$fonts/segoeuib.ttf',
                  ).readAsBytes().then(ByteData.sublistView),
                ))
              .load();
          await (FontLoader('Ahem')
                ..addFont(
                  File(
                    '$fonts/segoeui.ttf',
                  ).readAsBytes().then(ByteData.sublistView),
                )
                ..addFont(
                  File(
                    '$fonts/segoeuib.ttf',
                  ).readAsBytes().then(ByteData.sublistView),
                ))
              .load();
        });
      }
      for (final scenario in [
        (320.0, 1.0, false),
        (390.0, 1.0, false),
        (320.0, 1.6, true),
        (430.0, 1.6, true),
      ]) {
        tester.view.physicalSize = Size(scenario.$1, 900);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          app(
            MediaQuery(
              data: MediaQueryData(
                size: Size(scenario.$1, 900),
                textScaler: TextScaler.linear(scenario.$2),
              ),
              child: RepaintBoundary(
                key: boundary,
                child: FacilityDetailCard(
                  misafirhane: facility,
                  mapLocationState: location,
                  isFavorite: true,
                  onBack: () {},
                  onCall: () {},
                  onShare: () {},
                  onFavorite: () {},
                  onInspect: () {},
                  onReview: () {},
                  onShowOnMap: () {},
                  onRequestLocation: () async {},
                ),
              ),
            ),
            dark: scenario.$3,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Listeye dön'), findsNothing);
        expect(find.text('Konaklama detayı'), findsNothing);
        expect(find.text(facility.isim), findsOneWidget);
        expect(find.textContaining('(Kuş Uçuşu)'), findsOneWidget);
        await reveal(tester, find.text('Favori'));
        for (final label in [
          'Favori',
          'Takvim',
          'Yorum',
          'Karşılaştır',
          'Paylaş',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(
          find.byType(Image),
          findsOneWidget,
        ); // Existing Rotalink logo only.
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('DETAIL_SCREENSHOTS')) {
          final scroll = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          scroll.position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/checks/detail-${scenario.$1.toInt()}-${scenario.$2}-${scenario.$3}.png',
            );
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'hızlı işlemler ve sabit eylemler mevcut callback/karşılaştırma seçimini kullanır',
    (tester) async {
      final counts = <String, int>{};
      void count(String id) =>
          counts.update(id, (n) => n + 1, ifAbsent: () => 1);
      final location = MapLocationState();
      addTearDown(location.dispose);
      await tester.pumpWidget(
        app(
          FacilityDetailCard(
            misafirhane: facility,
            mapLocationState: location,
            isFavorite: false,
            onBack: () => count('back'),
            onCall: () => count('call'),
            onShare: () => count('share'),
            onFavorite: () => count('favorite'),
            onInspect: () => count('directions'),
            onReview: () => count('review'),
            onShowOnMap: () => count('map'),
            onRequestLocation: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Favori',
        'Yorum',
        'Paylaş',
        'Haritada göster',
        'Ara',
      ]) {
        await reveal(tester, find.text(label));
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(counts, {
        'favorite': 1,
        'review': 1,
        'share': 1,
        'map': 1,
        'call': 1,
      });
      expect(find.textContaining('Size uzaklık'), findsNothing);
      expect(find.text('Yol Tarifi'), findsNothing);
      expect(counts['directions'], isNull);
      if (PriceAccess.unlocked) {
        await reveal(tester, find.text('Karşılaştır'));
        await tester.tap(find.text('Karşılaştır'));
        await tester.pump();
        expect(FacilityCompareSelection.instance.contains(facility), true);
        await reveal(tester, find.text('Karşılaştır'));
        await tester.tap(find.text('Karşılaştır'));
        await tester.pump();
        expect(FacilityCompareSelection.instance.contains(facility), false);
      }
      await reveal(tester, find.text('Takvim'));
      await tester.tap(find.text('Takvim'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Geri'));
      expect(counts['back'], 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'dinamik tarife grupları, detay önce hesaplama sonra ve mevcut açılır bölümler',
    (tester) async {
      if (!PriceAccess.unlocked) return;
      final location = MapLocationState();
      addTearDown(location.dispose);
      await tester.pumpWidget(
        app(
          FacilityDetailCard(
            misafirhane: facility,
            mapLocationState: location,
            isFavorite: false,
            onBack: () {},
            onCall: () {},
            onShare: () {},
            onFavorite: () {},
            onInspect: () {},
            onReview: () {},
            onShowOnMap: () {},
            onRequestLocation: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Güncel Fiyatlar'));
      expect(find.text('Üye misafir'), findsOneWidget);
      expect(find.text('Diğer misafir'), findsOneWidget);
      expect(find.text('1.234 TL'), findsOneWidget);
      expect(find.text('2.345 TL'), findsOneWidget);
      final detail = find.text('Detaylı tarifeyi göster'),
          calculate = find.text('Konaklama ücretini hesapla');
      await reveal(tester, calculate);
      final d = tester.getTopLeft(detail), c = tester.getTopLeft(calculate);
      expect(d.dy < c.dy || (d.dy == c.dy && d.dx < c.dx), true);
      await reveal(tester, detail);
      await tester.tap(detail);
      await tester.pumpAndSettle();
      expect(find.byType(FacilityTariffView), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await reveal(tester, calculate);
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(find.text('Fiyat birimi'), findsOneWidget);
      expect(find.text('Tahmini toplam'), findsWidgets);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Kimler konaklayabilir?'));
      await tester.tap(find.text('Kimler konaklayabilir?'));
      await tester.pumpAndSettle();
      expect(find.text('Millî Eğitim Bakanlığı'), findsOneWidget);
      await reveal(tester, find.text('Nasıl kalınır?'));
      await tester.tap(find.text('Nasıl kalınır?'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('PRO erişimi fiyat kartının yeni sunumunda da korunur', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: FacilityOvernightPriceBox(
            facility: facility,
            detailPresentation: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('1.234 TL'),
      PriceAccess.unlocked ? findsOneWidget : findsNothing,
    );
    if (!PriceAccess.unlocked) {
      expect(find.text('Konaklama ücretini hesapla'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'hava yalnızca tesis koordinatını kullanır; eksik koordinatta sahte derece göstermez',
    (tester) async {
      final queries = <String>[];
      Future<WeatherSnapshot?> loader({
        required double latitude,
        required double longitude,
      }) async {
        queries.add('$latitude,$longitude');
        return const WeatherSnapshot(
          tempC: 9,
          iconCode: '01n',
          cityName: 'Bünyan',
          description: 'Açık',
        );
      }

      await tester.pumpWidget(
        app(FacilityWeatherBadge(facility: facility, loader: loader)),
      );
      await tester.pumpAndSettle();
      expect(queries, ['38.85,35.86']);
      expect(find.text('🌙'), findsOneWidget);
      expect(find.text('9°'), findsOneWidget);
      expect(find.text('Kayseri'), findsOneWidget);
      final badge = find.byType(FacilityWeatherBadge);
      final surface = tester.widget<Container>(
        find.descendant(of: badge, matching: find.byType(Container)).first,
      );
      expect(
        (surface.decoration! as BoxDecoration).gradient!.colors,
        weatherBadgeGradient('01n'),
      );
      final center = tester.getCenter(find.text('9°')).dx;
      for (final label in ['🌙', 'Kayseri', 'Açık']) {
        expect(tester.getCenter(find.text(label)).dx, closeTo(center, 1));
      }
      expect(
        tester.getCenter(find.text('🌙')).dy,
        lessThan(tester.getCenter(find.text('9°')).dy),
      );
      expect(
        tester.getCenter(find.text('9°')).dy,
        lessThan(tester.getCenter(find.text('Kayseri')).dy),
      );
      const missing = Misafirhane(
        isim: 'Koordinatsız',
        il: 'Ankara',
        adres: '',
        telefon: '',
        latitude: 0,
        longitude: 0,
        tip: 'Kamu',
      );
      await tester.pumpWidget(
        app(FacilityWeatherBadge(facility: missing, loader: loader)),
      );
      await tester.pumpAndSettle();
      expect(queries.length, 1);
      expect(find.text('9°'), findsNothing);
      expect(find.text('Hava bilgisi yok'), findsOneWidget);
    },
  );
  testWidgets(
    'yalnız eski fiyat alanları olan tesiste de kaynak ayrıntıda korunur',
    (tester) async {
      if (!PriceAccess.unlocked) return;
      FacilityPriceRepository.instance.applyJsonString(
        jsonEncode({
          'tesisler': [
            {
              'il': facility.il,
              'isim': facility.isim,
              'fiyat_sivil': '1.150 – 3.475 TL',
              'kaynak': 'https://example.com/legacy',
              'gecerlilik': '2026 tarifesi',
            },
          ],
        }),
      );
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: FacilityOvernightPriceBox(
              facility: facility,
              detailPresentation: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1.150 TL'), findsOneWidget);
      expect(find.byType(PriceMetaFooter), findsNothing);
      expect(find.text('Konaklama ücretini hesapla'), findsNothing);
      await tester.tap(find.text('Detaylı tarifeyi göster'));
      await tester.pumpAndSettle();
      expect(find.text('1.150 – 3.475 TL'), findsOneWidget);
      expect(find.byType(PriceMetaFooter), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  if (finder.evaluate().isEmpty) {
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 100, scrollable: scrollable);
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.3);
  await tester.pumpAndSettle();
}
