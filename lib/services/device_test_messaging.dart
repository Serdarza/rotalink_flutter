import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'device_test_service.dart';

typedef TestForegroundNotification =
    Future<void> Function({
      required String title,
      required String body,
      required String deliveryId,
      Uint8List? picture,
    });
@pragma('vm:entry-point')
Future<void> rotalinkDeviceTestBackground(RemoteMessage message) async {
  if (!kDebugMode) return;
  try {
    await Firebase.initializeApp();
    await DeviceTestService().message(message.data);
  } catch (_) {}
}

abstract final class DeviceTestMessaging {
  static bool _started = false;
  static TestForegroundNotification? _foreground;
  static Future<void> initialize(TestForegroundNotification foreground) async {
    if (!kDebugMode || kIsWeb || _started) return;
    _started = true;
    _foreground = foreground;
    FirebaseMessaging.onMessage.listen((message) {
      unawaited(_received(message));
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(DeviceTestService.instance.message(message.data, opened: true));
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(
        DeviceTestService.instance.updateFcm(token).catchError((Object _) {}),
      );
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      await DeviceTestService.instance.message(initial.data, opened: true);
    }
    await DeviceTestService.instance.load();
    if (DeviceTestService.instance.paired) {
      try {
        final t = await token();
        if (t != null) await DeviceTestService.instance.updateFcm(t);
      } catch (_) {}
    }
  }

  static Future<String?> token() async {
    if (!kDebugMode || kIsWeb) return null;
    if (Firebase.apps.isEmpty) {
      await _step('firebase', () => Firebase.initializeApp());
    }
    await _step(
      'auto-init',
      () => FirebaseMessaging.instance.setAutoInitEnabled(true),
    );
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await _step('apns', () => FirebaseMessaging.instance.getAPNSToken()) ==
            null) {
      return null;
    }
    return _step(
      'token',
      () => FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 12),
      ),
    );
  }

  // Only fixed diagnostic codes are shown. Native error messages can contain
  // identifiers, so never display or log the original exception.
  static String diagnosticCode(Object error) {
    if (error is MissingPluginException) return 'PLUGIN_MISSING';
    if (error is TimeoutException) return 'TIMEOUT';
    final String detail;
    if (error is FirebaseException) {
      detail = '${error.code} ${error.message ?? ''}';
    } else if (error is PlatformException) {
      detail = '${error.code} ${error.message ?? ''}';
    } else if (error is http.ClientException) {
      return 'NETWORK';
    } else {
      return 'UNKNOWN';
    }
    for (final code in const [
      'SERVICE_NOT_AVAILABLE',
      'AUTHENTICATION_FAILED',
      'FIS_AUTH_ERROR',
      'TOO_MANY_REGISTRATIONS',
      'INVALID_SENDER',
      'MISSING_INSTANCEID_SERVICE',
      'API_KEY_INVALID',
      'PERMISSION_DENIED',
    ]) {
      if (detail.toUpperCase().contains(code)) return code;
    }
    return 'PLATFORM_ERROR';
  }

  static Future<T> _step<T>(String stage, Future<T> Function() work) async {
    try {
      return await work();
    } catch (error) {
      final code = diagnosticCode(error);
      if (kDebugMode) debugPrint('[admin-fcm] $stage: $code');
      throw FormatException('Bildirim bağlantısı kurulamadı ($stage: $code).');
    }
  }

  static Future<void> stop() async {
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    } catch (_) {}
  }

  static Future<void> _received(RemoteMessage message) async {
    try {
      if (!await DeviceTestService.instance.message(message.data)) return;
      // The debug Android service displays renderer 2 in every app state.
      // Dart only records receipt; otherwise foreground delivery would duplicate it.
      if (message.data['notificationRenderer'] == '2') return;
      final title = message.notification?.title ?? 'Rotalink testi',
          body = message.notification?.body ?? '';
      final picture = await _picture(message.notification?.android?.imageUrl);
      await _foreground?.call(
        title: title,
        body: body,
        deliveryId: message.data['testDelivery'],
        picture: picture,
      );
    } catch (_) {}
  }

  static bool validImage(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'admin.rotalink.tr' &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        RegExp(
          r'^/device-test/image/[a-zA-Z0-9_-]{43}/[a-f0-9-]{36}\.(jpg|png)$',
        ).hasMatch(uri.path);
  }

  static Future<Uint8List?> _picture(String? value) async {
    if (!validImage(value)) return null;
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(value!)))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) > 1024 * 1024) {
        await response.stream.listen(null).cancel();
        return null;
      }
      final data = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 3),
      )) {
        if (data.length + chunk.length > 1024 * 1024) return null;
        data.addAll(chunk);
      }
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
