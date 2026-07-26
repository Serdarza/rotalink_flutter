import 'package:flutter/foundation.dart';

/// Milli bayram, dini bayram veya kamu idari izin.
enum HolidayKind {
  milli,
  dini,
  idari,
}

@immutable
class PublicHoliday {
  const PublicHoliday({
    required this.name,
    required this.dateLine,
    required this.detail,
    required this.start,
    required this.endInclusive,
    required this.kind,
    required this.year,
  });

  final String name;
  final String dateLine;

  /// Boş, `Yarım gün`, `3 gün`, `İdari izin` vb.
  final String detail;

  /// Tatilin / iznin başlangıç günü (yerel, saat 00:00).
  final DateTime start;

  /// Son gün (dahil).
  final DateTime endInclusive;

  final HolidayKind kind;
  final int year;

  String get durationLabel {
    if (detail == 'Yarım gün') return 'Yarım gün';
    if (detail.isNotEmpty) return detail;
    return '1 gün';
  }

  String get kindLabel {
    switch (kind) {
      case HolidayKind.milli:
        return 'Milli';
      case HolidayKind.dini:
        return 'Dini';
      case HolidayKind.idari:
        return 'İdari izin';
    }
  }
}

/// Geriye uyumluluk — eski tip adı.
typedef PublicHoliday2026 = PublicHoliday;

String _weekdayTr(DateTime d) {
  const names = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  return names[d.weekday - 1];
}

String _monthTr(int month) {
  const names = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];
  return names[month - 1];
}

String _dayLine(DateTime d) =>
    '${d.day} ${_monthTr(d.month)} ${_weekdayTr(d)}';

String _rangeLine(DateTime a, DateTime b) {
  if (a.year == b.year && a.month == b.month && a.day == b.day) {
    return _dayLine(a);
  }
  if (a.month == b.month) {
    return '${a.day} – ${b.day} ${_monthTr(a.month)} ${_weekdayTr(a)} – ${_weekdayTr(b)}';
  }
  return '${_dayLine(a)} – ${_dayLine(b)}';
}

PublicHoliday _h({
  required String name,
  required DateTime start,
  DateTime? endInclusive,
  String detail = '',
  required HolidayKind kind,
}) {
  final end = endInclusive ?? start;
  return PublicHoliday(
    name: name,
    dateLine: _rangeLine(start, end),
    detail: detail,
    start: start,
    endInclusive: end,
    kind: kind,
    year: start.year,
  );
}

/// 2026 resmi tatiller + açıklanan kamu idari izinleri (Türkiye).
///
/// Dini bayram tarihleri Diyanet takvimine göredir; idari izinler
/// Cumhurbaşkanlığı açıklamalarına göre eklenir (yalnızca kamu personeli).
final List<PublicHoliday> kPublicHolidays2026 = [
  _h(
    name: 'Yılbaşı',
    start: DateTime(2026, 1, 1),
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Ramazan Bayramı Arife',
    start: DateTime(2026, 3, 19),
    detail: 'Yarım gün',
    kind: HolidayKind.dini,
  ),
  _h(
    name: 'Ramazan Bayramı',
    start: DateTime(2026, 3, 20),
    endInclusive: DateTime(2026, 3, 22),
    detail: '3 gün',
    kind: HolidayKind.dini,
  ),
  _h(
    name: 'Ulusal Egemenlik ve Çocuk Bayramı',
    start: DateTime(2026, 4, 23),
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Emek ve Dayanışma Günü',
    start: DateTime(2026, 5, 1),
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Atatürk\'ü Anma, Gençlik ve Spor Bayramı',
    start: DateTime(2026, 5, 19),
    kind: HolidayKind.milli,
  ),
  // Cumhurbaskanligi: Kurban resmi tatiline +1,5 gün idari izin
  // (25 Mayıs tam gün + 26 Mayıs öğleden önce) → kamu için 9 günlük tatil.
  _h(
    name: 'Kurban Bayramı öncesi idari izin',
    start: DateTime(2026, 5, 25),
    detail: 'İdari izin (kamu)',
    kind: HolidayKind.idari,
  ),
  _h(
    name: 'Kurban Bayramı Arife',
    start: DateTime(2026, 5, 26),
    detail: 'Yarım gün (kamu: tam gün)',
    kind: HolidayKind.dini,
  ),
  _h(
    name: 'Kurban Bayramı',
    start: DateTime(2026, 5, 27),
    endInclusive: DateTime(2026, 5, 30),
    detail: '4 gün',
    kind: HolidayKind.dini,
  ),
  _h(
    name: 'Demokrasi ve Milli Birlik Günü',
    start: DateTime(2026, 7, 15),
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Zafer Bayramı',
    start: DateTime(2026, 8, 30),
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Cumhuriyet Bayramı Arife',
    start: DateTime(2026, 10, 28),
    detail: 'Yarım gün',
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Cumhuriyet Bayramı',
    start: DateTime(2026, 10, 29),
    kind: HolidayKind.milli,
  ),
];

/// 2027 resmi tatiller (Diyanet / 2429 sayılı Kanun).
/// İdari izinler açıklandıkça bu listeye eklenir.
final List<PublicHoliday> kPublicHolidays2027 = [
  _h(
    name: 'Yılbaşı',
    start: DateTime(2027, 1, 1),
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Ramazan Bayramı Arife',
    start: DateTime(2027, 3, 8),
    detail: 'Yarım gün',
    kind: HolidayKind.dini,
  ),
  _h(
    name: 'Ramazan Bayramı',
    start: DateTime(2027, 3, 9),
    endInclusive: DateTime(2027, 3, 11),
    detail: '3 gün',
    kind: HolidayKind.dini,
  ),
  _h(
    name: 'Ulusal Egemenlik ve Çocuk Bayramı',
    start: DateTime(2027, 4, 23),
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Emek ve Dayanışma Günü',
    start: DateTime(2027, 5, 1),
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Kurban Bayramı Arife',
    start: DateTime(2027, 5, 15),
    detail: 'Yarım gün',
    kind: HolidayKind.dini,
  ),
  _h(
    name: 'Kurban Bayramı',
    start: DateTime(2027, 5, 16),
    endInclusive: DateTime(2027, 5, 19),
    detail: '4 gün',
    kind: HolidayKind.dini,
  ),
  _h(
    name: 'Atatürk\'ü Anma, Gençlik ve Spor Bayramı',
    start: DateTime(2027, 5, 19),
    detail: 'Kurban Bayramı 4. günü ile aynı gün',
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Demokrasi ve Milli Birlik Günü',
    start: DateTime(2027, 7, 15),
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Zafer Bayramı',
    start: DateTime(2027, 8, 30),
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Cumhuriyet Bayramı Arife',
    start: DateTime(2027, 10, 28),
    detail: 'Yarım gün',
    kind: HolidayKind.milli,
  ),
  _h(
    name: 'Cumhuriyet Bayramı',
    start: DateTime(2027, 10, 29),
    kind: HolidayKind.milli,
  ),
];

/// 2026 + 2027 birleşik, tarihe göre sıralı liste.
final List<PublicHoliday> kPublicHolidays = [
  ...kPublicHolidays2026,
  ...kPublicHolidays2027,
];
