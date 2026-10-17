import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'holiday_notification_scheduler.dart';

/// FCM işlemlerini soyutlar; testlerde sahte uygulama verilir.
abstract class CampaignMessagingClient {
  Future<bool> requestPermission();
  Future<void> subscribe(String topic);
  Future<void> unsubscribe(String topic);

  /// iOS'ta konu aboneliği için APNs token'ı hazır olmalıdır (diğer platformlarda true).
  Future<bool> isReadyToSubscribe();
}

class _FirebaseMessagingClient implements CampaignMessagingClient {
  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  @override
  Future<bool> requestPermission() async {
    final s = await _fm.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<void> subscribe(String topic) => _fm.subscribeToTopic(topic);

  @override
  Future<void> unsubscribe(String topic) => _fm.unsubscribeFromTopic(topic);

  @override
  Future<bool> isReadyToSubscribe() async {
    if (kIsWeb || !Platform.isIOS) return true;
    for (var i = 0; i < 6; i++) {
      if (await _fm.getAPNSToken() != null) return true;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }
}

/// "Yeni Kampanya Bildirimleri" — sunucudan (GitHub Actions → FCM HTTP v1) gelen
/// günlük 10:00 bildirimi.
///
/// * Bildirim `kampanya_yeni` FCM konusuna gider; kullanıcı kapatınca konudan çıkarılır,
///   böylece hiçbir kampanya bildirimi almaz. Cihaz tokenları sunucuda tutulmaz;
///   token yenileme ve geçersiz token temizliği FCM tarafından yönetilir.
/// * Tercih, duyuru ve tatil bildirimi tercihlerinden ayrı saklanır.
/// * Bildirime dokunmak (uygulama kapalı / arka planda / açık) Kampanya sekmesini açar.
abstract final class CampaignPushService {
  static const topic = 'kampanya_yeni';
  static const prefKey = 'rotalink_campaign_push_enabled';
  static const _prefPendingOpen = 'rotalink_pending_open_campaigns';

  static const channelId = 'rotalink_campaigns';
  static const channelName = 'Yeni kampanyalar';
  static const channelDescription = 'Rotalink\'e yeni kampanyalar eklendiğinde bildirim';

  /// Sunucu `data.type` değeri ve yerel (ön plan) bildirim yükü.
  static const messageType = 'new_campaigns';
  static const localPayload = 'campaign:new';

  /// Ayarlar kartındaki başlık ve açıklama.
  static const settingTitle = 'Yeni Kampanya Bildirimleri';
  static const settingDescription =
      'Rotalink\'e yeni kampanyalar eklendiğinde bildirim al.';

  /// Kullanıcı bildirime dokundukça artar; ana iskelet dinler.
  static final ValueNotifier<int> openRequests = ValueNotifier<int>(0);
  static bool _pendingOpen = false;

  static CampaignMessagingClient _client = _FirebaseMessagingClient();
  static Future<void> Function({required String title, required String body})
      _showLocal = HolidayNotificationScheduler.showCampaignNotification;
  static bool _initialized = false;
  static final List<StreamSubscription<Object?>> _subs = [];

  @visibleForTesting
  static void debugSetClient(CampaignMessagingClient client) => _client = client;

  @visibleForTesting
  static void debugSetLocalNotifier(
    Future<void> Function({required String title, required String body}) fn,
  ) =>
      _showLocal = fn;

  @visibleForTesting
  static void debugReset() {
    _pendingOpen = false;
    openRequests.value = 0;
    _client = _FirebaseMessagingClient();
    _showLocal = HolidayNotificationScheduler.showCampaignNotification;
    _initialized = false;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }

  // ------------------------------------------------------------------ tercih

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(prefKey) ?? true;
  }

  /// Tercihi kaydeder ve FCM konu aboneliğini eşitler. Açarken bildirim izni istenir;
  /// izin verilmemişse `false` döner (tercih yine kaydedilir).
  static Future<bool> setEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(prefKey, enabled);
    var permitted = true;
    if (enabled) {
      try {
        permitted = await _client.requestPermission();
        await HolidayNotificationScheduler.requestPermissions();
      } catch (e) {
        debugPrint('Kampanya bildirimi izni alınamadı: $e');
      }
    }
    await syncSubscription();
    return permitted;
  }

  /// Tercihe göre konuya abone ol / aboneliği kaldır. Hata olursa uygulamayı bozmaz.
  static Future<void> syncSubscription() async {
    try {
      final enabled = await isEnabled();
      if (!await _client.isReadyToSubscribe()) return; // token yenilenince tekrar denenir
      if (enabled) {
        await _client.subscribe(topic);
      } else {
        await _client.unsubscribe(topic);
      }
    } catch (e) {
      debugPrint('Kampanya bildirimi aboneliği eşitlenemedi: $e');
    }
  }

  // ------------------------------------------------------------------ mesajlar

  static bool isCampaignMessage(Map<String, dynamic> data) =>
      data['type'] == messageType || data['route'] == 'kampanyalar';

  /// Kampanya sekmesinin açılmasını ister (uygulama henüz hazır değilse bekletilir).
  static void requestOpen() {
    _pendingOpen = true;
    openRequests.value++;
  }

  static bool get hasPendingOpen => _pendingOpen;

  /// Bekleyen açma isteğini tüketir; ana iskelet hazır olduğunda çağrılır.
  static bool consumePendingOpen() {
    final had = _pendingOpen;
    _pendingOpen = false;
    return had;
  }

  /// Ayrı isolate'ta (arka plan dokunuşu) çağrılır; uygulama açılınca [initialize] okur.
  static Future<void> markPendingOpenInPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefPendingOpen, true);
  }

  static Future<void> _consumePendingFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    if (p.getBool(_prefPendingOpen) ?? false) {
      await p.setBool(_prefPendingOpen, false);
      requestOpen();
    }
  }

  @visibleForTesting
  static void handleOpenedMessage(Map<String, dynamic> data) {
    if (isCampaignMessage(data)) requestOpen();
  }

  /// Ön planda gelen kampanya mesajı: sistem bildirimi göstermez, bu yüzden yerel
  /// bildirim üretilir (tıklanınca aynı yönlendirme çalışır).
  @visibleForTesting
  static Future<void> handleForegroundMessage(
    Map<String, dynamic> data,
    String? title,
    String? body,
  ) async {
    if (!isCampaignMessage(data)) return;
    if (!await isEnabled()) return;
    await _showLocal(
      title: title ?? 'Rotalink – Yeni Kampanyalar Eklendi! 🎉',
      body: body ??
          'Rotalink\'e yeni kampanyalar eklendi. Fırsatları kaçırmamak için hemen keşfet!',
    );
  }

  // ------------------------------------------------------------------ başlatma

  /// Firebase hazır olduktan sonra bir kez çağrılır.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;

    final fm = FirebaseMessaging.instance;

    _subs.add(FirebaseMessaging.onMessage.listen((m) {
      unawaited(handleForegroundMessage(
        m.data,
        m.notification?.title,
        m.notification?.body,
      ));
    }));
    _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => handleOpenedMessage(m.data),
    ));
    // Token yenilenince / APNs token'ı gelince abonelik yeniden eşitlenir.
    _subs.add(fm.onTokenRefresh.listen((_) => unawaited(syncSubscription())));

    try {
      final initial = await fm.getInitialMessage();
      if (initial != null) handleOpenedMessage(initial.data);
    } catch (e) {
      debugPrint('İlk bildirim okunamadı: $e');
    }
    await _consumePendingFromPrefs();
    unawaited(syncSubscription());
  }
}
