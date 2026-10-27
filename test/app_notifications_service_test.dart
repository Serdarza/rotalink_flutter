import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotalink_flutter/services/app_notifications_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final message = <String, String>{
    'type': 'rotalink_admin',
    'notificationRenderer': '2',
    'notificationId': '11111111-1111-4111-8111-111111111111',
    'route': 'tatiller',
    'link': '',
  };
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppNotificationsService.pendingTarget = null;
  });
  test('Normal APK konusu test ve eski kampanya konularından ayrıdır', () {
    expect(AppNotificationsService.topic, 'rotalink_admin_android_v2');
    expect(AppNotificationsService.topic, isNot('kampanya_yeni'));
  });
  test('Yalnızca doğrulanmış bildirim türü ve izinli hedef kabul edilir', () {
    expect(AppNotificationsService.parseTarget(message)!['route'], 'tatiller');
    for (final fields in [
      {'type': 'rotalink_admin_test'},
      {'route': 'admin'},
      {'notificationId': '../secret'},
      {'notificationRenderer': '1'},
    ]) {
      expect(
        AppNotificationsService.parseTarget({...message, ...fields}),
        isNull,
      );
    }
  });
  test('Dış bağlantı HTTPS ve kullanıcı bilgisi içermeyen adres ister', () {
    for (final link in [
      '',
      'http://rotalink.tr',
      'javascript:alert(1)',
      'https://user:pass@rotalink.tr',
    ]) {
      expect(
        AppNotificationsService.parseTarget({
          ...message,
          'route': 'external',
          'link': link,
        }),
        isNull,
      );
    }
    expect(
      AppNotificationsService.parseTarget({
        ...message,
        'route': 'external',
        'link': 'https://rotalink.tr',
      })!['link'],
      'https://rotalink.tr',
    );
  });
  test(
    'Soğuk açılış hedefi saklanır ve tüketildikten sonra tekrar açılmaz',
    () async {
      await AppNotificationsService.handleTap(
        'admin_push:${jsonEncode(message)}',
      );
      expect(AppNotificationsService.pendingTarget!['route'], 'tatiller');
      AppNotificationsService.pendingTarget = null;
      await AppNotificationsService.loadPending();
      expect(AppNotificationsService.pendingTarget!['route'], 'tatiller');
      await AppNotificationsService.consumePending();
      await AppNotificationsService.loadPending();
      expect(AppNotificationsService.pendingTarget, isNull);
    },
  );
  test('Bozuk veya test yükü normal bildirim hedefini oluşturmaz', () async {
    await AppNotificationsService.handleTap('admin_push:broken');
    await AppNotificationsService.handleTap(
      'admin_test:${jsonEncode(message)}',
    );
    expect(AppNotificationsService.pendingTarget, isNull);
  });
  test(
    'Bildirim tercihi mevcut diğer bildirim tercihlerini değiştirmez',
    () async {
      SharedPreferences.setMockInitialValues({
        'rotalink_campaign_push_enabled': false,
      });
      expect(await AppNotificationsService.isEnabled(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppNotificationsService.prefKey, false);
      expect(await AppNotificationsService.isEnabled(), isFalse);
      expect(prefs.getBool('rotalink_campaign_push_enabled'), isFalse);
    },
  );
}
