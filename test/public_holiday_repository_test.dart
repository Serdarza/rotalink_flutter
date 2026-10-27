import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotalink_flutter/constants/public_holidays_2026.dart';
import 'package:rotalink_flutter/services/public_holiday_repository.dart';

Map<String, dynamic> holiday({
  String id = 'holiday-1',
  String start = '2027-01-01',
  String end = '2027-01-01',
  bool active = true,
}) => {
  'id': id,
  'name': 'Yılbaşı',
  'startDate': start,
  'endDate': end,
  'kind': 'milli',
  'detail': '',
  'active': active,
  'sourceUrl': '',
};
Map<String, dynamic> document(
  List<Map<String, dynamic>> items, {
  int revision = 1,
}) => {
  'schemaVersion': 1,
  'published': true,
  'revision': revision,
  'items': items,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('ilk çevrimdışı açılış gömülü listeyi korur', () async {
    final repo = PublicHolidayRepository(
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(await repo.refresh(force: true), false);
    expect(repo.items.length, kPublicHolidays.length);
    expect(repo.hasPublishedData, false);
    repo.dispose();
  });
  test(
    'uzak yayın gömülü listeye eklenmez; tam liste olarak kullanılır',
    () async {
      final repo = PublicHolidayRepository(
        client: MockClient((r) async {
          expect(r.url, PublicHolidayRepository.endpoint);
          return http.Response(
            jsonEncode(document([holiday()])),
            200,
            headers: {"content-type": "application/json; charset=utf-8"},
          );
        }),
      );
      expect(await repo.refresh(force: true), true);
      expect(repo.items.length, 1);
      expect(repo.items.single.name, 'Yılbaşı');
      expect(repo.revision, 1);
      repo.dispose();
    },
  );
  test(
    'tamamen boş yayın kaldırılan tatilleri geri getirmez; yeniden açılışta da korunur',
    () async {
      var payload = document([holiday()]);
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(payload),
          200,
          headers: {"content-type": "application/json; charset=utf-8"},
        ),
      );
      final repo = PublicHolidayRepository(client: client);
      await repo.refresh(force: true);
      payload = document([], revision: 2);
      expect(await repo.refresh(force: true), true);
      expect(repo.items, isEmpty);
      repo.dispose();
      final offline = PublicHolidayRepository(
        client: MockClient((_) async => throw const FormatException('offline')),
      );
      await offline.refresh(force: true);
      expect(offline.items, isEmpty);
      expect(offline.revision, 2);
      offline.dispose();
    },
  );
  test(
    'bozuk yeni cevap son geçerli listeyi ve cache sürümünü bozmaz',
    () async {
      var payload = document([holiday()]);
      final repo = PublicHolidayRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(payload),
            200,
            headers: {"content-type": "application/json; charset=utf-8"},
          ),
        ),
      );
      await repo.refresh(force: true);
      payload = document([
        holiday(start: '2027-02-30', end: '2027-03-01'),
      ], revision: 2);
      expect(await repo.refresh(force: true), false);
      expect(repo.revision, 1);
      expect(repo.items.single.start, DateTime(2027, 1, 1));
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString(PublicHolidayRepository.cacheKey)!,
        )['revision'],
        1,
      );
      repo.dispose();
    },
  );
  test('eski CDN cevabı yeni listeyi geriye götürmez', () async {
    var payload = document([], revision: 3);
    final repo = PublicHolidayRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(payload),
          200,
          headers: {"content-type": "application/json; charset=utf-8"},
        ),
      ),
    );
    await repo.refresh(force: true);
    payload = document([holiday()], revision: 2);
    expect(await repo.refresh(force: true), false);
    expect(repo.items, isEmpty);
    expect(repo.revision, 3);
    repo.dispose();
  });
  test('henüz yayımlanmamış cevap yayımlanmış cache verisini silmez', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PublicHolidayRepository.cacheKey,
      jsonEncode(document([], revision: 2)),
    );
    final repo = PublicHolidayRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'schemaVersion': 1,
            'published': false,
            'revision': 0,
            'items': [],
          }),
          200,
        ),
      ),
    );
    await repo.refresh(force: true);
    expect(repo.items, isEmpty);
    expect(repo.revision, 2);
    repo.dispose();
  });
  test('paralel ekran ve hatırlatıcı isteği tek HTTP çağrısı yapar', () async {
    final gate = Completer<void>();
    var requests = 0;
    final repo = PublicHolidayRepository(
      client: MockClient((_) async {
        requests++;
        await gate.future;
        return http.Response(
          jsonEncode(document([])),
          200,
          headers: {"content-type": "application/json; charset=utf-8"},
        );
      }),
    );
    final first = repo.refresh(force: true), second = repo.refresh(force: true);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(repo.hasPublishedData, true);
    repo.dispose();
  });
  test(
    'geçerli cache ile gereksiz otomatik istek yapılmaz; elle yenileme çalışır',
    () async {
      var requests = 0;
      final repo = PublicHolidayRepository(
        client: MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode(document([])),
            200,
            headers: {"content-type": "application/json; charset=utf-8"},
          );
        }),
      );
      await repo.refresh(force: true);
      await repo.refresh();
      expect(requests, 1);
      await repo.refresh(force: true);
      expect(requests, 2);
      repo.dispose();
    },
  );
  test(
    'liste değiştiğinde hatırlatıcı dinleyicisi boş yayın için de uyarılır',
    () async {
      var payload = document([holiday()]), changes = 0;
      final repo = PublicHolidayRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(payload),
            200,
            headers: {"content-type": "application/json; charset=utf-8"},
          ),
        ),
      );
      repo.addListener(() => changes++);
      await repo.refresh(force: true);
      payload = document([], revision: 2);
      await repo.refresh(force: true);
      await repo.refresh(force: true);
      expect(changes, 2);
      repo.dispose();
    },
  );
  test('yarım gün ve idari izin bilgileri kaybolmaz', () {
    final p = PublishedHolidayList.parse(
      document([
        {...holiday(), 'kind': 'idari', 'detail': 'Yarım gün (kamu)'},
      ]),
    );
    expect(p.items.single.kind, HolidayKind.idari);
    expect(p.items.single.detail, 'Yarım gün (kamu)');
  });
  test('aynı gün farklı kimlikli tatiller korunur', () {
    expect(
      PublishedHolidayList.parse(
        document([
          holiday(),
          {...holiday(id: 'second'), 'name': 'Başka tatil', 'kind': 'idari'},
        ]),
      ).items.length,
      2,
    );
  });
  test('tekrarlanan kimlik ve geçersiz tür reddedilir', () {
    expect(
      () => PublishedHolidayList.parse(document([holiday(), holiday()])),
      throwsFormatException,
    );
    expect(
      () => PublishedHolidayList.parse(
        document([
          {...holiday(), 'kind': 'other'},
        ]),
      ),
      throwsFormatException,
    );
  });
  test(
    'yayında yanlışlıkla bulunan pasif veya kaldırılan kayıt gösterilmez',
    () {
      expect(
        PublishedHolidayList.parse(
          document([
            holiday(active: false),
            {...holiday(id: 'removed'), 'removed': true},
          ]),
        ).items,
        isEmpty,
      );
    },
  );
  test('ters veya normalleştirilmiş geçersiz tarih reddedilir', () {
    expect(
      () =>
          PublishedHolidayList.parse(document([holiday(start: '2027-01-02')])),
      throwsFormatException,
    );
    expect(
      () => PublishedHolidayList.parse(
        document([holiday(start: '2027-02-29', end: '2027-03-01')]),
      ),
      throwsFormatException,
    );
  });

  test('çok günlük tatilde açıklama boşsa gün sayısı hesaplanır', () {
    final p = PublishedHolidayList.parse(
      document([holiday(start: '2027-03-09', end: '2027-03-11')]),
    );
    expect(p.items.single.durationLabel, '3 gün');
  });
}
