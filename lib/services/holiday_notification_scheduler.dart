import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants/public_holidays_2026.dart';
import '../navigator_keys.dart';
import '../screens/holidays_screen.dart';

/// Arka planda bildirime tıklanınca (ayrı isolate); [pragma] zorunlu.
@pragma('vm:entry-point')
Future<void> rotalinkHolidayNotificationBackgroundTap(
  NotificationResponse details,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  await HolidayNotificationScheduler.handleBackgroundTap(details);
}

/// Yerel zamanlı hatırlatma: her resmi tatilden tam 7 gün önce (09:00, İstanbul).
class HolidayNotificationScheduler {
  HolidayNotificationScheduler._();

  static const String payloadOpenHolidays = 'open_holidays';

  static const String _prefPendingNav =
      'rotalink_pending_open_holidays_from_notification';

  static const int _idBase = 910_000;

  static const String _channelId = 'rotalink_holidays';

  static const String _channelName = 'Resmi tatiller';

  static const String _channelDescription =
      'Yaklaşan resmi tatil için 1 hafta kala hatırlatma';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> handleBackgroundTap(NotificationResponse details) async {
    if (details.payload != payloadOpenHolidays) return;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefPendingNav, true);
  }

  static Future<void> initialize() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onForegroundNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          rotalinkHolidayNotificationBackgroundTap,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload == payloadOpenHolidays) {
      await _setPendingNavigationFlag();
    }

    _initialized = true;

    await scheduleUpcomingHolidayReminders();
  }

  static void _onForegroundNotificationResponse(NotificationResponse r) {
    if (r.payload != payloadOpenHolidays) return;
    final ctx = rotalinkNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx).push(
        MaterialPageRoute<void>(builder: (_) => const HolidaysScreen()),
      );
      return;
    }
    unawaited(_setPendingNavigationFlag());
  }

  static Future<void> _setPendingNavigationFlag() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefPendingNav, true);
  }

  /// Ana ekran hazır olduğunda çağrılır: önce tercih bayrağı, sonra anlık [Navigator].
  static Future<bool> consumePendingOpenHolidaysNavigation() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final fromPrefs = p.getBool(_prefPendingNav) ?? false;
    if (fromPrefs) {
      await p.setBool(_prefPendingNav, false);
      return true;
    }
    return false;
  }

  /// İzin diyaloğunu UI hazır olduktan sonra göstermek için ayrı metot.
  /// [app.dart] içindeki post-frame callback'ten çağrılır.
  static Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (defaultTargetPlatform == TargetPlatform.android) {
      await android?.requestNotificationsPermission();
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  static Future<void> scheduleUpcomingHolidayReminders() async {
    for (var i = 0; i < kPublicHolidays2026.length; i++) {
      await _plugin.cancel(_idBase + i);
    }

    final now = DateTime.now();
    for (var i = 0; i < kPublicHolidays2026.length; i++) {
      final h = kPublicHolidays2026[i];
      final startDay = DateTime(h.start.year, h.start.month, h.start.day);
      final reminderDay = startDay.subtract(const Duration(days: 7));
      final atNine = DateTime(
        reminderDay.year,
        reminderDay.month,
        reminderDay.day,
        9,
        0,
      );
      if (!atNine.isAfter(now)) continue;

      final when = tz.TZDateTime.from(atNine, tz.local);

      final title = '«${h.name}» — 1 hafta kaldı';
      const sourceLine = 'Rotalink uygulamasından hatırlatma';
      final body =
          'Resmi tatilinize 7 gün kaldı. Tatil: ${h.dateLine}.\n'
          '$sourceLine — dokunarak uygulamayı açın.';

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body, summaryText: 'Rotalink'),
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        subtitle: sourceLine,
      );

      try {
        await _plugin.zonedSchedule(
          _idBase + i,
          title,
          body,
          when,
          NotificationDetails(android: androidDetails, iOS: iosDetails),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payloadOpenHolidays,
        );
      } catch (e, st) {
        debugPrint('Tatil bildirimi planlanamadı (${h.name}): $e\n$st');
      }
    }
  }
}
