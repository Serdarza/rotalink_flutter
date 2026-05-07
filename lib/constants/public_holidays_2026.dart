import 'package:flutter/foundation.dart';

/// Kotlin [ResmiTatil.kt] `resmiTatiller2026` — geri sayım için yerel tarih aralığı.
@immutable
class PublicHoliday2026 {
  const PublicHoliday2026({
    required this.name,
    required this.dateLine,
    required this.detail,
    required this.start,
    required this.endInclusive,
  });

  final String name;
  final String dateLine;

  /// Boş, `Yarım gün`, `3 gün` vb. (Kotlin `detay`).
  final String detail;

  /// Tatilin başlangıç günü (yerel, saat 00:00).
  final DateTime start;

  /// Tatilin son günü (dahil).
  final DateTime endInclusive;

  /// Kartta gösterilecek süre metni.
  String get durationLabel {
    if (detail == 'Yarım gün') return 'Yarım gün';
    if (detail.isNotEmpty) return detail;
    return '1 gün';
  }
}

/// 2026 resmi tatiller (Türkiye, yerel takvim).
final List<PublicHoliday2026> kPublicHolidays2026 = [
  PublicHoliday2026(
    name: 'Yılbaşı',
    dateLine: '1 Ocak Perşembe',
    detail: '',
    start: DateTime(2026, 1, 1),
    endInclusive: DateTime(2026, 1, 1),
  ),
  PublicHoliday2026(
    name: 'Ramazan Bayramı Arife',
    dateLine: '19 Mart Perşembe',
    detail: 'Yarım gün',
    start: DateTime(2026, 3, 19),
    endInclusive: DateTime(2026, 3, 19),
  ),
  PublicHoliday2026(
    name: 'Ramazan Bayramı',
    dateLine: '20 – 22 Mart Cuma – Pazar',
    detail: '3 gün',
    start: DateTime(2026, 3, 20),
    endInclusive: DateTime(2026, 3, 22),
  ),
  PublicHoliday2026(
    name: 'Ulusal Egemenlik ve Çocuk Bayramı',
    dateLine: '23 Nisan Perşembe',
    detail: '',
    start: DateTime(2026, 4, 23),
    endInclusive: DateTime(2026, 4, 23),
  ),
  PublicHoliday2026(
    name: 'Emek ve Dayanışma Günü',
    dateLine: '1 Mayıs Cuma',
    detail: '',
    start: DateTime(2026, 5, 1),
    endInclusive: DateTime(2026, 5, 1),
  ),
  PublicHoliday2026(
    name: 'Atatürk\'ü Anma, Gençlik ve Spor Bayramı',
    dateLine: '19 Mayıs Salı',
    detail: '',
    start: DateTime(2026, 5, 19),
    endInclusive: DateTime(2026, 5, 19),
  ),
  PublicHoliday2026(
    name: 'Kurban Bayramı Arife',
    dateLine: '26 Mayıs Salı',
    detail: 'Yarım gün',
    start: DateTime(2026, 5, 26),
    endInclusive: DateTime(2026, 5, 26),
  ),
  PublicHoliday2026(
    name: 'Kurban Bayramı',
    dateLine: '27 – 30 Mayıs Çarşamba – Cumartesi',
    detail: '4 gün',
    start: DateTime(2026, 5, 27),
    endInclusive: DateTime(2026, 5, 30),
  ),
  PublicHoliday2026(
    name: 'Demokrasi ve Milli Birlik Günü',
    dateLine: '15 Temmuz Çarşamba',
    detail: '',
    start: DateTime(2026, 7, 15),
    endInclusive: DateTime(2026, 7, 15),
  ),
  PublicHoliday2026(
    name: 'Zafer Bayramı',
    dateLine: '30 Ağustos Pazar',
    detail: '',
    start: DateTime(2026, 8, 30),
    endInclusive: DateTime(2026, 8, 30),
  ),
  PublicHoliday2026(
    name: 'Cumhuriyet Bayramı Arife',
    dateLine: '28 Ekim Çarşamba',
    detail: 'Yarım gün',
    start: DateTime(2026, 10, 28),
    endInclusive: DateTime(2026, 10, 28),
  ),
  PublicHoliday2026(
    name: 'Cumhuriyet Bayramı',
    dateLine: '29 Ekim Perşembe',
    detail: '',
    start: DateTime(2026, 10, 29),
    endInclusive: DateTime(2026, 10, 29),
  ),
];
