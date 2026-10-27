import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotalink_flutter/data/campaign_repository.dart';
import 'package:rotalink_flutter/models/campaign_insights.dart';
import 'package:rotalink_flutter/screens/discover_screen.dart';
import 'package:rotalink_flutter/screens/campaign_detail_screen.dart';
import 'package:rotalink_flutter/widgets/campaign_promotion_card.dart';

void main() {
  testWidgets(
    'tüm kurum sekmeleri, sayaçlar ve arama aynı kampanyaları gösterir',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      const network = MethodChannel('dev.fluttercommunity.plus/connectivity');
      const promotionTitle = 'Tesisiniz veya kampanyanız Rotalink’te yer alsın';
      const promotionLink =
          'mailto:rotalinkinfo@gmail.com?subject=Rotalink%20Kampanya';
      const tags = {
        CampaignAudience.teacher: 'Öğretmen',
        CampaignAudience.health: 'Sağlık Çalışanı',
        CampaignAudience.police: 'Emniyet',
        CampaignAudience.military: 'TSK',
        CampaignAudience.gendarmerie: 'Jandarma',
        CampaignAudience.academic: 'Akademisyen',
        CampaignAudience.municipal: 'Belediye Personeli',
        CampaignAudience.publicGeneral: 'Kamu Personeli',
      };
      String title(CampaignAudience audience) =>
          '${audience.label} için özel kampanya';
      final repository = CampaignRepository.instance;
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'rotalink_campaign_tabs_',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          paths,
          (_) async => directory.path,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          network,
          (_) async => ['none'],
        );
        await File('${directory.path}/rotalink_kampanyalar.json').writeAsString(
          jsonEncode({
            'kampanyalar': [
              for (final entry in tags.entries)
                {
                  'id': entry.key.name,
                  'baslik': title(entry.key),
                  'kurum': entry.key == CampaignAudience.police
                      ? 'Emniyet Teşkilatı Sendikası'
                      : 'Kampanya sağlayıcısı',
                  'etiketler': [entry.value],
                },
              {
                'id': 'shared',
                'baslik': 'Ortak kurum kampanyası',
                'etiketler': ['Emniyet', 'TSK', 'Jandarma'],
              },
              {
                'id': 'promotion',
                'baslik': promotionTitle,
                'aciklama': 'Tesis ve kampanyalarınız için iletişime geçin.',
                'link': promotionLink,
                'tarih': '2020-01-01T00:00:00Z',
                'etiketler': ['TSK'],
              },
            ],
          }),
        );
        await repository.ensureLocalDataReady();
      });
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          paths,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          network,
          null,
        );
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(home: DiscoverScreen(repository: repository)),
      );
      await tester.pumpAndSettle();

      Finder chip(String label, int count) => find.byWidgetPredicate(
        (w) =>
            w is Semantics && w.properties.label == '$label, $count kampanya',
      );
      final horizontal = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      );
      final tabScroll = find.descendant(
        of: horizontal,
        matching: find.byType(Scrollable),
      );
      Future<void> selectChip(Finder target, double delta) async {
        await tester.scrollUntilVisible(target, delta, scrollable: tabScroll);
        await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(target.hitTestable());
        await tester.pumpAndSettle();
      }

      int listCount() {
        final list = tester
            .widgetList<ListView>(find.byType(ListView))
            .singleWhere((w) => w.scrollDirection == Axis.vertical);
        return (list.childrenDelegate as SliverChildBuilderDelegate)
            .childCount!;
      }

      expect(listCount(), 10);
      expect(find.byType(CampaignPromotionCard), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(promotionTitle)).dy,
        lessThan(
          tester.getTopLeft(find.text(title(CampaignAudience.teacher))).dy,
        ),
      );
      for (final audience in CampaignAudience.values) {
        final shared = {
          CampaignAudience.police,
          CampaignAudience.military,
          CampaignAudience.gendarmerie,
        }.contains(audience);
        final expected = audience == CampaignAudience.publicGeneral
            ? 1
            : (shared ? 3 : 2);
        final target = chip(audience.label, expected);
        await selectChip(target, 200);
        expect(find.byType(CampaignPromotionCard), findsNothing);
        expect(listCount(), expected, reason: audience.label);
        expect(find.text(title(audience)), findsOneWidget);
        expect(
          find.text(title(CampaignAudience.publicGeneral)),
          findsOneWidget,
        );
        expect(
          find.text('Ortak kurum kampanyası'),
          shared ? findsOneWidget : findsNothing,
        );
      }
      await selectChip(chip('Emniyet', 3), -200);
      await tester.enterText(find.byType(TextField), 'Sendikası');
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pumpAndSettle();
      expect(listCount(), 1);
      expect(find.text(title(CampaignAudience.police)), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pumpAndSettle();
      expect(listCount(), 3);
      await selectChip(chip('Tümü', 10), -200);
      expect(listCount(), 10);
      expect(find.byType(CampaignPromotionCard), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'bulunmayan arama');
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pumpAndSettle();
      expect(listCount(), 1);
      expect(find.byType(CampaignPromotionCard), findsOneWidget);
      await tester.tap(find.text(promotionTitle));
      await tester.pumpAndSettle();
      final detail = tester.widget<CampaignDetailScreen>(
        find.byType(CampaignDetailScreen),
      );
      expect(detail.campaign.linkUrl, promotionLink);
      expect(find.text('E-posta ile iletişime geç'), findsOneWidget);
      expect(find.textContaining('Bu bağlantı üçüncü taraf'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
