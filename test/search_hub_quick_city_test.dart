import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/data/firebase_rota_repository.dart';
import 'package:rotalink_flutter/screens/search_hub_screen.dart';
import 'package:rotalink_flutter/theme/app_theme.dart';

class _SearchHubRepository extends FirebaseRotaRepository {
  @override
  RotaDataState get currentState =>
      const RotaDataState(misafirhaneler: [], initialLoadCompleted: true);

  @override
  Stream<RotaDataState> watchRoot() => Stream.value(currentState);
}

Widget _screen({
  required ValueChanged<String> onQuery,
  VoidCallback onNearby = _noop,
  ValueChanged<String>? onCitySelected,
  bool dark = false,
}) => MaterialApp(
  theme: dark ? buildRotalinkDarkTheme() : buildRotalinkTheme(),
  home: Scaffold(
    body: SearchHubScreen(
      repository: _SearchHubRepository(),
      onBack: () {},
      onQuery: onQuery,
      onCitySelected: onCitySelected,
      onNearby: onNearby,
    ),
  ),
);

void main() {
  testWidgets('Ara araması plaka numarasını il adına dönüştürür', (
    tester,
  ) async {
    String? submittedQuery;
    await tester.pumpWidget(
      _screen(onQuery: (query) => submittedQuery = query),
    );
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, '34');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(submittedQuery, 'İstanbul');

    await tester.enterText(searchField, '01');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(submittedQuery, 'Adana');
  });

  testWidgets('Ara ekranında dokuz şehir kartı ve Yakınımda ara görünür', (
    tester,
  ) async {
    String? selectedQuery;
    var nearbyOpened = false;
    await tester.pumpWidget(
      _screen(
        onQuery: (_) {},
        onNearby: () => nearbyOpened = true,
        onCitySelected: (query) => selectedQuery = query,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hızlı Şehir Seçimi'), findsOneWidget);
    expect(find.text('Şehrini Seç, Keşfet!'), findsOneWidget);
    expect(find.text('Listemi Düzenle'), findsOneWidget);
    expect(find.text('34'), findsOneWidget);
    expect(find.text('İstanbul'), findsOneWidget);
    expect(find.text('06'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
    expect(find.text('07'), findsOneWidget);
    expect(find.text('38'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(find.text('61'), findsOneWidget);
    expect(find.text('27'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(find.text('Eskişehir'), findsNothing);
    expect(find.text('Konya'), findsNothing);
    expect(find.text('Muğla'), findsNothing);
    expect(find.text('Hızlı erişim'), findsNothing);
    expect(find.text('Popüler şehirler'), findsNothing);
    expect(find.text('81 İl + KKTC'), findsNothing);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);

    await tester.ensureVisible(find.text('Kayseri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('38'));
    await tester.pump();
    expect(selectedQuery, 'Kayseri');
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Yakınımda ara'), findsOneWidget);
    await tester.tap(find.text('Yakınımda ara'));
    expect(nearbyOpened, isTrue);
  });

  testWidgets(
    'şehir seçici plaka ile arar ve KKTC seçimini Kıbrıs verisine bağlar',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? selectedQuery;
      await tester.pumpWidget(
        _screen(onQuery: (query) => selectedQuery = query),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'initial hub layout');

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'scrolled hub layout');
      await tester.tap(find.text('Tüm Şehirleri Gör'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'city picker layout');
      expect(find.text('Şehir Seç'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));

      await tester.enterText(find.byType(TextField).last, '81');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'plate query layout');
      expect(find.text('Düzce'), findsOneWidget);
      expect(find.text('KKTC'), findsNothing);

      await tester.enterText(find.byType(TextField).last, 'Kıbrıs');
      await tester.pumpAndSettle();
      final queryError = tester.takeException();
      if (queryError is FlutterError) debugPrint(queryError.toStringDeep());
      expect(queryError, isNull, reason: 'Kıbrıs query layout');
      expect(find.text('Kuzey Kıbrıs'), findsOneWidget);
      await tester.tap(find.text('KKTC').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'selected city layout');
      expect(selectedQuery, 'Kıbrıs');
    },
  );

  testWidgets('şehir kartları koyu temada da taşma üretmez', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_screen(onQuery: (_) {}, dark: true));
    await tester.pumpAndSettle();

    expect(find.text('Hızlı Şehir Seçimi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
