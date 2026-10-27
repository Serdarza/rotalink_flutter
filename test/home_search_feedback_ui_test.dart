import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rotalink_flutter/services/feedback_service.dart';
import 'package:rotalink_flutter/theme/app_theme.dart';
import 'package:rotalink_flutter/widgets/custom_search_bar.dart';
import 'package:rotalink_flutter/widgets/feedback_report_button.dart';

void main() {
  testWidgets(
    'ana arama Android/iOS, küçük ekran ve iki temada tek yüzeydir, metin araması korunur',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var submits = 0;
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        for (final dark in [false, true]) {
          for (final width in [320.0, 430.0]) {
            tester.view.physicalSize = Size(width, 700);
            controller.clear();
            await tester.pumpWidget(
              MaterialApp(
                theme: (dark ? buildRotalinkDarkTheme() : buildRotalinkTheme())
                    .copyWith(platform: platform),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 700),
                    textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
                  ),
                  child: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CustomSearchBar(
                        controller: controller,
                        compactHome: true,
                        ignoreKeyboardInset: true,
                        onSubmitted: () => submits++,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(find.text('İl veya misafirhane ara...'), findsOneWidget);
            expect(find.textContaining('Trabzon'), findsNothing);
            expect(find.byTooltip('Sesli ara'), findsOneWidget);
            final field = tester.widget<TextField>(find.byType(TextField));
            expect(field.decoration?.filled, false);
            await tester.enterText(find.byType(TextField), 'Ankara');
            await tester.testTextInput.receiveAction(TextInputAction.search);
            await tester.pump();
            expect(tester.takeException(), isNull);
          }
        }
      }
      expect(submits, 8);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'bildir formu klavyede kaydırılır, başarısız gönderimde açıklama korunur',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final service = FeedbackService(
        version: () async => '1+1',
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackReportForm(sourcePage: 'Ana Sayfa', service: service),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'Test açıklaması');
      await tester.ensureVisible(find.text('Gönder'));
      await tester.tap(find.text('Gönder'));
      await tester.pumpAndSettle();
      expect(find.textContaining('şu anda kullanılamıyor'), findsOneWidget);
      expect(find.text('Test açıklaması'), findsOneWidget);
      expect(find.text('Teşekkürler, bildiriminiz alındı.'), findsNothing);
    },
  );
}
