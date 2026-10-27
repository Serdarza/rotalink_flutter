import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/admin_popup.dart';
import 'device_test_service.dart';
import 'holiday_notification_scheduler.dart';

@pragma('vm:entry-point')
Future<void> rotalinkBackgroundNotifications(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    if (kDebugMode && message.data['type'] == 'rotalink_admin_test') {
      await DeviceTestService().message(message.data);
    }
    // Public Android notifications are displayed once by the native service.
  } catch (_) {}
}

/// Normal APK notifications. No administrator pairing or private server key.
abstract final class AppNotificationsService {
  static const topic = 'rotalink_admin_android_v2';
  static const prefKey = 'rotalink_admin_notifications_enabled';
  static const payloadPrefix = 'admin_push:';
  static const _pendingKey = 'rotalink_admin_push_pending_v1';
  static const _native = MethodChannel('rotalink/admin_notification_layout');
  static final openRequests = ValueNotifier<int>(0);
  static Map<String, String>? pendingTarget;
  static bool _started = false;
  static Future<void>? _syncFlight;
  static bool _syncRequested = false;

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialize() async {
    if (!_android || _started) return;
    _started = true;
    FirebaseMessaging.onBackgroundMessage(rotalinkBackgroundNotifications);
    FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => unawaited(syncSubscription()),
    );
    await loadPending();
    await syncSubscription();
  }

  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(prefKey) ?? true;

  static Future<bool> setEnabled(bool enabled) async {
    await (await SharedPreferences.getInstance()).setBool(prefKey, enabled);
    if (!enabled && _android) {
      try {
        await _native.invokeMethod<int>('public', {'enabled': false});
      } catch (_) {}
    }
    final allowed =
        !enabled || await HolidayNotificationScheduler.requestPermissions();
    await syncSubscription();
    return allowed;
  }

  static Future<void> syncSubscription() {
    _syncRequested = true;
    return _syncFlight ??= _syncLatest().whenComplete(() => _syncFlight = null);
  }

  static Future<void> _syncLatest() async {
    do {
      _syncRequested = false;
      await _sync();
    } while (_syncRequested);
  }

  static Future<void> _sync() async {
    if (!_android) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      final allowed =
          await isEnabled() &&
          settings.authorizationStatus == AuthorizationStatus.authorized;
      final renderer = await _native.invokeMethod<int>('public', {
        'enabled': allowed,
      });
      if (renderer != 2) return;
      if (allowed) {
        await FirebaseMessaging.instance.setAutoInitEnabled(true);
        await FirebaseMessaging.instance
            .subscribeToTopic(topic)
            .timeout(const Duration(seconds: 12));
        await _native.invokeMethod<void>('subscriptionStatus', {'ready': true});
      } else {
        await FirebaseMessaging.instance
            .unsubscribeFromTopic(topic)
            .timeout(const Duration(seconds: 12));
        await _native.invokeMethod<void>('subscriptionStatus', {'ready': false});
      }
    } catch (_) {
      // Retry on app resume or when the user changes their preference.
    }
  }

  static Map<String, String>? parseTarget(Object? value) {
    if (value is! Map ||
        value['type'] != 'rotalink_admin' ||
        value['notificationRenderer'] != '2') {
      return null;
    }
    final id = value['notificationId'],
        route = value['route'],
        link = value['link'] ?? '';
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{16,80}$').hasMatch(id) ||
        route is! String ||
        !AdminPopup.routes.contains(route) ||
        link is! String ||
        link.length > 1000) {
      return null;
    }
    if (link.isNotEmpty) {
      final uri = Uri.tryParse(link);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        return null;
      }
    } else if (route == 'external') {
      return null;
    }
    return {'notificationId': id, 'route': route, 'link': link};
  }

  static Future<void> handleTap(String payload) async {
    if (!payload.startsWith(payloadPrefix)) return;
    try {
      final target = parseTarget(
        jsonDecode(payload.substring(payloadPrefix.length)),
      );
      if (target == null) return;
      await (await SharedPreferences.getInstance()).setString(
        _pendingKey,
        jsonEncode(target),
      );
      pendingTarget = target;
      openRequests.value++;
    } catch (_) {}
  }

  static Future<void> loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_pendingKey);
    if (raw == null) return;
    try {
      final saved = jsonDecode(raw);
      final target = parseTarget({
        ...Map<String, dynamic>.from(saved),
        'type': 'rotalink_admin',
        'notificationRenderer': '2',
      });
      if (target != null) pendingTarget = target;
    } catch (_) {}
  }

  static Future<void> consumePending() async {
    pendingTarget = null;
    await (await SharedPreferences.getInstance()).remove(_pendingKey);
  }
}
