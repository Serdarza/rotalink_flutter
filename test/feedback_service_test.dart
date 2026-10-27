import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rotalink_flutter/services/feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'e-posta gerektirmeden gönderir; durum, not ve konum istemci göndermez',
    () async {
      final service = FeedbackService(
        version: () async => '4.8.2+86',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.url.path, '/public/feedback');
          expect(body['email'], '');
          expect(body['contactConsent'], false);
          expect(body.keys, isNot(contains('status')));
          expect(body.keys, isNot(contains('adminNote')));
          expect(body.keys, isNot(contains('latitude')));
          return http.Response(
            jsonEncode({'accepted': true, 'id': body['id']}),
            201,
          );
        }),
      );
      expect(
        await service.submit(
          kind: FeedbackKind.suggestion,
          description: 'Güzel bir öneri',
          sourcePage: 'Ana Sayfa',
        ),
        matches(RegExp(r'^[a-f0-9]{64}$')),
      );
      await expectLater(
        service.submit(
          kind: FeedbackKind.bug,
          description: 'Başka bildirim',
          sourcePage: 'Ara',
        ),
        throwsA(isA<FeedbackException>()),
      );
    },
  );
  test('izin verilmemiş veya geçersiz e-posta sunucuya gitmez', () async {
    var calls = 0;
    final service = FeedbackService(
      client: MockClient((_) async {
        calls++;
        return http.Response('', 500);
      }),
    );
    for (final email in ['bad', 'a@example.com']) {
      await expectLater(
        service.submit(
          kind: FeedbackKind.bug,
          description: 'Hata açıklaması',
          sourcePage: 'Ara',
          email: email,
        ),
        throwsA(isA<FeedbackException>()),
      );
    }
    expect(calls, 0);
  });
  test('yanıt kaybolunca aynı gönderim kimliğiyle tekrar dener', () async {
    final ids = <String>[];
    final service = FeedbackService(
      version: () async => '1+1',
      client: MockClient((r) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        ids.add(body['id'] as String);
        if (ids.length == 1) throw http.ClientException('offline');
        return http.Response(
          jsonEncode({'accepted': true, 'id': body['id']}),
          201,
        );
      }),
    );
    Future<String> send() => service.submit(
      kind: FeedbackKind.complaint,
      description: 'Açıklama metni',
      sourcePage: 'Konaklama',
    );
    await expectLater(send(), throwsA(isA<FeedbackException>()));
    await send();
    expect(ids.length, 2);
    expect(ids[0], ids[1]);
  });
  test('503 veya sahte başarı yanıtı teşekkür olarak kabul edilmez', () async {
    for (final response in [
      http.Response('{}', 503),
      http.Response('{"accepted":true,"id":"other"}', 200),
    ]) {
      final service = FeedbackService(
        version: () async => '1+1',
        client: MockClient((_) async => response),
      );
      await expectLater(
        service.submit(
          kind: FeedbackKind.bug,
          description: 'Bir hata bildirimi',
          sourcePage: 'Ara',
        ),
        throwsA(isA<FeedbackException>()),
      );
    }
  });
  test(
    'canlı gönderim yolu kurulmamışsa kullanıcı bilgilerini suçlamaz',
    () async {
      for (final status in [404, 405, 501]) {
        final service = FeedbackService(
          version: () async => '1+1',
          client: MockClient((_) async => http.Response('', status)),
        );
        await expectLater(
          service.submit(
            kind: FeedbackKind.bug,
            description: 'Hata açıklaması',
            sourcePage: 'Ana Sayfa',
          ),
          throwsA(
            isA<FeedbackException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('henüz etkin değil'),
                contains('formda korunuyor'),
              ),
            ),
          ),
        );
      }
    },
  );
}
