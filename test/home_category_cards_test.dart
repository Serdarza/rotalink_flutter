import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotalink_flutter/data/firebase_rota_repository.dart';
import 'package:rotalink_flutter/data/hediyelik_repository.dart';
import 'package:rotalink_flutter/data/kamp_repository.dart';
import 'package:rotalink_flutter/models/gezi_yemek_item.dart';
import 'package:rotalink_flutter/screens/home_dashboard_screen.dart';
import 'package:rotalink_flutter/theme/app_theme.dart';

class _Repository extends FirebaseRotaRepository {
  static const item = GeziYemekItem(
    il: 'Bursa',
    isim: 'Yer',
    adres: '',
    aciklama: '',
  );
  @override
  RotaDataState get currentState =>
      RotaDataState(gezi: List.filled(4214, item));
  @override
  Stream<RotaDataState> watchRoot() => Stream.value(currentState);
}

void main() {
  testWidgets(
    'altı fotoğraflı kart çevrimdışı, dinamik sayılar ve tıklamalarla çalışır',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final selected = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HomeDashboardScreen(
            repository: _Repository(),
            onOpenMap: () {},
            onOpenSearch: () {},
            onSubmitQuery: (_) {},
            onOpenCategory: selected.add,
            onOpenFavorites: () {},
            onOpenRoutePlan: () {},
            onOpenDiscover: () {},
            onOpenNamedRoute: (_) {},
            onOpenKami: () {},
          ),
        ),
      );
      await tester.pump();
      // Gerçek ana sayfanın oluşturduğu widget'ı aynı veriler/callback ile sınar.
      // Üretim koduna test için yeni API veya bağımlılık eklenmez.
      final grid = tester.widget(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_CategoryGrid',
        ),
      );
      final boundary = GlobalKey();
      Future<void> show({
        required bool dark,
        required double width,
        double scale = 1,
      }) async {
        tester.view.physicalSize = Size(width, 740);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? buildRotalinkDarkTheme() : buildRotalinkTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: grid,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(dark: false, width: 390);
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(6));
      expect(images.every((im) => im.image is ResizeImage), isTrue);
      await tester.runAsync(() async {
        for (final im in images) {
          await precacheImage(im.image, tester.element(find.byType(Scaffold)));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('4214'), findsOneWidget);
      expect(find.text('Kamu Misafirhaneleri'), findsOneWidget);
      expect(find.text('Misafirhane ve orduevi'), findsNothing);
      const names = [
        'Konaklama',
        'Gezi',
        'Yemek',
        'Sosyal tesisler',
        'Hediyelik',
        'Kamp yerleri',
      ];
      for (final name in names) {
        await tester.tap(find.text(name));
      }
      await tester.pumpAndSettle();
      expect(selected, [0, 1, 2, 3, 4, 5]);
      final previousGifts = HediyelikRepository.instance.byIl.value;
      final previousCamps = KampRepository.instance.items.value;
      addTearDown(
        () => HediyelikRepository.instance.byIl.value = previousGifts,
      );
      addTearDown(() => KampRepository.instance.items.value = previousCamps);
      KampRepository.instance.items.value = List.filled(
        595,
        const KampAlani(
          id: 'kamp',
          ad: 'Kamp',
          il: 'Bursa',
          enlem: 40,
          boylam: 29,
          ucret: '',
          kampTuru: '',
          sonKontrol: null,
          dogrulama: '',
          kaynakUrl: null,
        ),
      );
      HediyelikRepository.instance.byIl.value = {
        'bursa': List.generate(
          913,
          (i) => HediyelikItem(il: 'Bursa', ad: 'Ürün $i'),
        ),
      };
      await tester.pump();
      expect(find.text('913'), findsOneWidget);
      expect(find.text('595'), findsOneWidget);

      if (const bool.fromEnvironment('HOME_CATEGORY_SCREENSHOTS')) {
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
        });
      }
      for (final scenario in [
        (false, 390.0, 1.0, 'light'),
        (true, 390.0, 1.0, 'dark'),
        (false, 320.0, 1.8, 'small_large_text'),
      ]) {
        await show(dark: scenario.$1, width: scenario.$2, scale: scenario.$3);
        expect(tester.takeException(), isNull);
        final cards = tester.widgetList<GridView>(find.byType(GridView)).single;
        final delegate =
            cards.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, 2);
        if (const bool.fromEnvironment('HOME_CATEGORY_SCREENSHOTS')) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final shot = await render.toImage(pixelRatio: 2);
            final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/home_category_previews/${scenario.$4}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            shot.dispose();
          });
        }
      }
      // Sıfır sayıda mevcut etiket gizleme davranışı korunur.
      HediyelikRepository.instance.byIl.value = {};
      KampRepository.instance.items.value = [];
      await tester.pump();
      expect(find.text('913'), findsNothing);
      expect(find.text('595'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
