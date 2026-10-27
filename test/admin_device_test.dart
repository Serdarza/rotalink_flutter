import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotalink_flutter/models/admin_popup.dart';
import 'package:rotalink_flutter/services/device_test_service.dart';
import 'package:rotalink_flutter/services/device_test_messaging.dart';
import 'package:rotalink_flutter/widgets/admin_popup_host.dart';

const uuid = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> sample({String frequency = 'once'}) => {
  'id': uuid,
  'version': 1,
  'title': 'Telefon denemesi',
  'body': 'Rotalink pop-up testi',
  'frequency': frequency,
  'priority': 5,
  'route': 'kampanyalar',
  'buttonLabel': 'Keşfet',
};
http.Response jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'FCM tanısı yalnızca sabit kodları gösterir; hata içeriğini sızdırmaz',
    () {
      expect(
        DeviceTestMessaging.diagnosticCode(MissingPluginException()),
        'PLUGIN_MISSING',
      );
      expect(
        DeviceTestMessaging.diagnosticCode(TimeoutException('private')),
        'TIMEOUT',
      );
      expect(
        DeviceTestMessaging.diagnosticCode(
          PlatformException(
            code: 'unknown',
            message: 'private-token SERVICE_NOT_AVAILABLE',
          ),
        ),
        'SERVICE_NOT_AVAILABLE',
      );
      expect(
        DeviceTestMessaging.diagnosticCode(
          PlatformException(code: 'secret', message: 'private-token'),
        ),
        'PLATFORM_ERROR',
      );
      expect(
        DeviceTestMessaging.diagnosticCode(StateError('private-token')),
        'UNKNOWN',
      );
    },
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
    'Görselsiz pop-up boş görsel oluşturmaz',
    () => expect(AdminPopup.parse(sample()).imageUrl, isNull),
  );
  test('HTTPS dış bağlantı ve mevcut panel rotaları desteklenir', () {
    for (final route in [
      'kampanyalar',
      'tesisler',
      'pro',
      'tatiller',
      'external',
    ]) {
      expect(
        AdminPopup.parse({
          ...sample(),
          'route': route,
          'link': 'https://rotalink.tr/',
        }).route,
        route,
      );
    }
  });
  test('Özel görsel yalnızca admin kaynağından okunur', () {
    final p = AdminPopup.parse({
      ...sample(),
      'imageUrl': '/device-test/media/$uuid',
    });
    expect(p.imageUrl!.host, 'admin.rotalink.tr');
    expect(
      () => AdminPopup.parse({
        ...sample(),
        'imageUrl': 'https://evil.example/image.jpg',
      }),
      throwsFormatException,
    );
  });
  test('Kod ve script bağlantıları reddedilir', () {
    expect(
      () => AdminPopup.parse({...sample(), 'link': 'javascript:alert(1)'}),
      throwsFormatException,
    );
  });
  test(
    'Bilinmeyen rota reddedilir',
    () => expect(
      () => AdminPopup.parse({...sample(), 'route': 'unknown'}),
      throwsFormatException,
    ),
  );
  test('Bir kez gösterim geçmişi korunur', () {
    final p = AdminPopup.parse(sample());
    expect(
      p.eligible(DateTime.utc(2026, 10, 25), {
        p.historyKey: '2026-10-24T12:00:00Z',
      }, {}),
      isFalse,
    );
  });
  test('Günlük gösterim İstanbul gece sınırını kullanır', () {
    final p = AdminPopup.parse(sample(frequency: 'daily')),
        h = {p.historyKey: '2026-10-24T20:30:00Z'};
    expect(p.eligible(DateTime.utc(2026, 10, 24, 20, 59), h, {}), isFalse);
    expect(p.eligible(DateTime.utc(2026, 10, 24, 21, 1), h, {}), isTrue);
  });
  test('Her açılış aynı oturumda tekrar gösterilmez', () {
    final p = AdminPopup.parse(sample(frequency: 'every_launch'));
    expect(p.eligible(DateTime.utc(2026, 10, 25), {}, {p.historyKey}), isFalse);
    expect(
      p.eligible(DateTime.utc(2026, 10, 25), {
        p.historyKey: '2026-10-24T12:00:00Z',
      }, {}),
      isTrue,
    );
  });
  test('Yayın başlangıcı ve bitişi uygulanır', () {
    final p = AdminPopup.parse({
      ...sample(),
      'startsAt': '2026-10-25T12:00:00Z',
      'endsAt': '2026-10-26T12:00:00Z',
    });
    expect(p.eligible(DateTime.utc(2026, 10, 25, 11), {}, {}), isFalse);
    expect(p.eligible(DateTime.utc(2026, 10, 25, 12), {}, {}), isTrue);
    expect(p.eligible(DateTime.utc(2026, 10, 26, 12), {}, {}), isFalse);
  });
  test('Geçersiz eşleştirme kodu ağa gönderilmez', () async {
    var calls = 0;
    final service = DeviceTestService(
      client: MockClient((r) async {
        calls++;
        return jsonResponse({});
      }),
    );
    await expectLater(service.pair('short'), throwsFormatException);
    expect(calls, 0);
    service.dispose();
  });
  test(
    'Telefon belirteci güvenli depoda, HTTP bearer yalnızca test isteklerinde',
    () async {
      final paths = <String>[];
      final service = DeviceTestService(
        client: MockClient((r) async {
          paths.add(r.url.path);
          if (r.url.path.endsWith('/pair')) {
            expect(r.headers.containsKey('authorization'), isFalse);
            return jsonResponse({
              'id': uuid,
              'token': 'x' * 43,
              'expiresAt': '2099-01-01T00:00:00Z',
              'label': 'Telefonum',
            });
          }
          expect(r.headers['authorization'], 'Bearer ${'x' * 43}');
          return jsonResponse({
            'id': uuid,
            'items': [
              {...sample(), 'deliveryId': uuid},
            ],
          });
        }),
      );
      await service.pair('ABCD-1234-ABCD-1234-ABCD');
      expect(service.paired, isTrue);
      expect(service.items.length, 1);
      expect(paths, ['/device-test/pair', '/device-test/state']);
      final storage = const FlutterSecureStorage();
      expect(
        await storage.read(key: DeviceTestService.storageKey),
        contains('expiresAt'),
      );
      service.dispose();
    },
  );
  test('Yabancı oturum bildirimi işlenmez', () async {
    final service = DeviceTestService(
      client: MockClient((r) async => jsonResponse({})),
    );
    expect(
      await service.message({
        'type': 'rotalink_admin_test',
        'testSession': uuid,
        'testDelivery': uuid,
      }),
      isFalse,
    );
    service.dispose();
  });
  test('FCM görsel adresi yalnızca geçici test kaynağını kabul eder', () {
    expect(
      DeviceTestMessaging.validImage(
        'https://admin.rotalink.tr/device-test/image/${'x' * 43}/$uuid.jpg',
      ),
      isTrue,
    );
    expect(
      DeviceTestMessaging.validImage('https://evil.example/picture.jpg'),
      isFalse,
    );
    expect(
      DeviceTestMessaging.validImage(
        'https://admin.rotalink.tr/api/media/$uuid',
      ),
      isFalse,
    );
  });
  test(
    'Yeni Android düzeni yalnızca yerel köprü hazırsa bildirilir ve çıkışta silinir',
    () async {
      const channel = MethodChannel('rotalink/admin_notification_layout');
      final nativeCalls = <Map<dynamic, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeCalls.add(Map<dynamic, dynamic>.from(call.arguments));
            return call.arguments['id'] == null ? 0 : 2;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      Map<String, dynamic>? registration;
      final service = DeviceTestService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/pair')) {
            return jsonResponse({
              'id': uuid,
              'token': 'x' * 43,
              'label': 'Test',
              'expiresAt': DateTime.now()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
            });
          }
          if (request.url.path.endsWith('/fcm')) {
            registration = jsonDecode(request.body);
          }
          return jsonResponse({'items': []});
        }),
      );
      await service.pair('A' * 20);
      await service.updateFcm('test-token');
      expect(registration!['notificationRenderer'], 2);
      expect(nativeCalls.last.keys, unorderedEquals(['id', 'expiresAt']));
      expect(nativeCalls.last['id'], uuid);
      await service.disconnect(remote: false);
      expect(nativeCalls.last['id'], isNull);
      service.dispose();
    },
  );
  test(
    'Yerel bildirim dokunması, soğuk açılışta da oturum ve hedefi doğrular',
    () async {
      var events = 0;
      final service = DeviceTestService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/pair')) {
            return jsonResponse({
              'id': uuid,
              'token': 'x' * 43,
              'label': 'Test',
              'expiresAt': DateTime.now()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
            });
          }
          if (request.url.path.endsWith('/events')) events++;
          return jsonResponse({'items': []});
        }),
      );
      await service.pair('A' * 20);
      final target = {
        'type': 'rotalink_admin_test',
        'testSession': uuid,
        'testDelivery': uuid,
        'route': 'tatiller',
        'link': '',
      };
      await service.localTap(
        'native2:${jsonEncode({...target, 'testSession': '22222222-2222-4222-8222-222222222222'})}',
      );
      expect(events, 0);
      await service.localTap('native2:${jsonEncode(target)}');
      expect(events, 1);
      expect(service.pendingTarget!['route'], 'tatiller');
      service.dispose();
    },
  );
  testWidgets('Küçük ekranda büyük yazı, görselsiz içerik ve kapatma', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.6),
          ),
          child: AdminPopupDialog(
            popup: AdminPopup.parse(sample()),
            onClose: () => closed++,
            onAction: () {},
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('Telefon denemesi'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Kapat'));
    expect(closed, 1);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AdminPopupDialog(
          popup: AdminPopup.parse(sample()),
          onClose: () {},
          onAction: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
