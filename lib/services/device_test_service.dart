import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/admin_popup.dart';

class DeviceTestService extends ChangeNotifier {
  DeviceTestService({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();
  static final instance = DeviceTestService();
  static const storageKey = 'rotalink_admin_device_test_v1';
  static const historyKey = 'rotalink_admin_popup_history_v1';
  final http.Client _client;
  final FlutterSecureStorage _storage;
  static const _nativeLayout = MethodChannel(
    'rotalink/admin_notification_layout',
  );
  Map<String, dynamic>? _session;
  Future<void>? _loadFlight;
  Future<void>? _refreshFlight;
  List<AdminPopup> _items = [];
  List<AdminPopup> get items => List.unmodifiable(_items);
  bool get paired =>
      kDebugMode &&
      _session != null &&
      DateTime.parse(_session!['expiresAt']).isAfter(DateTime.now());
  String get label => _session?['label'] ?? '';
  String get expiresAt => _session?['expiresAt'] ?? '';
  Map<String, String> get headers =>
      paired ? {'Authorization': 'Bearer ${_session!['token']}'} : {};
  Map<String, String>? pendingTarget;
  String status = '';
  int historyEpoch = 0;
  Future<void> resetPopupHistory() async {
    await (await SharedPreferences.getInstance()).remove(historyKey);
    historyEpoch++;
    notifyListeners();
  }

  Future<void> load() =>
      _loadFlight ??= _load().whenComplete(() => _loadFlight = null);
  Future<void> _load() async {
    if (!kDebugMode || _session != null) return;
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null) return;
      final s = jsonDecode(raw);
      if (s is Map<String, dynamic> &&
          s['token'] is String &&
          RegExp(r'^[a-zA-Z0-9_-]{43}$').hasMatch(s['token']) &&
          s['id'] is String &&
          DateTime.parse(s['expiresAt']).isAfter(DateTime.now())) {
        _session = s;
      }
    } catch (_) {
    } finally {
      await _syncNativeLayout();
    }
  }

  Future<int> _syncNativeLayout() async {
    if (!kDebugMode ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return 1;
    }
    try {
      return await _nativeLayout.invokeMethod<int>('configure', {
                'id': paired ? _session!['id'] : null,
                'expiresAt': paired
                    ? DateTime.parse(expiresAt).millisecondsSinceEpoch
                    : 0,
              }) ==
              2
          ? 2
          : 1;
    } catch (_) {
      return 1;
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final url = Uri.parse(AdminPopup.origin + path);
    final response =
        await (body == null
                ? _client.get(url, headers: headers)
                : _client.post(
                    url,
                    headers: {...headers, 'Content-Type': 'application/json'},
                    body: jsonEncode(body),
                  ))
            .timeout(const Duration(seconds: 6));
    if (response.statusCode == 401) {
      await disconnect(remote: false);
      throw const FormatException(
        'Test bağlantısının süresi doldu. Yeniden eşleştirin.',
      );
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException(
        data is Map
            ? data['error'] ?? 'Test isteği başarısız.'
            : 'Test isteği başarısız.',
      );
    }
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Geçersiz test yanıtı.');
    }
    return data;
  }

  Future<void> pair(
    String code, {
    String? fcmToken,
    String platform = 'android',
  }) async {
    if (!kDebugMode) throw const FormatException('Test modu kapalı.');
    final clean = code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (!RegExp(r'^[A-F0-9]{20}$').hasMatch(clean)) {
      throw const FormatException(
        'Paneldeki eşleştirme kodunu eksiksiz girin.',
      );
    }
    final response = await _request(
      '/device-test/pair',
      body: {'code': clean, 'platform': platform, 'fcmToken': ?fcmToken},
    );
    if (response['token'] is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{43}$').hasMatch(response['token']) ||
        response['id'] is! String ||
        response['expiresAt'] is! String) {
      throw const FormatException('Eşleştirme yanıtı geçersiz.');
    }
    await _storage.write(key: storageKey, value: jsonEncode(response));
    _session = response;
    status = 'Telefon bağlandı.';
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() =>
      _refreshFlight ??= _refresh().whenComplete(() => _refreshFlight = null);
  Future<void> _refresh() async {
    await load();
    if (!paired) return;
    try {
      final response = await _request('/device-test/state');
      final raw = response['items'];
      if (raw is! List || raw.length > 10) {
        throw const FormatException('Test listesi geçersiz.');
      }
      final parsed =
          raw
              .map((v) => AdminPopup.parse(Map<String, dynamic>.from(v)))
              .toList()
            ..sort((a, b) => b.priority.compareTo(a.priority));
      _items = parsed;
      status = 'Telefon test bağlantısı açık.';
      notifyListeners();
    } catch (_) {
      status = 'Test sunucusuna ulaşılamadı. Bağlantıyı kontrol edin.';
    }
  }

  Future<void> updateFcm(String token) async {
    await load();
    if (paired) {
      await _request(
        '/device-test/fcm',
        body: {
          'fcmToken': token,
          'notificationRenderer': await _syncNativeLayout(),
        },
      );
    }
  }

  Future<void> event(String delivery, String event) async {
    await load();
    if (!paired) return;
    try {
      await _request(
        '/device-test/events',
        body: {'deliveryId': delivery, 'event': event},
      );
    } catch (_) {}
  }

  Future<void> disconnect({bool remote = true}) async {
    if (remote && paired) {
      try {
        await _request('/device-test/disconnect', body: {});
      } catch (_) {}
    }
    _session = null;
    await _syncNativeLayout();
    _items = [];
    pendingTarget = null;
    await _storage.delete(key: storageKey);
    notifyListeners();
  }

  Future<bool> message(Map<String, dynamic> data, {bool opened = false}) async {
    await load();
    if (!paired ||
        data['type'] != 'rotalink_admin_test' ||
        data['testSession'] != _session!['id'] ||
        data['testDelivery'] is! String ||
        !RegExp(r'^[a-f0-9-]{36}$').hasMatch(data['testDelivery'])) {
      return false;
    }
    final target = <String, String>{
      'type': 'rotalink_admin_test',
      'testSession': data['testSession'],
      'testDelivery': data['testDelivery'],
      'route': data['route'] is String ? data['route'] : '',
      'link': data['link'] is String ? data['link'] : '',
    };
    if (!AdminPopup.routes.contains(target['route'])) return false;
    final link = target['link']!;
    if (link.isNotEmpty) {
      final u = Uri.tryParse(link);
      if (u == null ||
          u.scheme != 'https' ||
          u.host.isEmpty ||
          u.userInfo.isNotEmpty) {
        return false;
      }
    }
    final prefs = await SharedPreferences.getInstance(),
        keys = prefs.getStringList('admin_test_message_ids') ?? [];
    await prefs.setString(
      'admin_test_message_${data['testDelivery']}',
      jsonEncode(target),
    );
    if (!keys.contains(data['testDelivery'])) keys.add(data['testDelivery']);
    while (keys.length > 20) {
      await prefs.remove('admin_test_message_${keys.removeAt(0)}');
    }
    await prefs.setStringList('admin_test_message_ids', keys);
    await event(
      data['testDelivery'],
      opened ? 'notification_opened' : 'notification_received',
    );
    if (opened) {
      await prefs.setString('admin_test_pending_target', jsonEncode(target));
      pendingTarget = target;
      notifyListeners();
    }
    return true;
  }

  Future<void> localTap(String delivery) async {
    if (delivery.startsWith('native2:')) {
      try {
        await message(
          Map<String, dynamic>.from(jsonDecode(delivery.substring(8))),
          opened: true,
        );
      } catch (_) {}
      return;
    }
    final prefs = await SharedPreferences.getInstance(),
        raw = prefs.getString('admin_test_message_$delivery');
    if (raw == null) return;
    try {
      await message(Map<String, dynamic>.from(jsonDecode(raw)), opened: true);
    } catch (_) {}
  }

  Future<void> restorePendingTarget() async {
    final prefs = await SharedPreferences.getInstance(),
        raw = prefs.getString('admin_test_pending_target');
    if (raw == null) return;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw));
      await load();
      if (paired && data['testSession'] == _session!['id']) {
        pendingTarget = data.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}
  }

  Future<void> consumeTarget() async {
    pendingTarget = null;
    await (await SharedPreferences.getInstance()).remove(
      'admin_test_pending_target',
    );
  }
}
