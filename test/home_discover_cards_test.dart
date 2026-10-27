import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotalink_flutter/billing/pro_service.dart';
import 'package:rotalink_flutter/data/firebase_rota_repository.dart';
import 'package:rotalink_flutter/navigation/rotalink_shell_routes.dart';
import 'package:rotalink_flutter/screens/home_dashboard_screen.dart';
import 'package:rotalink_flutter/theme/app_theme.dart';
import 'package:rotalink_flutter/widgets/winter_discover_home_card.dart';

class _Repository extends FirebaseRotaRepository {
  @override
  RotaDataState get currentState =>
      const RotaDataState(initialLoadCompleted: true);
  @override
  Stream<RotaDataState> watchRoot() => Stream.value(currentState);
}

void main() {
  testWidgets(
    'fotoğraflı keşif ve hızlı işlemler tema, erişilebilirlik ve bağlantıları korur',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const billingChannel =
          'dev.flutter.pigeon.in_app_purchase_android.InAppPurchaseApi.startConnection';
      // Kartın Pro rozeti testi mağaza hizmetinin yanıtını gerektirmez.
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        billingChannel,
        (_) => Completer<ByteData?>().future,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          billingChannel,
          null,
        ),
      );
      final oldPro = ProService.instance.isPro.value;
      ProService.instance.isPro.value = false;
      addTearDown(() => ProService.instance.isPro.value = oldPro);
      var mapOpens = 0;
      var routeOpens = 0;
      var campaignOpens = 0;
      final routes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HomeDashboardScreen(
            repository: _Repository(),
            onOpenMap: () => mapOpens++,
            onOpenSearch: () {},
            onSubmitQuery: (_) {},
            onOpenCategory: (_) {},
            onOpenFavorites: () {},
            onOpenRoutePlan: () => routeOpens++,
            onOpenDiscover: () => campaignOpens++,
            onOpenNamedRoute: routes.add,
            onOpenKami: () {},
          ),
        ),
      );
      await tester.pump();
      final pageScroll = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      Finder type(String name) =>
          find.byWidgetPredicate((w) => w.runtimeType.toString() == name);
      await tester.scrollUntilVisible(
        type('_MapDiscoverCard'),
        250,
        scrollable: pageScroll,
      );
      final map = tester.widget(type('_MapDiscoverCard'));
      await tester.scrollUntilVisible(
        find.byType(WinterDiscoverHomeCard),
        200,
        scrollable: pageScroll,
      );
      final winter = tester.widget(find.byType(WinterDiscoverHomeCard));
      await tester.scrollUntilVisible(
        type('_QuickActions'),
        200,
        scrollable: pageScroll,
      );
      final dynamic quick = tester.widget(type('_QuickActions'));
      final section = tester.widget(
        find.ancestor(
          of: find.text('Hızlı işlemler'),
          matching: type('_SectionTitle'),
        ),
      );
      final callbacks = <VoidCallback>[
        quick.onRoute,
        quick.onPrice,
        quick.onWeather,
        quick.onHolidays,
      ];

      if (const bool.fromEnvironment('HOME_DISCOVER_SCREENSHOTS')) {
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
      final boundary = GlobalKey();
      for (final scenario in [
        (false, 390.0, 1.0, 4, 'light'),
        (true, 390.0, 1.0, 4, 'dark'),
        (false, 320.0, 1.8, 2, 'small_large_text'),
      ]) {
        tester.view.physicalSize = Size(
          scenario.$2,
          scenario.$3 > 1 ? 1400 : 700,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: scenario.$1
                  ? buildRotalinkDarkTheme()
                  : buildRotalinkTheme(),
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scenario.$3)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      map,
                      const SizedBox(height: 12),
                      winter,
                      const SizedBox(height: 24),
                      section,
                      const SizedBox(height: 12),
                      quick as Widget,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        expect(images, hasLength(6));
        expect(images.every((image) => image.image is ResizeImage), isTrue);
        await tester.runAsync(() async {
          for (final image in images) {
            await precacheImage(
              image.image,
              tester.element(find.byType(Scaffold)),
            );
          }
        });
        await tester.pumpAndSettle();
        final grid = tester.widget<GridView>(find.byType(GridView));
        expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          scenario.$4,
        );
        for (final (index, label) in [
          'Yakınımdaki\nMisafirhaneler',
          'Fiyat',
          'Meteoroloji',
          'Tatiller',
        ].indexed) {
          final ink = tester.widget<InkWell>(
            find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
          );
          expect(ink.onTap, same(callbacks[index]), reason: label);
        }
        expect(find.text('Pro'), findsOneWidget);
        expect(find.text('Kampanyalar'), findsNothing);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('HOME_DISCOVER_SCREENSHOTS')) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final shot = await render.toImage(pixelRatio: 2);
            final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/home_discover_previews/${scenario.$5}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            shot.dispose();
          });
        }
      }
      await tester.tap(find.text('Haritada keşfet'));
      await tester.tap(find.text('Kış Keşfet'));
      await tester.tap(find.text('Yakınımdaki\nMisafirhaneler'));
      await tester.tap(find.text('Tatiller'));
      expect(mapOpens, 1);
      expect(routeOpens, 0);
      expect(campaignOpens, 0);
      expect(routes, [
        RotalinkShellRoutes.winterDiscover,
        RotalinkShellRoutes.nearby,
        RotalinkShellRoutes.holidays,
      ]);
      ProService.instance.isPro.value = true;
      await tester.pump();
      expect(find.text('Pro'), findsNothing);
      ProService.instance.isPro.value = false;
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
