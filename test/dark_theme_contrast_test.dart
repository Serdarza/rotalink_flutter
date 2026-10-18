import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/screens/settings_screen.dart';
import 'package:rotalink_flutter/theme/app_colors.dart';
import 'package:rotalink_flutter/theme/app_theme.dart';
import 'package:rotalink_flutter/widgets/custom_search_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, ThemeData theme, Widget home) async {
  await tester.pumpWidget(MaterialApp(theme: theme, home: home));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('tema metin renkleri açıkta koyu, koyuda açık', () {
    final light = buildRotalinkTheme();
    final dark = buildRotalinkDarkTheme();
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.textTheme.bodyLarge?.color, AppColors.textStrong);
    expect(dark.textTheme.bodyLarge?.color, AppColors.darkTextStrong);
    expect(dark.inputDecorationTheme.fillColor, AppColors.darkSurface);
    expect(light.inputDecorationTheme.fillColor, AppColors.searchBarBg);
    expect(dark.bottomSheetTheme.backgroundColor, AppColors.darkSurface);
    expect(dark.dialogTheme.backgroundColor, AppColors.darkSurface);
  });

  testWidgets('koyu temada arama metni açık renkte', (tester) async {
    final controller = TextEditingController(text: 'Ankara');
    addTearDown(controller.dispose);
    await _pump(
      tester,
      buildRotalinkDarkTheme(),
      Scaffold(body: CustomSearchBar(controller: controller)),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style?.color, AppColors.darkTextStrong);
    expect(field.cursorColor, AppColors.primary);
  });

  testWidgets('açık temada arama metni koyu renkte kalır', (tester) async {
    final controller = TextEditingController(text: 'İstanbul');
    addTearDown(controller.dispose);
    await _pump(
      tester,
      buildRotalinkTheme(),
      Scaffold(body: CustomSearchBar(controller: controller)),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style?.color, AppColors.searchBarText);
  });

  testWidgets('koyu temada ayarlar kartı koyu zemin kullanır', (tester) async {
    await _pump(
      tester,
      buildRotalinkDarkTheme(),
      const SettingsScreen(),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Yeni Kampanya Bildirimleri'), findsOneWidget);
    expect(find.text('Duyuru bildirimleri'), findsOneWidget);

    final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    final card = boxes.cast<DecoratedBox?>().firstWhere(
      (b) => b!.decoration is BoxDecoration &&
          (b.decoration as BoxDecoration).color == AppColors.darkSurface,
      orElse: () => null,
    );
    expect(card, isNotNull);
  });

  testWidgets('açık temada ayarlar kartı beyaz kalır', (tester) async {
    await _pump(tester, buildRotalinkTheme(), const SettingsScreen());
    await tester.pump(const Duration(milliseconds: 50));
    final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    final card = boxes.cast<DecoratedBox?>().firstWhere(
      (b) => b!.decoration is BoxDecoration &&
          (b.decoration as BoxDecoration).color == AppColors.surface,
      orElse: () => null,
    );
    expect(card, isNotNull);
  });
}
