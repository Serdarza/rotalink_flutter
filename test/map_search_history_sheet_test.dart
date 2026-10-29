import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/services/map_search_history.dart';
import 'package:rotalink_flutter/theme/app_theme.dart';
import 'package:rotalink_flutter/widgets/custom_search_bar.dart';
import 'package:rotalink_flutter/widgets/map_search_history_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Geçmiş düğmesi yalnız Harita arama kutusunda durur', (
    tester,
  ) async {
    final plain = TextEditingController(text: 'Ankara');
    final map = TextEditingController();
    addTearDown(plain.dispose);
    addTearDown(map.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CustomSearchBar(controller: plain, hintText: 'Ara'),
              CustomSearchBar(
                controller: map,
                hintText: 'İl, ilçe, adres veya tesis',
                compactHome: true,
                onHistoryPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byTooltip('Geçmiş'), findsOneWidget);
    expect(find.byTooltip('Sesli ara'), findsNWidgets(2));
  });

  testWidgets('geçmiş sayfası hesapsız açılır ve koyu zeminde kalır', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRotalinkDarkTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMapSearchHistorySheet(
                context: context,
                onReplay: (MapHistoryEntry entry) async {},
              ),
              child: const Text('Geçmişi aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Geçmişi aç'));
    await tester.pumpAndSettle();
    expect(find.text('Geçmiş'), findsOneWidget);
    expect(find.text('Henüz harita araması yok.'), findsOneWidget);
    expect(find.textContaining('GitHub'), findsNothing);
    expect(find.textContaining('giriş'), findsNothing);
  });

  testWidgets('kayıtlı aramaların hepsi girişsiz görünür', (tester) async {
    await LocalMapSearchHistory.remember(
      displayName: 'Kayseri',
      addressSummary: 'Kayseri',
      radiusKm: 25,
      facilityType: 'Tümü',
      latitude: 38.73,
      longitude: 35.48,
      facilities: const [(il: 'Kayseri', isim: 'Erciyes')],
    );
    await LocalMapSearchHistory.remember(
      displayName: 'Ankara',
      addressSummary: 'Ankara',
      radiusKm: 10,
      facilityType: 'Tümü',
      latitude: 39.93,
      longitude: 32.86,
      facilities: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMapSearchHistorySheet(
                context: context,
                onReplay: (MapHistoryEntry entry) async {},
              ),
              child: const Text('Geçmişi aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Geçmişi aç'));
    await tester.pumpAndSettle();
    expect(find.text('Ankara'), findsWidgets);
    expect(find.text('Kayseri'), findsWidgets);
    expect(find.text('Tekrar gör'), findsNWidgets(2));
    expect(find.textContaining('GitHub'), findsNothing);
  });
}
