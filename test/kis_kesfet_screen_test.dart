import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/data/kis_kesfet_repository.dart';
import 'package:rotalink_flutter/models/kis_kesfet_place.dart';
import 'package:rotalink_flutter/models/kis_kesfet_ucret.dart';
import 'package:rotalink_flutter/screens/kis_kesfet_screen.dart';
import 'package:rotalink_flutter/theme/app_theme.dart';
import 'package:rotalink_flutter/widgets/winter_discover_home_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const places = [
    KisKesfetPlace(
      id: 'k1',
      kategori: KisKesfetKategori.kayak,
      il: 'Bursa',
      ilce: '',
      isim: 'Uludağ Kayak Merkezi',
      kurumTuru: 'Kış sporları merkezi',
      kisaAciklama: 'Bursa kayak merkezi.',
      adres: 'Uludağ',
      telefon: '',
      kullanimTuru: 'Günübirlik',
      latitude: null,
      longitude: null,
      resmiKaynak: 'https://www.ktb.gov.tr/ornek',
      sonDogrulama: '2026-10-22',
      anaBilgiler: [KisKesfetBilgi(baslik: 'Pist sayısı', deger: '13 pist')],
    ),
    KisKesfetPlace(
      id: 't1',
      kategori: KisKesfetKategori.termal,
      il: 'Ankara',
      ilce: 'Kızılcahamam',
      isim: 'Belediye Kaplıcası',
      kurumTuru: 'Belediye',
      kisaAciklama:
          'Kamu Tesisleri dizininde belediye kaplıcası olarak kayıtlıdır.',
      adres: 'Kızılcahamam',
      telefon: '0312 111 11 11',
      kullanimTuru: '',
      latitude: 40.46,
      longitude: 32.65,
      resmiKaynak: 'https://hsgm.saglik.gov.tr/ornek.pdf',
      sonDogrulama: '2019-09-21',
      tesisSinifi: 'kamu',
    ),
  ];

  testWidgets('kategori, il ve detay akışı açılır', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: KisKesfetScreen(places: places)),
    );

    expect(find.text('Bursa'), findsOneWidget);
    expect(find.text('1 kayak merkezi'), findsOneWidget);

    await tester.tap(find.text('Termal'));
    await tester.pumpAndSettle();
    expect(find.text('Ankara'), findsOneWidget);
    expect(find.text('1 termal tesis'), findsOneWidget);

    await tester.tap(find.text('Ankara'));
    await tester.pumpAndSettle();
    expect(find.text('Belediye Kaplıcası'), findsOneWidget);
    expect(find.text('Kamu · Belediye'), findsWidgets);
    expect(find.text('Özel tesis'), findsNothing);
    expect(find.text('0312 111 11 11'), findsOneWidget);
    expect(find.textContaining('olarak kayıtlıdır'), findsNothing);

    await tester.tap(find.text('Belediye Kaplıcası'));
    await tester.pumpAndSettle();
    expect(find.text('Ara'), findsOneWidget);
    expect(find.text('Haritada göster'), findsWidgets);
    expect(find.text('Güncelleme tarihi'), findsNothing);
    expect(find.text('21.09.2019'), findsNothing);
    expect(find.text('Son doğrulama'), findsNothing);
    expect(find.textContaining('olarak kayıtlıdır'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Güncel bilgiler için resmî kaynağı kontrol edin.'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.text('Güncel bilgiler için resmî kaynağı kontrol edin.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'termal kartı başlangıç ücretini, detay tüm tarifeyi ve kontrolü gösterir',
    (tester) async {
      final priced = places[1].withUcretBilgisi(
        const KisKesfetUcretBilgisi(
          sonKontrol: '2026-10-24',
          aciklama: 'Konaklamaya kahvaltı ve havuz kullanımı dâhildir.',
          kaynaklar: ['https://tesis.bel.tr/tarife'],
          kalemler: [
            KisKesfetUcret(
              tur: KisKesfetUcretTuru.havuz,
              ad: 'Yetişkin havuz',
              tutar: 250,
              birim: 'kişi / 90 dakika',
              kaynakUrl: 'https://tesis.bel.tr/tarife',
              baslangic: true,
            ),
            KisKesfetUcret(
              tur: KisKesfetUcretTuru.konaklama,
              ad: 'İki kişilik oda',
              tutar: 2000,
              birim: 'oda / gece',
              kaynakUrl: 'https://tesis.bel.tr/tarife',
              kosul: 'Kahvaltı dâhil',
              baslangic: true,
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: KisKesfetScreen(places: [priced])),
      );
      await tester.tap(find.text('Termal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ankara'));
      await tester.pumpAndSettle();
      expect(find.text('Başlangıç · Havuz'), findsOneWidget);
      expect(find.text('Fiyat Bilgisi'), findsOneWidget);
      expect(find.text('250 TL / kişi / 90 dakika'), findsOneWidget);
      await _reveal(tester, find.text('Detay'));
      await tester.tap(find.text('Detay'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Ücret son kontrol: 24.10.2026'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Yetişkin havuz'), findsWidgets);
      expect(find.text('İki kişilik oda'), findsOneWidget);
      expect(find.text('2.000 TL / oda / gece'), findsOneWidget);
      expect(find.text('Kahvaltı dâhil'), findsOneWidget);
      expect(find.text('Ücret bilgisi bulunamadı'), findsNothing);
      expect(find.text('Giriş'), findsNothing);
      expect(find.text('Aile banyosu'), findsNothing);
      expect(
        find.text('Konaklamaya kahvaltı ve havuz kullanımı dâhildir.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Resmî kaynak'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Resmî kaynak'), findsOneWidget);
      expect(find.textContaining('Resmî kaynak ·'), findsNothing);
      expect(find.text('Güncelleme tarihi'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ücret bulunamayan termalde tahmini fiyat gösterilmez', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: KisKesfetScreen(places: places)),
    );
    await tester.tap(find.text('Termal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ankara'));
    await tester.pumpAndSettle();
    expect(find.text('Ücret bilgisi bulunamadı'), findsNothing);
    expect(find.textContaining('Başlangıç ·'), findsNothing);
    expect(find.text('Fiyat Bilgisi'), findsNothing);
    await _reveal(tester, find.text('Detay'));
    await tester.tap(find.text('Detay'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Resmî kaynak'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Ücret bilgisi bulunamadı'), findsNothing);
    expect(find.text('Ücretler'), findsNothing);
    expect(find.textContaining('Ücret son kontrol:'), findsNothing);
    expect(find.text('Resmî kaynak'), findsOneWidget);
  });

  testWidgets('telefonu olmayan kayıtta Ara görünmez', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: KisKesfetScreen(places: places)),
    );
    await tester.tap(find.text('Bursa'));
    await tester.pumpAndSettle();
    expect(find.text('13 pist'), findsOneWidget);
    await _reveal(tester, find.text('Detay'));
    await tester.tap(find.text('Detay'));
    await tester.pumpAndSettle();
    expect(find.text('Ara'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Resmî kaynak'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Resmî kaynak'), findsOneWidget);
  });

  testWidgets('kayak kartında Pist Haritası açılır, termalde görünmez', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: KisKesfetScreen(places: places)),
    );
    await tester.tap(find.text('Bursa'));
    await tester.pumpAndSettle();
    expect(find.text('Pist Haritası'), findsOneWidget);

    await _reveal(tester, find.text('Pist Haritası'));
    await tester.tap(find.text('Pist Haritası'));
    await tester.pumpAndSettle();
    expect(find.text('Resmî pist haritasını aç'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    await _reveal(tester, find.byIcon(Icons.arrow_back_rounded));
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Termal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ankara'));
    await tester.pumpAndSettle();
    expect(find.text('Pist Haritası'), findsNothing);
    expect(find.text('Harita henüz bulunamadı'), findsNothing);
  });

  testWidgets('ana ekran kartı dokunulabilir', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WinterDiscoverHomeCard(onTap: () => opened = true),
        ),
      ),
    );
    expect(
      find.text('Kayak merkezlerini ve termal tesisleri keşfet'),
      findsOneWidget,
    );
    await tester.tap(find.text('Kış Keşfet'));
    expect(opened, isTrue);
  });

  test('gömülü liste resmi kaynaklı kayıtlardan oluşur', () async {
    final places = await KisKesfetRepository.load();
    expect(places, isNotEmpty);
    expect(
      places.where((p) => p.kategori == KisKesfetKategori.kayak),
      isNotEmpty,
    );
    expect(
      places.where((p) => p.kategori == KisKesfetKategori.termal),
      isNotEmpty,
    );
    expect(
      places.where((p) => p.kategori == KisKesfetKategori.kisGezisi),
      isNotEmpty,
    );
    expect(places.every((p) => p.hasOfficialSource), isTrue);
    expect(places.every((p) => p.isim.isNotEmpty && p.il.isNotEmpty), isTrue);
    expect(
      places.where((p) => p.kategori == KisKesfetKategori.kayak && p.hasPhone),
      isNotEmpty,
    );
    expect(
      places.where((p) => p.kategori == KisKesfetKategori.termal && p.hasPhone),
      isNotEmpty,
    );
    expect(
      places
          .where((p) => p.kategori == KisKesfetKategori.kayak)
          .every((p) => p.hasFacts),
      isTrue,
    );
    expect(places.any((p) => p.id == 'termal-ankara-cimcime'), isFalse);
    expect(places.any((p) => p.isim.contains('Cimcime')), isFalse);
    final termal = places
        .where((p) => p.kategori == KisKesfetKategori.termal)
        .toList();
    expect(termal, hasLength(51));
    expect(termal.every((p) => p.isKamuTesis), isTrue);
    expect(termal.any((p) => p.isOzelTesis), isFalse);
    expect(
      termal.any((p) => p.isim.toLowerCase().contains('mutlular')),
      isFalse,
    );
    expect(
      termal.where((p) => p.id == 'termal-ankara-medrese').single.telefon,
      '0312 658 29 02',
    );
    expect(
      termal.where((p) => p.id == 'termal-ankara-hakimevi').single.telefon,
      '0312 736 61 53',
    );
    expect(
      termal.where((p) => p.id == 'termal-bursa-polisevi').single.telefon,
      '0224 239 69 00',
    );
    expect(
      termal.where((p) => p.id == 'termal-bursa-gemlik').single.telefon,
      '0224 800 20 60',
    );
    final kayak = places
        .where((p) => p.kategori == KisKesfetKategori.kayak)
        .toList();
    expect(kayak, hasLength(10));
    expect(kayak.every((p) => p.pistHaritasi != null), isTrue);
    final erciyes = kayak.singleWhere((p) => p.id == 'kayak-kayseri-erciyes');
    expect(erciyes.pistHaritasiUygulamada, isTrue);
    expect(erciyes.pistHaritasi!.hasGorsel, isTrue);
    expect(
      erciyes.pistHaritasi!.sayfaUrl,
      'https://www.erciyeskayak.com/tr/pist-haritasi',
    );
    final palandoken = kayak.singleWhere(
      (p) => p.id == 'kayak-erzurum-palandoken',
    );
    final konakli = kayak.singleWhere((p) => p.id == 'kayak-erzurum-konakli');
    expect(
      palandoken.pistHaritasi!.sayfaUrl,
      isNot(konakli.pistHaritasi!.sayfaUrl),
    );
    expect(palandoken.pistHaritasi!.sayfaUrl.contains('palandoken'), isTrue);
    expect(konakli.pistHaritasi!.sayfaUrl.contains('konakli'), isTrue);
    expect(
      kayak.where((p) => p.pistHaritasi!.durum == KisKesfetPistDurum.yok),
      hasLength(3),
    );
    final sarikamis = kayak.singleWhere((p) => p.id == 'kayak-kars-sarikamis');
    expect(sarikamis.pistHaritasiEksik, isTrue);
    expect(sarikamis.pistHaritasiUygulamada, isFalse);
    expect(sarikamis.pistHaritasiBaglanti, isNotNull);
    expect(sarikamis.pistHaritasi!.hasSayfa, isTrue);
    expect(erciyes.pistHaritasiEksik, isFalse);
  });

  testWidgets('il araması temizlenir ve yalnız kayak ile termal gösterilir', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: KisKesfetScreen(places: places)),
    );
    await tester.enterText(find.byType(TextField), 'izmir');
    await tester.pumpAndSettle();
    expect(find.text('Aradığınız il bu kategoride yok.'), findsOneWidget);
    await tester.tap(find.byTooltip('Aramayı temizle'));
    await tester.pumpAndSettle();
    expect(find.text('Bursa'), findsOneWidget);
    expect(find.text('Kış Gezileri'), findsNothing);
    expect(
      tester.widget<TabBarView>(find.byType(TabBarView)).children,
      hasLength(2),
    );
    await tester.tap(find.text('Termal'));
    await tester.pumpAndSettle();
    expect(find.text('Ankara'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('küçük ekran ve büyük yazıda kategori ve detay erişilebilir', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRotalinkDarkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const KisKesfetScreen(places: places),
      ),
    );
    await _reveal(tester, find.text('Termal'));
    await tester.tap(find.text('Termal'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Ankara'));
    await tester.tap(find.text('Ankara'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Detay'));
    await tester.tap(find.text('Detay'));
    await tester.pumpAndSettle();
    expect(find.text('Ara'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Kapat'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Kapat'), findsNothing);
  });

  if (const bool.fromEnvironment('WINTER_SCREENSHOTS')) {
    testWidgets('Kış Keşfet görsel önizlemeleri', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final allPlaces = (await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        // Görsel önizlemede testin Ahem fontu yerine cihaz fontunu kullan.
        // Üretim uygulamasının font ayarları değişmez.
        if (Platform.isWindows) {
          final fonts = '${Platform.environment['WINDIR']}/Fonts';
          final regular = File('$fonts/segoeui.ttf');
          final bold = File('$fonts/segoeuib.ttf');
          if (await regular.exists() && await bold.exists()) {
            final textFont = FontLoader('Roboto')
              ..addFont(regular.readAsBytes().then(ByteData.sublistView))
              ..addFont(bold.readAsBytes().then(ByteData.sublistView));
            await textFont.load();
          }
        }
        return KisKesfetRepository.load();
      }))!;
      final boundary = GlobalKey();
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File('build/winter_previews/$name.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildRotalinkTheme(),
            home: KisKesfetScreen(places: allPlaces),
          ),
        ),
      );
      await capture('kayak');
      await tester.tap(find.text('Termal'));
      await capture('termal');
      await _reveal(tester, find.text('Ankara'));
      await tester.tap(find.text('Ankara'));
      await capture('tesisler');
      await _reveal(tester, find.text('Detay').first);
      await tester.tap(find.text('Detay').first);
      await capture('detay');
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      final pricedCard = find.text('Kızılcahamam Belediyesi Büyük Kaplıca');
      await tester.scrollUntilVisible(
        pricedCard,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await capture('ucretli_kartlar');
      await tester.tap(pricedCard);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Saunasız özel kabin'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await capture('ucretli_detay');
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            key: const ValueKey('dark'),
            debugShowCheckedModeBanner: false,
            theme: buildRotalinkDarkTheme(),
            home: KisKesfetScreen(places: allPlaces),
          ),
        ),
      );
      await capture('koyu');
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
