import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'holiday_notification_scheduler.dart';

/// "Yeni Kampanya Bildirimleri" — GitHub `kampanya.json` indirdiğinde yerel bildirim.
///
/// Firebase / FCM kullanılmaz. Uygulama yeni kayıtları çekince, daha önce
/// görülmemiş kimlikler için tek bildirim gösterilir. İlk indirmede mevcut
/// liste taban alınır, toplu bildirim gitmez. Tercih kapalıysa gösterilmez.
/// Bildirime dokunmak Kampanya sekmesini açar.
abstract final class CampaignPushService {
  static const prefKey = 'rotalink_campaign_push_enabled';
  static const _prefPendingOpen = 'rotalink_pending_open_campaigns';
  static const _prefKnownIds = 'rotalink_campaign_known_ids';
  static const _maxKnownIds = 3000;

  static const channelId = 'rotalink_campaigns';
  static const channelName = 'Yeni kampanyalar';
  static const channelDescription =
      'Rotalink\'e yeni kampanyalar eklendiğinde bildirim';

  static const localPayload = 'campaign:new';

  static const settingTitle = 'Yeni Kampanya Bildirimleri';
  static const settingDescription =
      'Uygulama yeni kampanyaları indirdiğinde bildirim al.';

  /// Kullanıcı bildirime dokundukça artar; ana iskelet dinler.
  static final ValueNotifier<int> openRequests = ValueNotifier<int>(0);
  static bool _pendingOpen = false;

  static Future<bool> Function() _requestPermission =
      HolidayNotificationScheduler.requestPermissions;
  static Future<void> Function({required String title, required String body})
      _showLocal = HolidayNotificationScheduler.showCampaignNotification;
  static bool _initialized = false;

  @visibleForTesting
  static void debugSetPermission(Future<bool> Function() fn) =>
      _requestPermission = fn;

  @visibleForTesting
  static void debugSetLocalNotifier(
    Future<void> Function({required String title, required String body}) fn,
  ) =>
      _showLocal = fn;

  @visibleForTesting
  static void debugReset() {
    _pendingOpen = false;
    openRequests.value = 0;
    _requestPermission = HolidayNotificationScheduler.requestPermissions;
    _showLocal = HolidayNotificationScheduler.showCampaignNotification;
    _initialized = false;
  }

  static (String title, String body) buildText(int count) {
    if (count > 0) {
      return (
        'Rotalink – $count Yeni Kampanya Eklendi! 🎉',
        'Yeni fırsatları keşfetmek için hemen Rotalink\'i aç!',
      );
    }
    return (
      'Rotalink – Yeni Kampanyalar Eklendi! 🎉',
      'Rotalink\'e yeni kampanyalar eklendi. Fırsatları kaçırmamak için hemen keşfet!',
    );
  }

  // ------------------------------------------------------------------ tercih

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(prefKey) ?? true;
  }

  /// Tercihi kaydeder. Açarken yerel bildirim izni istenir; izin yoksa `false`
  /// döner (tercih yine kaydedilir).
  static Future<bool> setEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(prefKey, enabled);
    var permitted = true;
    if (enabled) {
      try {
        permitted = await _requestPermission();
      } catch (e) {
        debugPrint('Kampanya bildirimi izni alınamadı: $e');
      }
    }
    return permitted;
  }

  // ------------------------------------------------------------------ mesajlar

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

  /// GitHub listesindeki kimlikleri işler: ilk seferde taban kaydı, sonra yalnızca
  /// yeni kimlikler için bir yerel bildirim.
  static Future<void> notifyNewCampaigns(Iterable<String> currentIds) async {
    final fresh = await claimNewIds(currentIds);
    if (fresh.isEmpty) return;
    if (!await isEnabled()) return;
    final text = buildText(fresh.length);
    await _showLocal(title: text.$1, body: text.$2);
  }

  /// Daha önce görülmemiş kimlikleri döndürür. İlk çağrıda tümünü taban alır,
  /// bildirim üretmez (`[]`).
  @visibleForTesting
  static Future<List<String>> claimNewIds(Iterable<String> currentIds) async {
    final ids = <String>[];
    final seen = <String>{};
    for (final raw in currentIds) {
      final id = raw.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      ids.add(id);
    }
    if (ids.isEmpty) return const [];

    final p = await SharedPreferences.getInstance();
    final stored = p.getStringList(_prefKnownIds);
    if (stored == null) {
      await p.setStringList(_prefKnownIds, _capped(ids));
      return const [];
    }

    final known = stored.toSet();
    final fresh = [for (final id in ids) if (!known.contains(id)) id];
    if (fresh.isEmpty) return const [];

    await p.setStringList(_prefKnownIds, _capped([...stored, ...fresh]));
    return fresh;
  }

  static List<String> _capped(List<String> ids) {
    if (ids.length <= _maxKnownIds) return ids;
    return ids.sublist(ids.length - _maxKnownIds);
  }

  // ------------------------------------------------------------------ başlatma

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;

    await _consumePendingFromPrefs();
    if (await isEnabled()) {
      try {
        await _requestPermission();
      } catch (e) {
        debugPrint('Kampanya bildirimi izni alınamadı: $e');
      }
    }
  }
}
