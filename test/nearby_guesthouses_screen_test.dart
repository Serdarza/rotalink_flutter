import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotalink_flutter/widgets/nearby_guesthouse_card.dart';
import 'package:rotalink_flutter/widgets/search_results_ui.dart';
import 'package:rotalink_flutter/widgets/best_value_pro_card.dart';
import 'package:rotalink_flutter/data/facility_price_repository.dart';
import 'package:rotalink_flutter/billing/price_access.dart';
import 'package:rotalink_flutter/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rotalink_flutter/data/firebase_rota_repository.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';
import 'package:rotalink_flutter/screens/nearby_guesthouses_screen.dart';
import 'package:rotalink_flutter/services/nearby_location_access.dart';
import 'package:rotalink_flutter/services/simple_location_service.dart';

const near = Misafirhane(
  isim: 'Yakın Öğretmenevi',
  il: 'Ankara',
  ilce: 'Çankaya',
  adres: '',
  telefon: '',
  latitude: 39.94,
  longitude: 32.86,
  tip: 'Öğretmenevi',
);
const far = Misafirhane(
  isim: 'Uzak Polisevi',
  il: 'Ankara',
  ilce: 'Çubuk',
  adres: '',
  telefon: '',
  latitude: 40.3,
  longitude: 32.86,
  tip: 'Polisevi',
);
// Closer but another province: must not leak into the selected province list.
const other = Misafirhane(
  isim: 'Başka İlin Tesisi',
  il: 'Bolu',
  adres: '',
  telefon: '',
  latitude: 39.934,
  longitude: 32.86,
  tip: 'Kamu',
);
const missing = Misafirhane(
  isim: 'Koordinatsız Tesis',
  il: 'Ankara',
  adres: '',
  telefon: '',
  latitude: 0,
  longitude: 0,
  tip: 'Kamu',
);

class Repository extends FirebaseRotaRepository {
  @override
  RotaDataState get currentState => const RotaDataState(
    misafirhaneler: [far, other, missing, near],
    initialLoadCompleted: true,
  );
  @override
  Stream<RotaDataState> watchRoot() => Stream.value(currentState);
}

class Location extends NearbyLocationAccess {
  bool enabled = true, granted = false;
  bool enableInSettings = false;
  int requests = 0, positions = 0, settingsOpens = 0;
  Future<bool>? enabledPending;
  Future<PermissionRequestOutcome>? permissionPending;
  Position? cached;
  Future<Position>? pending;
  @override
  Future<Position?> lastKnownPosition() async => cached;
  @override
  Future<bool> isEnabled() async => enabledPending ?? Future.value(enabled);
  @override
  Future<bool> isGranted() async => granted;
  @override
  Future<PermissionRequestOutcome> requestPermission() async {
    requests++;
    if (permissionPending != null) return permissionPending!;
    return PermissionRequestOutcome.denied;
  }

  @override
  Future<bool> openLocationSettings() async {
    settingsOpens++;
    if (enableInSettings) {
      enabled = true;
      granted = true;
    }
    return true;
  }

  @override
  Future<Position> currentPosition() async {
    positions++;
    if (pending != null) return pending!;
    return Position.fromMap({
      'latitude': 39.9334,
      'longitude': 32.8597,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
}

Widget page(Location location, {ValueChanged<Misafirhane>? onOpen}) =>
    MaterialApp(
      home: NearbyGuesthousesScreen(
        repository: Repository(),
        location: location,
        onOpenFacility: onOpen ?? (_) {},
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FacilityPriceRepository.instance.applyJsonString('{"tesisler":[]}');
  });
  testWidgets('izin reddedilince il sormaz ve tesislere sahte mesafe üretmez', (
    tester,
  ) async {
    final location = Location();
    await tester.pumpWidget(page(location));
    await tester.pumpAndSettle();
    expect(location.requests, 1);
    expect(location.positions, 0);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.textContaining('konum izni gerekiyor'), findsOneWidget);
    expect(find.text('Yakın Öğretmenevi'), findsNothing);
    await tester.pump();
    expect(location.requests, 1);
  });
  testWidgets(
    'GPS kapalıysa pop-up açar; konumu aç butonu cihaz ayarlarına gider',
    (tester) async {
      final location = Location()..enabled = false;
      await tester.pumpWidget(page(location));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Konumunuz kapalı'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Konumu aç'));
      await tester.pumpAndSettle();
      expect(location.settingsOpens, 1);
      expect(location.requests, 0);
      expect(location.positions, 0);
    },
  );
  testWidgets(
    'konum açıkken il sormadan aynı ilin tüm tesislerini yakından uzağa sıralar',
    (tester) async {
      final location = Location()..granted = true;
      final opened = <Misafirhane>[];
      await tester.pumpWidget(page(location, onOpen: opened.add));
      await tester.pumpAndSettle();
      expect(find.text('Ankara · Yakından uzağa'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('20 km'), findsNothing);
      expect(find.text('Başka İlin Tesisi'), findsNothing);
      final titles = tester
          .widgetList<NearbyGuesthouseCard>(find.byType(NearbyGuesthouseCard))
          .map((card) => card.facility.isim)
          .toList();
      expect(titles, [
        'Yakın Öğretmenevi',
        'Uzak Polisevi',
        'Koordinatsız Tesis',
      ]);
      expect(find.textContaining('Mesafe bilgisi bulunamadı'), findsNothing);
      await tester.tap(find.text('Yakın Öğretmenevi'));
      await tester.pump();
      expect(opened, [near]);
      expect(location.positions, 1);
      expect(location.requests, 0);
    },
  );
  testWidgets(
    'arama kartını paylaşır; doğrulanmış en ucuz aynı il tesisini PRO üstte gösterir',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FacilityPriceRepository.instance.applyJsonString(
        jsonEncode({
          'tesisler': [
            for (final entry in [
              (near, 250, 'resmi_kaynak'),
              (far, 100, 'tesis_dogruladi'),
              (other, 1, 'resmi_kaynak'),
              (missing, 50, 'kullanici_bildirimi'),
            ])
              {
                'il': entry.$1.il,
                'isim': entry.$1.isim,
                'tarife': {
                  'dogrulama': entry.$3,
                  'kategoriler': [
                    {'id': 'sivil', 'ad': 'Sivil misafir'},
                  ],
                  'tablolar': [
                    {
                      'satirlar': [
                        {
                          'ad': 'Tek Kişilik Oda',
                          'kisi': 1,
                          'fiyatlar': {'sivil': entry.$2},
                        },
                      ],
                    },
                  ],
                },
              },
          ],
        }),
      );
      final location = Location()..granted = true;
      final opened = <Misafirhane>[];
      await tester.pumpWidget(page(location, onOpen: opened.add));
      await tester.pumpAndSettle();
      final pro = tester.widget<BestValueProCard>(
        find.byType(BestValueProCard),
      );
      expect(pro.pick.facility.isim, far.isim);
      expect(pro.pick.price, 100);
      final cards = tester
          .widgetList<SearchFacilityResultCard>(
            find.byType(SearchFacilityResultCard),
          )
          .toList();
      expect(cards.map((card) => card.name), [
        near.isim,
        far.isim,
        missing.isim,
      ]);
      expect(cards.first.hasPrice, true);
      expect(
        tester.getTopLeft(find.byType(BestValueProCard)).dy,
        lessThan(tester.getTopLeft(find.byType(NearbyGuesthouseCard).first).dy),
      );
      if (PriceAccess.unlocked) {
        await tester.tap(find.text('Tesisi İncele'));
        await tester.pump();
        expect(opened.single.isim, far.isim);
      } else {
        expect(
          find.descendant(
            of: find.byType(BestValueProCard),
            matching: find.text(far.isim),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(BestValueProCard),
            matching: find.text('100 TL'),
          ),
          findsNothing,
        );
      }
    },
  );

  testWidgets('doğrulanmış fiyat yoksa PRO fiyat kartı uydurmaz', (
    tester,
  ) async {
    final location = Location()..granted = true;
    await tester.pumpWidget(page(location));
    await tester.pumpAndSettle();
    expect(find.byType(BestValueProCard), findsNothing);
    expect(find.byType(SearchFacilityResultCard), findsNWidgets(3));
  });

  testWidgets('ayarlardan konum açılıp dönünce liste kendiliğinden yüklenir', (
    tester,
  ) async {
    final location = Location()
      ..enabled = false
      ..enableInSettings = true;
    await tester.pumpWidget(page(location));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Konumu aç'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Ankara · Yakından uzağa'), findsOneWidget);
    expect(location.positions, 1);
    expect(location.settingsOpens, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets(
    'yakın tarihli konumla GPS beklemeden sonuç verir; hata listeyi silmez',
    (tester) async {
      final completion = Completer<Position>();
      final location = Location()
        ..granted = true
        ..cached = Position.fromMap({
          'latitude': 39.9334,
          'longitude': 32.8597,
          'accuracy': 30.0,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        })
        ..pending = completion.future;
      await tester.pumpWidget(page(location));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Yakın Öğretmenevi'), findsOneWidget);
      expect(find.text('Konumunuz arka planda yenileniyor.'), findsOneWidget);
      expect(location.positions, 1);
      completion.completeError(TimeoutException('GPS'));
      await tester.pumpAndSettle();
      expect(find.text('Yakın Öğretmenevi'), findsOneWidget);
      expect(
        find.textContaining('yakın zamanda alınan konumunuz'),
        findsOneWidget,
      );
      expect(find.text('Konumunuz arka planda yenileniyor.'), findsNothing);
    },
  );

  testWidgets(
    'yanıt vermeyen GPS sekiz saniyede çıkar ve tekrar denemeye izin verir',
    (tester) async {
      final location = Location()
        ..granted = true
        ..pending = Completer<Position>().future;
      await tester.pumpWidget(page(location));
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.textContaining('Konum henüz alınamadı'), findsOneWidget);
      expect(find.text('Tekrar dene'), findsOneWidget);
      expect(find.text('Yakın Öğretmenevi'), findsNothing);
    },
  );

  testWidgets('yanıtsız konum servis kontrolü süresiz bekletmez', (
    tester,
  ) async {
    final location = Location()..enabledPending = Completer<bool>().future;
    await tester.pumpWidget(page(location));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(location.positions, 0);
  });

  testWidgets('yanıtsız izin isteği süresiz bekletmez', (tester) async {
    final location = Location()
      ..permissionPending = Completer<PermissionRequestOutcome>().future;
    await tester.pumpWidget(page(location));
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(location.requests, 1);
    expect(location.positions, 0);
  });

  test(
    'eski, gelecekteki, hatalı ve doğruluğu düşük konum ilk liste için kullanılmaz',
    () {
      final now = DateTime.now();
      Position fix(Duration age, {double accuracy = 30, double lat = 39.9}) =>
          Position.fromMap({
            'latitude': lat,
            'longitude': 32.8,
            'accuracy': accuracy,
            'timestamp': now.subtract(age).millisecondsSinceEpoch,
          });
      expect(
        NearbyLocationAccess.isRecent(
          fix(const Duration(seconds: 30)),
          now: now,
        ),
        true,
      );
      expect(
        NearbyLocationAccess.isRecent(
          fix(const Duration(minutes: 3)),
          now: now,
        ),
        false,
      );
      expect(
        NearbyLocationAccess.isRecent(
          fix(const Duration(seconds: -30)),
          now: now,
        ),
        false,
      );
      expect(
        NearbyLocationAccess.isRecent(
          fix(Duration.zero, accuracy: 2000),
          now: now,
        ),
        false,
      );
      expect(
        NearbyLocationAccess.isRecent(fix(Duration.zero, lat: 0), now: now),
        false,
      );
    },
  );

  testWidgets('yakın tesis kartı il ve ilçeyi tema ve büyük yazıda taşırmaz', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      for (final width in [320.0, 600.0]) {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? buildRotalinkDarkTheme() : buildRotalinkTheme(),
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(
                ctx,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: NearbyGuesthouseCard(
                  facility: const Misafirhane(
                    isim:
                        'Kayseri İl Sağlık Müdürlüğü Bölge Eğitim Araştırma ve Uygulama Merkezi Misafirhanesi',
                    il: 'Kayseri',
                    adres: 'Meteoroloji Caddesi No: 3 Melikgazi/Kayseri',
                    telefon: '',
                    latitude: 38.6,
                    longitude: 35.5,
                    tip: 'Kamu misafirhanesi',
                  ),
                  distanceKm: 0.1,
                  onTap: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.text('Kayseri / Melikgazi'), findsOneWidget);
        expect(
          find.textContaining('0,1 km · Konumunuzdan · (Kuş Uçuşu)'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
