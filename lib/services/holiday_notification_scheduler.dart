import 'device_test_service.dart';
import 'app_notifications_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants/public_holidays_2026.dart';
import 'public_holiday_repository.dart';
import '../navigator_keys.dart';
import '../screens/holidays_screen.dart';
import '../navigation/rotalink_shell_routes.dart';
import 'announcement_notification_scheduler.dart';
import 'campaign_push_service.dart';

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

  static const prefKey = 'rotalink_holiday_reminders_enabled';

  static const settingTitle = 'Resmi tatil hatırlatması';

  static const settingDescription =
      'Her resmi tatilden 1 hafta önce, sabah 09:00\'da hatırlatma.';

  static const String _prefPendingNav =
      'rotalink_pending_open_holidays_from_notification';

  static const String _prefPendingRoute =
      'rotalink_pending_route_from_notification';

  static const int _idBase = 910_000;

  static const String _channelId = 'rotalink_holidays';

  static const String _channelName = 'Resmi tatiller';

  static const String _channelDescription =
      'Yaklaşan resmi tatil için 1 hafta kala hatırlatma';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static Future<void>? _scheduleFlight;
  static bool _rescheduleRequested = false;

  static void _onHolidayListChanged() {
    unawaited(
      scheduleUpcomingHolidayReminders().catchError((Object e) {
        debugPrint('Tatil hatırlatmaları yenilenemedi: $e');
      }),
    );
  }

  static Future<void> handleBackgroundTap(NotificationResponse details) async {
    if (details.payload?.startsWith(AppNotificationsService.payloadPrefix) ??
        false) {
      await AppNotificationsService.handleTap(details.payload!);
      return;
    }
    if (kDebugMode &&
        (details.payload?.startsWith(adminTestPayloadPrefix) ?? false)) {
      await DeviceTestService().localTap(
        details.payload!.substring(adminTestPayloadPrefix.length),
      );
      return;
    }
    if (details.payload == CampaignPushService.localPayload) {
      await CampaignPushService.markPendingOpenInPrefs();
      return;
    }
    final route = _announcementRoute(details.payload);
    if (route != null) {
      await _setPendingRoute(route);
      return;
    }
    if (details.payload != payloadOpenHolidays) return;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefPendingNav, true);
  }

  /// Duyuru bildirimi yükünden shell rotası; rota yoksa veya duyuru değilse null.
  static String? _announcementRoute(String? payload) {
    const prefix = AnnouncementNotificationScheduler.payloadPrefix;
    if (payload == null || !payload.startsWith(prefix)) return null;
    final route = payload.substring(prefix.length);
    return route.isEmpty ? null : route;
  }

  static Future<void> _setPendingRoute(String route) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefPendingRoute, route);
  }

  static Future<void> initialize() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));

    const androidInit = AndroidInitializationSettings('ic_stat_rotalink');
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

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'rotalink_admin_test',
        'Yönetici telefon testleri',
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        CampaignPushService.channelId,
        CampaignPushService.channelName,
        description: CampaignPushService.channelDescription,
        importance: Importance.high,
      ),
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = launch?.notificationResponse?.payload;
      if (payload?.startsWith(AppNotificationsService.payloadPrefix) ?? false) {
        await AppNotificationsService.handleTap(payload!);
      }
      if (kDebugMode &&
          (payload?.startsWith(adminTestPayloadPrefix) ?? false)) {
        await DeviceTestService.instance.localTap(
          payload!.substring(adminTestPayloadPrefix.length),
        );
      }
      final route = _announcementRoute(payload);
      if (payload == CampaignPushService.localPayload) {
        CampaignPushService.requestOpen();
      } else if (route != null) {
        await _setPendingRoute(route);
      } else if (payload == payloadOpenHolidays) {
        await _setPendingNavigationFlag();
      }
    }

    _initialized = true;
    PublicHolidayRepository.instance.addListener(_onHolidayListChanged);
    await PublicHolidayRepository.instance.loadCache();
    await scheduleUpcomingHolidayReminders();
  }

  /// Ön planda gelen yeni kampanya bildirimini gösterir (tıklanınca Kampanya sekmesi açılır).
  static Future<void> showCampaignNotification({
    required String title,
    required String body,
  }) async {
    if (!_initialized) await initialize();
    final android = AndroidNotificationDetails(
      CampaignPushService.channelId,
      CampaignPushService.channelName,
      channelDescription: CampaignPushService.channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_rotalink',
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await _plugin.show(
      _campaignNotificationId,
      title,
      body,
      NotificationDetails(android: android, iOS: ios),
      payload: CampaignPushService.localPayload,
    );
  }

  static const adminTestPayloadPrefix = 'admin_test:';
  static Future<void> showAdminTestNotification({
    required String title,
    required String body,
    required String deliveryId,
    Uint8List? picture,
  }) async {
    if (!kDebugMode) return;
    if (!_initialized) await initialize();
    final android = AndroidNotificationDetails(
      'rotalink_admin_test',
      'Yönetici telefon testleri',
      channelDescription:
          'Yalnızca eşleştirilmiş test telefonuna gönderilen bildirimler',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_rotalink',
      styleInformation: picture == null
          ? BigTextStyleInformation(body)
          : BigPictureStyleInformation(
              ByteArrayAndroidBitmap(picture),
              contentTitle: title,
              summaryText: body,
            ),
    );
    await _plugin.show(
      950000 + (deliveryId.hashCode & 1023),
      title,
      body,
      NotificationDetails(
        android: android,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: adminTestPayloadPrefix + deliveryId,
    );
  }

  static const int _campaignNotificationId = 940_000;

  static void _onForegroundNotificationResponse(NotificationResponse r) {
    if (r.payload?.startsWith(AppNotificationsService.payloadPrefix) ?? false) {
      unawaited(AppNotificationsService.handleTap(r.payload!));
      return;
    }
    if (kDebugMode &&
        (r.payload?.startsWith(adminTestPayloadPrefix) ?? false)) {
      unawaited(
        DeviceTestService.instance.localTap(
          r.payload!.substring(adminTestPayloadPrefix.length),
        ),
      );
      return;
    }
    if (r.payload == CampaignPushService.localPayload) {
      CampaignPushService.requestOpen();
      return;
    }
    final route = _announcementRoute(r.payload);
    if (route != null) {
      final shellNav = rotalinkShellBodyNavigatorKey.currentState;
      if (shellNav != null) {
        shellNav.pushNamed(route);
      } else {
        unawaited(_setPendingRoute(route));
      }
      return;
    }
    if (r.payload != payloadOpenHolidays) return;
    final shellNav = rotalinkShellBodyNavigatorKey.currentState;
    if (shellNav != null) {
      shellNav.pushNamed(RotalinkShellRoutes.holidays);
      return;
    }
    final ctx = rotalinkNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      Navigator.of(
        ctx,
      ).push(MaterialPageRoute<void>(builder: (_) => const HolidaysScreen()));
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

  /// Uygulama kapalıyken dokunulan duyuru bildiriminin açacağı shell rotası.
  static Future<String?> consumePendingRouteFromNotification() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final route = p.getString(_prefPendingRoute);
    if (route != null) await p.remove(_prefPendingRoute);
    return route;
  }

  /// İzin diyaloğunu UI hazır olduktan sonra göstermek için ayrı metot.
  /// [app.dart] içindeki post-frame callback'ten çağrılır.
  /// Açık reddedilirse `false` döner.
  static Future<bool> requestPermissions() async {
    var permitted = true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final granted = await android?.requestNotificationsPermission();
      if (granted == false) permitted = false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (granted == false) permitted = false;
    }
    return permitted;
  }

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(prefKey) ?? true;
  }

  /// Tercihi kaydeder. Kapatınca bekleyen tatil hatırlatmalarını siler;
  /// açınca yeniden planlar. İzin verilmezse `false` döner.
  static Future<bool> setEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(prefKey, enabled);
    if (!enabled) {
      await scheduleUpcomingHolidayReminders();
      return true;
    }
    if (!_initialized) await initialize();
    final permitted = await requestPermissions();
    await scheduleUpcomingHolidayReminders();
    return permitted;
  }

  static Future<void> _cancelHolidayReminders() async {
    if (!_initialized) return;
    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.id >= _idBase && notification.id < _idBase + 1000) {
        await _plugin.cancel(notification.id);
      }
    }
  }

  static Future<void> scheduleUpcomingHolidayReminders() {
    if (!_initialized) return Future.value();
    // Ana ekranın mevcut resume çağrısı da tatil verisini arka planda yeniler.
    unawaited(PublicHolidayRepository.instance.refresh());
    _rescheduleRequested = true;
    return _scheduleFlight ??= _drainHolidaySchedules().whenComplete(
      () => _scheduleFlight = null,
    );
  }

  static Future<void> _drainHolidaySchedules() async {
    while (_rescheduleRequested) {
      _rescheduleRequested = false;
      await _scheduleCurrentHolidayList();
    }
  }

  static Future<void> _scheduleCurrentHolidayList() async {
    await _cancelHolidayReminders();
    if (!await isEnabled()) return;
    final holidays = PublicHolidayRepository.instance.items;
    var scheduledCount = 0;
    final now = DateTime.now();
    for (var i = 0; i < holidays.length; i++) {
      final h = holidays[i];
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
      if (scheduledCount >= 48) break; // Diğer bildirimlere de yer bırakır.

      final when = tz.TZDateTime.from(atNine, tz.local);

      final isIdari = h.kind == HolidayKind.idari;
      final title = isIdari
          ? '«${h.name}» — 1 hafta kaldı'
          : '«${h.name}» — 1 hafta kaldı';
      const sourceLine = 'Rotalink uygulamasından hatırlatma';
      final body = isIdari
          ? 'Kamu idari izninize 7 gün kaldı. Tarih: ${h.dateLine}.\n'
                '$sourceLine — dokunarak uygulamayı açın.'
          : 'Resmi tatilinize 7 gün kaldı. Tatil: ${h.dateLine}.\n'
                '$sourceLine — dokunarak uygulamayı açın.';

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(
          body,
          summaryText: 'Rotalink',
        ),
        icon: 'ic_stat_rotalink',
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
        scheduledCount++;
      } catch (e, st) {
        debugPrint('Tatil bildirimi planlanamadı (${h.name}): $e\n$st');
      }
    }
  }
}
