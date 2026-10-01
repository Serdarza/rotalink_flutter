import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants/github_bildirim_config.dart';
import '../navigation/rotalink_shell_routes.dart';
import 'holiday_notification_scheduler.dart';

/// `bildirimler.json` içindeki bir mesajın telefonda zamanlanacak hâli.
@immutable
class PlannedAnnouncement {
  const PlannedAnnouncement({
    required this.when,
    required this.title,
    required this.body,
    this.route,
  });

  /// İstanbul duvar saati.
  final DateTime when;
  final String title;
  final String body;

  /// Bildirime dokununca açılacak shell rotası; yoksa uygulama açılır.
  final String? route;
}

/// GitHub'daki `bildirimler.json` mesajlarını indirip yerel bildirim olarak
/// zamanlar. Sunucu gerekmez: telefon bildirimi belirtilen saatte kendisi
/// gösterir. Yeni mesajlar uygulama açılınca veya arka plan görevinde alınır.
abstract final class AnnouncementNotificationScheduler {
  static const payloadPrefix = 'announce:';

  /// Mesajda `saat` yoksa ve dosyada genel `saat` yoksa.
  static const defaultHour = 21;

  /// Bildirimler bu saat aralığının dışına taşmaz.
  static const earliestHour = 10;
  static const latestHour = 21;

  /// iOS en fazla 64 bekleyen bildirime izin verir; tatil hatırlatmalarıyla
  /// paylaşıldığı için az tutulur.
  static const maxScheduled = 8;
  static const horizon = Duration(days: 70);

  static const screenRoutes = <String, String>{
    'kampanyalar': RotalinkShellRoutes.discover,
    'tatiller': RotalinkShellRoutes.holidays,
    'pro': RotalinkShellRoutes.pro,
  };

  static const _idBase = 930_000;
  static const _kEnabled = 'rotalink_announcements_enabled';
  static const _kCache = 'rotalink_announcements_cache';
  static const _kLastFetchMs = 'rotalink_announcements_last_fetch_ms';
  static const _resumeFetchInterval = Duration(hours: 6);
  static const _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';

  static const _channelId = 'rotalink_announcements';
  static const _channelName = 'Duyurular';
  static const _channelDescription = 'Haftalık tatil, tesis ve kampanya önerileri';

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabled) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, enabled);
    await sync(forceFetch: enabled);
  }

  /// [forceFetch] false ise ağdan en fazla 6 saatte bir indirilir; arada
  /// önbellekteki dosyayla yeniden zamanlanır.
  static Future<void> sync({bool background = false, bool forceFetch = true}) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final plugin = await _plugin(background: background);

    if (!(prefs.getBool(_kEnabled) ?? true)) {
      await _cancelAll(plugin);
      return;
    }

    var raw = prefs.getString(_kCache);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastMs = prefs.getInt(_kLastFetchMs) ?? 0;
    if (forceFetch || raw == null || nowMs - lastMs > _resumeFetchInterval.inMilliseconds) {
      final fetched = await _fetch();
      if (fetched != null) {
        raw = fetched;
        await prefs.setString(_kCache, fetched);
        await prefs.setInt(_kLastFetchMs, nowMs);
      }
    }
    if (raw == null) return;

    final List<PlannedAnnouncement> plan;
    try {
      final n = tz.TZDateTime.now(tz.local);
      plan = planFrom(jsonDecode(raw), DateTime(n.year, n.month, n.day, n.hour, n.minute));
    } catch (e) {
      debugPrint('[Announcements] bildirimler.json okunamadı: $e');
      return;
    }

    await _cancelAll(plugin);
    for (var i = 0; i < plan.length; i++) {
      await _schedule(plugin, _idBase + i, plan[i]);
    }
  }

  /// Dosyadan gelecek [horizon] içindeki mesajları seçer: saat 10:00–21:00
  /// aralığına çekilir, aynı haftaya düşen ikinci mesaj atlanır.
  static List<PlannedAnnouncement> planFrom(dynamic root, DateTime now) {
    if (root is! Map) return const [];
    final list = root['mesajlar'];
    if (list is! List) return const [];
    final fileTime = _parseTime(root['saat']);

    final items = <(int, PlannedAnnouncement)>[];
    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      if (m is! Map || m['aktif'] == false) continue;
      final title = _text(m['baslik']);
      final body = _text(m['metin']);
      final date = _parseDate(m['tarih']);
      if (title == null || body == null || date == null) continue;
      final t = _clampTime(_parseTime(m['saat']) ?? fileTime ?? (hour: defaultHour, minute: 0));
      final when = DateTime(date.year, date.month, date.day, t.hour, t.minute);
      if (!when.isAfter(now) || when.isAfter(now.add(horizon))) continue;
      items.add((
        i,
        PlannedAnnouncement(
          when: when,
          title: title,
          body: body,
          route: screenRoutes[_text(m['ekran'])?.toLowerCase()],
        ),
      ));
    }
    items.sort((a, b) {
      final c = a.$2.when.compareTo(b.$2.when);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });

    final weeks = <DateTime>{};
    final out = <PlannedAnnouncement>[];
    for (final (_, a) in items) {
      if (!weeks.add(_weekStart(a.when))) continue;
      out.add(a);
      if (out.length == maxScheduled) break;
    }
    return out;
  }

  static Future<FlutterLocalNotificationsPlugin> _plugin({required bool background}) async {
    final plugin = FlutterLocalNotificationsPlugin();
    if (!background) {
      await HolidayNotificationScheduler.initialize();
      return plugin;
    }
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    return plugin;
  }

  static Future<String?> _fetch() async {
    try {
      final res = await http
          .get(GithubBildirimConfig.uri, headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final body = utf8.decode(res.bodyBytes).trim();
      if (body.isEmpty) return null;
      jsonDecode(body);
      return body;
    } catch (e) {
      debugPrint('[Announcements] indirilemedi: $e');
      return null;
    }
  }

  static Future<void> _cancelAll(FlutterLocalNotificationsPlugin plugin) async {
    for (var i = 0; i < maxScheduled; i++) {
      await plugin.cancel(_idBase + i);
    }
  }

  static Future<void> _schedule(
    FlutterLocalNotificationsPlugin plugin,
    int id,
    PlannedAnnouncement a,
  ) async {
    final when = tz.TZDateTime(
      tz.local,
      a.when.year,
      a.when.month,
      a.when.day,
      a.when.hour,
      a.when.minute,
    );
    try {
      await plugin.zonedSchedule(
        id,
        a.title,
        a.body,
        when,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            styleInformation: BigTextStyleInformation(a.body, summaryText: 'Rotalink'),
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: '$payloadPrefix${a.route ?? ''}',
      );
    } catch (e) {
      debugPrint('[Announcements] zamanlanamadı (${a.title}): $e');
    }
  }

  static String? _text(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static DateTime? _parseDate(dynamic v) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(_text(v) ?? '');
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    final date = DateTime(y, mo, d);
    return date.month == mo && date.day == d ? date : null;
  }

  static ({int hour, int minute})? _parseTime(dynamic v) {
    final m = RegExp(r'^(\d{1,2})[:.](\d{2})$').firstMatch(_text(v) ?? '');
    if (m == null) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    if (h > 23 || min > 59) return null;
    return (hour: h, minute: min);
  }

  static ({int hour, int minute}) _clampTime(({int hour, int minute}) t) {
    if (t.hour < earliestHour) return (hour: earliestHour, minute: 0);
    if (t.hour > latestHour || (t.hour == latestHour && t.minute > 0)) {
      return (hour: latestHour, minute: 0);
    }
    return t;
  }

  static DateTime _weekStart(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
}
