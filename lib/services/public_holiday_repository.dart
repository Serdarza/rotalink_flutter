import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/public_holidays_2026.dart';

/// Yayımlanan TAM liste kullanılır; kaldırılanlar gömülü listeden geri eklenmez.
class PublishedHolidayList {
  const PublishedHolidayList(this.revision, this.items);
  final int revision;
  final List<PublicHoliday> items;
  static PublishedHolidayList parse(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['schemaVersion'] != 1 ||
        value['published'] != true ||
        value['revision'] is! int ||
        (value['revision'] as int) < 1 ||
        value['items'] is! List) {
      throw const FormatException('Yayımlanmış tatil listesi gerekli.');
    }
    final records = value['items'] as List;
    if (records.length > 200) {
      throw const FormatException('Tatil listesi çok büyük.');
    }
    final ids = <String>{}, items = <PublicHoliday>[];
    for (final raw in records) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Geçersiz tatil.');
      }
      final id = raw['id'];
      if (id is! String ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id) ||
          !ids.add(id)) {
        throw const FormatException('Geçersiz veya tekrarlanan tatil kimliği.');
      }
      final name = raw['name'], detail = raw['detail'];
      if (name is! String ||
          name.trim().isEmpty ||
          name.length > 180 ||
          detail is! String ||
          detail.length > 300 ||
          raw['active'] is! bool ||
          (raw.containsKey('removed') && raw['removed'] is! bool)) {
        throw const FormatException('Geçersiz tatil alanları.');
      }
      final start = _date(raw['startDate']), end = _date(raw['endDate']);
      final days = DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
      if (days < 0 || days > 366) {
        throw const FormatException('Geçersiz tarih aralığı.');
      }
      final kind = switch (raw['kind']) {
        'milli' => HolidayKind.milli,
        'dini' => HolidayKind.dini,
        'idari' => HolidayKind.idari,
        _ => throw const FormatException('Geçersiz tatil türü.'),
      };
      if (raw['active'] != true || raw['removed'] == true) continue;
      items.add(
        PublicHoliday(
          name: name.trim(),
          dateLine: _range(start, end),
          detail: detail.trim().isEmpty && days > 0
              ? '${days + 1} gün'
              : detail.trim(),
          start: start,
          endInclusive: end,
          kind: kind,
          year: start.year,
        ),
      );
    }
    items.sort((a, b) => a.start.compareTo(b.start));
    return PublishedHolidayList(
      value['revision'] as int,
      List.unmodifiable(items),
    );
  }

  static DateTime _date(Object? raw) {
    if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
      throw const FormatException('Geçersiz tatil tarihi.');
    }
    final y = int.parse(raw.substring(0, 4)),
        m = int.parse(raw.substring(5, 7)),
        d = int.parse(raw.substring(8, 10));
    final result = DateTime(y, m, d);
    if (y < 2000 ||
        y > 2100 ||
        result.year != y ||
        result.month != m ||
        result.day != d) {
      throw const FormatException('Geçersiz tatil tarihi.');
    }
    return result;
  }

  static const _months = [
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
  static const _weekdays = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  static String _day(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${_weekdays[d.weekday - 1]}';
  static String _range(DateTime a, DateTime b) {
    if (a == b) return _day(a);
    if (a.month == b.month && a.year == b.year) {
      return '${a.day} – ${b.day} ${_months[a.month - 1]} ${_weekdays[a.weekday - 1]} – ${_weekdays[b.weekday - 1]}';
    }
    return '${_day(a)} – ${_day(b)}';
  }
}

class PublicHolidayRepository extends ChangeNotifier {
  PublicHolidayRepository({
    http.Client? client,
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _preferences = preferences ?? SharedPreferences.getInstance,
       _clock = clock ?? DateTime.now;
  static final instance = PublicHolidayRepository();
  static final endpoint = Uri.https('admin.rotalink.tr', '/public/holidays');
  static const cacheKey = 'rotalink_public_holidays_snapshot_v1',
      _fetchKey = 'rotalink_public_holidays_fetch_v1';
  final http.Client _client;
  final bool _ownsClient;
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _clock;
  List<PublicHoliday> _items = List.unmodifiable(kPublicHolidays);
  List<PublicHoliday> get items => _items;
  int get revision => _revision;
  bool get hasPublishedData => _revision > 0;
  int _revision = 0, _lastFetch = 0, _lastAttempt = 0;
  bool _loaded = false, _disposed = false;
  Future<void>? _cacheFlight;
  Future<bool>? _flight;
  Future<void> loadCache() {
    if (_loaded) return Future.value();
    return _cacheFlight ??= _readCache().whenComplete(
      () => _cacheFlight = null,
    );
  }

  Future<void> _readCache() async {
    try {
      final prefs = await _preferences(), raw = prefs.getString(cacheKey);
      if (raw != null) _apply(PublishedHolidayList.parse(jsonDecode(raw)));
      _lastFetch = prefs.getInt(_fetchKey) ?? 0;
    } catch (_) {
      /* Bozuk cache, son geçerli belleği / gömülü listeyi bozmaz. */
    } finally {
      _loaded = true;
    }
  }

  Future<bool> refresh({bool force = false}) =>
      _flight ??= _refresh(force).whenComplete(() => _flight = null);
  Future<bool> _refresh(bool force) async {
    await loadCache();
    final now = _clock().millisecondsSinceEpoch;
    if (!force &&
        ((now - _lastFetch >= 0 &&
                now - _lastFetch < const Duration(minutes: 5).inMilliseconds) ||
            (now - _lastAttempt >= 0 &&
                now - _lastAttempt <
                    const Duration(seconds: 30).inMilliseconds))) {
      return false;
    }
    _lastAttempt = now;
    try {
      final response = await _client
          .send(http.Request('GET', endpoint))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > 1024 * 1024) {
        await response.stream.listen(null).cancel();
        return false;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 5),
      )) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          throw const FormatException('Liste boyutu aşıldı.');
        }
        bytes.addAll(chunk);
      }
      final raw = utf8.decode(bytes),
          parsed = PublishedHolidayList.parse(jsonDecode(raw));
      if (_disposed || parsed.revision < _revision) return false;
      final prefs = await _preferences();
      await prefs.setString(cacheKey, raw);
      await prefs.setInt(_fetchKey, now);
      _lastFetch = now;
      return _apply(parsed);
    } catch (_) {
      return false;
    }
  }

  bool _apply(PublishedHolidayList value) {
    if (_disposed || value.revision <= _revision) return false;
    _revision = value.revision;
    _items = value.items;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
