import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/screens/settings_screen.dart';
import 'package:rotalink_flutter/services/announcement_notification_scheduler.dart';
import 'package:rotalink_flutter/services/campaign_push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CampaignPushService.debugReset();
    CampaignPushService.debugSetPermission(() async => true);
  });

  tearDown(CampaignPushService.debugReset);

  group('metin ve sabitler', () {
    test('ayar başlığı ve açıklaması istenen metinle birebir aynı', () {
      expect(CampaignPushService.settingTitle, 'Yeni Kampanya Bildirimleri');
      expect(
        CampaignPushService.settingDescription,
        'Uygulama yeni kampanyaları indirdiğinde bildirim al.',
      );
    });

    test('kanal kimliği yerel bildirimle aynı', () {
      expect(CampaignPushService.channelId, 'rotalink_campaigns');
    });

    test('sayıya göre başlık Rotalink der', () {
      expect(
        CampaignPushService.buildText(5).$1,
        'Rotalink – 5 Yeni Kampanya Eklendi! 🎉',
      );
      expect(
        CampaignPushService.buildText(0).$1,
        'Rotalink – Yeni Kampanyalar Eklendi! 🎉',
      );
    });
  });

  group('açma / kapama', () {
    test('varsayılan açık', () async {
      expect(await CampaignPushService.isEnabled(), isTrue);
    });

    test('açıkken izin istenir', () async {
      var requests = 0;
      CampaignPushService.debugSetPermission(() async {
        requests++;
        return true;
      });
      final permitted = await CampaignPushService.setEnabled(true);
      expect(permitted, isTrue);
      expect(requests, 1);
      expect(await CampaignPushService.isEnabled(), isTrue);
    });

    test('kapatınca tercih kalıcı olur ve izin istenmez', () async {
      var requests = 0;
      CampaignPushService.debugSetPermission(() async {
        requests++;
        return true;
      });
      await CampaignPushService.setEnabled(false);
      expect(requests, 0);
      expect(await CampaignPushService.isEnabled(), isFalse);
    });

    test('izin reddedilse de tercih saklanır; kullanıcıya false döner', () async {
      CampaignPushService.debugSetPermission(() async => false);
      expect(await CampaignPushService.setEnabled(true), isFalse);
      expect(await CampaignPushService.isEnabled(), isTrue);
    });
  });

  group('diğer bildirim tercihlerine dokunmaz', () {
    test('duyuru ve tatil tercihleri değişmez', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'rotalink_announcements_enabled': false,
        'rotalink_pending_open_holidays_from_notification': true,
        'rotalink_announcements_cache': '{"x":1}',
      });
      await CampaignPushService.setEnabled(false);
      await CampaignPushService.setEnabled(true);

      final p = await SharedPreferences.getInstance();
      expect(p.getBool('rotalink_announcements_enabled'), isFalse);
      expect(p.getBool('rotalink_pending_open_holidays_from_notification'), isTrue);
      expect(p.getString('rotalink_announcements_cache'), '{"x":1}');
      expect(CampaignPushService.prefKey, isNot('rotalink_announcements_enabled'));
    });

    test('duyuru bildirimini kapatmak kampanya tercihini değiştirmez', () async {
      await AnnouncementNotificationScheduler.setEnabled(false)
          .catchError((Object _) {});
      expect(await AnnouncementNotificationScheduler.isEnabled(), isFalse);
      expect(await CampaignPushService.isEnabled(), isTrue);
    });
  });

  group('bildirime dokunma', () {
    test('istek Kampanya sekmesini açar', () {
      var notified = 0;
      CampaignPushService.openRequests.addListener(() => notified++);

      CampaignPushService.requestOpen();

      expect(CampaignPushService.hasPendingOpen, isTrue);
      expect(notified, 1);
      expect(CampaignPushService.consumePendingOpen(), isTrue);
      expect(CampaignPushService.consumePendingOpen(), isFalse);
    });

    test('uygulama kapalıyken dokunulan bildirim sonradan tüketilir', () {
      CampaignPushService.requestOpen();
      expect(CampaignPushService.hasPendingOpen, isTrue);
      expect(CampaignPushService.consumePendingOpen(), isTrue);
    });
  });

  group('yeni kampanya tespiti', () {
    test('ilk listede bildirim yok, taban kaydedilir', () async {
      var count = 0;
      CampaignPushService.debugSetLocalNotifier(
        ({required String title, required String body}) async => count++,
      );
      await CampaignPushService.notifyNewCampaigns(['a', 'b']);
      expect(count, 0);
      expect(await CampaignPushService.claimNewIds(['a', 'b']), isEmpty);
    });

    test('sonradan eklenenler tek bildirimle ve sayıyla gider', () async {
      final shown = <(String, String)>[];
      CampaignPushService.debugSetLocalNotifier(
        ({required String title, required String body}) async =>
            shown.add((title, body)),
      );
      await CampaignPushService.notifyNewCampaigns(['a']);
      await CampaignPushService.notifyNewCampaigns(['a', 'b', 'c']);
      expect(shown, hasLength(1));
      expect(shown.single.$1, 'Rotalink – 2 Yeni Kampanya Eklendi! 🎉');
    });

    test('aynı kimlik ikinci kez bildirim üretmez', () async {
      var count = 0;
      CampaignPushService.debugSetLocalNotifier(
        ({required String title, required String body}) async => count++,
      );
      await CampaignPushService.notifyNewCampaigns(['a']);
      await CampaignPushService.notifyNewCampaigns(['a']);
      expect(count, 0);
    });

    test('kullanıcı kapattıysa gösterilmez ama kimlikler işlenir', () async {
      await CampaignPushService.setEnabled(false);
      var count = 0;
      CampaignPushService.debugSetLocalNotifier(
        ({required String title, required String body}) async => count++,
      );
      await CampaignPushService.notifyNewCampaigns(['a']);
      await CampaignPushService.notifyNewCampaigns(['a', 'b']);
      expect(count, 0);
      await CampaignPushService.setEnabled(true);
      await CampaignPushService.notifyNewCampaigns(['a', 'b']);
      expect(count, 0);
    });
  });

  group('Ayarlar ekranı', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('yeni anahtar mevcut ekranda, açıklamasıyla görünür', (tester) async {
      await pump(tester);
      expect(find.text('Duyuru bildirimleri'), findsOneWidget);
      expect(find.text('Yeni Kampanya Bildirimleri'), findsOneWidget);
      expect(
        find.text('Uygulama yeni kampanyaları indirdiğinde bildirim al.'),
        findsOneWidget,
      );
      expect(find.text('Resmi tatil hatırlatması'), findsOneWidget);
      expect(find.text('Rotalink bildirimleri'), findsOneWidget);
    });

    testWidgets('anahtar yalnızca kampanya tercihini değiştirir', (tester) async {
      await pump(tester);
      final campaignTile = find.ancestor(
        of: find.text('Yeni Kampanya Bildirimleri'),
        matching: find.byType(SwitchListTile),
      );
      final campaignSwitch = find.descendant(
        of: campaignTile,
        matching: find.byType(Switch),
      );
      await tester.tap(campaignSwitch);
      await tester.pump(const Duration(milliseconds: 50));

      expect(await CampaignPushService.isEnabled(), isFalse);
      expect(await AnnouncementNotificationScheduler.isEnabled(), isTrue);

      await tester.tap(campaignSwitch);
      await tester.pump(const Duration(milliseconds: 50));
      expect(await CampaignPushService.isEnabled(), isTrue);
    });
  });
}
