import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/screens/settings_screen.dart';
import 'package:rotalink_flutter/services/announcement_notification_scheduler.dart';
import 'package:rotalink_flutter/services/campaign_push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeClient implements CampaignMessagingClient {
  final List<String> subscribed = [];
  final List<String> unsubscribed = [];
  int permissionRequests = 0;
  bool permissionResult = true;
  bool ready = true;
  Object? subscribeError;

  @override
  Future<bool> isReadyToSubscribe() async => ready;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionResult;
  }

  @override
  Future<void> subscribe(String topic) async {
    if (subscribeError != null) throw subscribeError!;
    subscribed.add(topic);
  }

  @override
  Future<void> unsubscribe(String topic) async => unsubscribed.add(topic);
}

void main() {
  late _FakeClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    client = _FakeClient();
    CampaignPushService.debugReset();
    CampaignPushService.debugSetClient(client);
  });

  tearDown(CampaignPushService.debugReset);

  group('metin ve sabitler', () {
    test('ayar başlığı ve açıklaması istenen metinle birebir aynı', () {
      expect(CampaignPushService.settingTitle, 'Yeni Kampanya Bildirimleri');
      expect(
        CampaignPushService.settingDescription,
        'Rotalink\'e yeni kampanyalar eklendiğinde bildirim al.',
      );
    });

    test('konu adı sunucuyla (collector/notify.py) aynı', () {
      expect(CampaignPushService.topic, 'kampanya_yeni');
      expect(CampaignPushService.channelId, 'rotalink_campaigns');
    });
  });

  group('açma / kapama', () {
    test('varsayılan açık', () async {
      expect(await CampaignPushService.isEnabled(), isTrue);
    });

    test('açıkken izin istenir ve konuya abone olunur', () async {
      final permitted = await CampaignPushService.setEnabled(true);
      expect(permitted, isTrue);
      expect(client.permissionRequests, 1);
      expect(client.subscribed, ['kampanya_yeni']);
      expect(await CampaignPushService.isEnabled(), isTrue);
    });

    test('kapatınca konudan çıkılır ve tercih kalıcı olur', () async {
      await CampaignPushService.setEnabled(false);
      expect(client.unsubscribed, ['kampanya_yeni']);
      expect(client.subscribed, isEmpty);
      expect(client.permissionRequests, 0);
      expect(await CampaignPushService.isEnabled(), isFalse);

      // "Yeniden başlatma": tercih diskten okunur ve abonelik kapalı kalır.
      client.unsubscribed.clear();
      await CampaignPushService.syncSubscription();
      expect(client.unsubscribed, ['kampanya_yeni']);
      expect(client.subscribed, isEmpty);
    });

    test('izin reddedilse de tercih saklanır; kullanıcıya false döner', () async {
      client.permissionResult = false;
      expect(await CampaignPushService.setEnabled(true), isFalse);
      expect(await CampaignPushService.isEnabled(), isTrue);
    });

    test('abonelik hatası uygulamayı çökertmez', () async {
      client.subscribeError = StateError('apns-token-not-set');
      await CampaignPushService.setEnabled(true);
      expect(await CampaignPushService.isEnabled(), isTrue);
    });

    test('APNs token hazır değilse abonelik denenmez (token yenilenince tekrar)', () async {
      client.ready = false;
      await CampaignPushService.syncSubscription();
      expect(client.subscribed, isEmpty);
      expect(client.unsubscribed, isEmpty);
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
    test('kampanya mesajı Kampanya sekmesi isteği oluşturur', () {
      var notified = 0;
      CampaignPushService.openRequests.addListener(() => notified++);

      CampaignPushService.handleOpenedMessage(<String, dynamic>{
        'type': 'new_campaigns',
        'route': 'kampanyalar',
      });

      expect(CampaignPushService.hasPendingOpen, isTrue);
      expect(notified, 1);
      expect(CampaignPushService.consumePendingOpen(), isTrue);
      // Tek seferlik: ikinci tüketimde istek kalmaz.
      expect(CampaignPushService.consumePendingOpen(), isFalse);
    });

    test('uygulama kapalıyken dokunulan bildirim (bekleyen istek) sonradan tüketilir', () {
      // Shell henüz dinlemiyorken gelen istek bekletilir.
      CampaignPushService.handleOpenedMessage(<String, dynamic>{'route': 'kampanyalar'});
      expect(CampaignPushService.hasPendingOpen, isTrue);
      // Shell hazır olunca:
      expect(CampaignPushService.consumePendingOpen(), isTrue);
    });

    test('kampanya dışı mesaj Kampanya sekmesini açmaz', () {
      CampaignPushService.handleOpenedMessage(<String, dynamic>{'type': 'other'});
      expect(CampaignPushService.hasPendingOpen, isFalse);
    });

    test('isCampaignMessage', () {
      expect(CampaignPushService.isCampaignMessage({'type': 'new_campaigns'}), isTrue);
      expect(CampaignPushService.isCampaignMessage({'route': 'kampanyalar'}), isTrue);
      expect(CampaignPushService.isCampaignMessage({'route': 'tatiller'}), isFalse);
      expect(CampaignPushService.isCampaignMessage({}), isFalse);
    });
  });

  group('ön plan', () {
    test('açıkken yerel bildirim gösterilir (sunucu metniyle)', () async {
      final shown = <(String, String)>[];
      CampaignPushService.debugSetLocalNotifier(
        ({required String title, required String body}) async => shown.add((title, body)),
      );
      await CampaignPushService.handleForegroundMessage(
        {'type': 'new_campaigns'},
        'Rotalink – 5 Yeni Kampanya Eklendi! 🎉',
        'Yeni fırsatları keşfetmek için hemen Rotalink\'i aç!',
      );
      expect(shown, hasLength(1));
      expect(shown.single.$1, 'Rotalink – 5 Yeni Kampanya Eklendi! 🎉');
    });

    test('kullanıcı kapattıysa gösterilmez', () async {
      await CampaignPushService.setEnabled(false);
      var count = 0;
      CampaignPushService.debugSetLocalNotifier(
        ({required String title, required String body}) async => count++,
      );
      await CampaignPushService.handleForegroundMessage({'type': 'new_campaigns'}, 't', 'b');
      expect(count, 0);
    });

    test('kampanya dışı mesaj gösterilmez', () async {
      var count = 0;
      CampaignPushService.debugSetLocalNotifier(
        ({required String title, required String body}) async => count++,
      );
      await CampaignPushService.handleForegroundMessage({'type': 'x'}, 't', 'b');
      expect(count, 0);
    });

    test('başlık yoksa varsayılan Rotalink metni kullanılır', () async {
      String? gotTitle;
      String? gotBody;
      CampaignPushService.debugSetLocalNotifier(
        ({required String title, required String body}) async {
          gotTitle = title;
          gotBody = body;
        },
      );
      await CampaignPushService.handleForegroundMessage({'type': 'new_campaigns'}, null, null);
      expect(gotTitle, 'Rotalink – Yeni Kampanyalar Eklendi! 🎉');
      expect(
        gotBody,
        'Rotalink\'e yeni kampanyalar eklendi. Fırsatları kaçırmamak için hemen keşfet!',
      );
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
        find.text('Rotalink\'e yeni kampanyalar eklendiğinde bildirim al.'),
        findsOneWidget,
      );
      expect(find.text('Resmi tatil hatırlatması'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(4));
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
      expect(client.unsubscribed, ['kampanya_yeni']);

      await tester.tap(campaignSwitch);
      await tester.pump(const Duration(milliseconds: 50));
      expect(await CampaignPushService.isEnabled(), isTrue);
      expect(client.subscribed, ['kampanya_yeni']);
    });
  });
}
