import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/navigation/rotalink_shell_routes.dart';
import 'package:rotalink_flutter/services/announcement_notification_scheduler.dart';

void main() {
  // Perşembe 1 Ekim 2026, 12:00
  final now = DateTime(2026, 10, 1, 12);

  Map<String, dynamic> msg(String tarih, {String? saat, String? ekran, bool? aktif}) => {
        'tarih': tarih,
        'baslik': 'Başlık $tarih',
        'metin': 'Metin $tarih',
        'saat': ?saat,
        'ekran': ?ekran,
        'aktif': ?aktif,
      };

  List<PlannedAnnouncement> plan(List<Map<String, dynamic>> mesajlar, {String? saat}) =>
      AnnouncementNotificationScheduler.planFrom(
        {'saat': ?saat, 'mesajlar': mesajlar},
        now,
      );

  test('varsayılan saat 21:00, dosya saati uygulanır', () {
    expect(plan([msg('2026-10-08')]).single.when, DateTime(2026, 10, 8, 21));
    expect(plan([msg('2026-10-08')], saat: '20:30').single.when, DateTime(2026, 10, 8, 20, 30));
    expect(plan([msg('2026-10-08', saat: '19.15')], saat: '20:30').single.when,
        DateTime(2026, 10, 8, 19, 15));
  });

  test('saat 10:00–21:00 aralığına çekilir', () {
    expect(plan([msg('2026-10-08', saat: '23:30')]).single.when, DateTime(2026, 10, 8, 21));
    expect(plan([msg('2026-10-08', saat: '21:01')]).single.when, DateTime(2026, 10, 8, 21));
    expect(plan([msg('2026-10-08', saat: '07:00')]).single.when, DateTime(2026, 10, 8, 10));
  });

  test('aynı haftada yalnızca ilk mesaj', () {
    final p = plan([
      msg('2026-10-09'),
      msg('2026-10-08'),
      msg('2026-10-12'),
    ]);
    expect(p.map((a) => a.when.day), [8, 12]);
  });

  test('geçmiş, ufuk dışı, hatalı ve pasif mesajlar atlanır', () {
    final p = plan([
      msg('2026-09-24'),
      msg('2026-10-01', saat: '11:00'),
      msg('2027-03-04'),
      msg('2026-02-30'),
      msg('08.10.2026'),
      {'tarih': '2026-10-15', 'baslik': ' ', 'metin': 'x'},
      msg('2026-10-22', aktif: false),
      msg('2026-10-29'),
    ]);
    expect(p.map((a) => a.when.day), [29]);
  });

  test('ekran rotaya çevrilir, bilinmeyen ekran rotasız', () {
    final p = plan([
      msg('2026-10-08', ekran: 'Kampanyalar'),
      msg('2026-10-15', ekran: 'tatiller'),
      msg('2026-10-22', ekran: 'https://evil.example'),
    ]);
    expect(p.map((a) => a.route), [
      RotalinkShellRoutes.discover,
      RotalinkShellRoutes.holidays,
      null,
    ]);
  });

  test('en fazla maxScheduled mesaj', () {
    final mesajlar = [
      for (var i = 0; i < 10; i++)
        msg(DateTime(2026, 10, 2).add(Duration(days: 7 * i)).toIso8601String().substring(0, 10)),
    ];
    expect(plan(mesajlar).length, AnnouncementNotificationScheduler.maxScheduled);
  });

  test('bozuk kök boş liste döner', () {
    expect(AnnouncementNotificationScheduler.planFrom([], now), isEmpty);
    expect(AnnouncementNotificationScheduler.planFrom({'mesajlar': 'x'}, now), isEmpty);
  });
}
