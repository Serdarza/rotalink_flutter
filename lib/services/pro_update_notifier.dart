import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../billing/price_access.dart';
import '../billing/pro_service.dart';
import '../data/campaign_filter_prefs.dart';
import '../data/facility_price_repository.dart';
import '../data/favorites_repository.dart';
import '../data/github_fiyat_data_source.dart';
import '../data/github_kampanya_data_source.dart';
import '../models/campaign.dart';
import '../models/campaign_insights.dart';
import '../models/misafirhane.dart';
import '../utils/best_value_facility.dart';
import '../widgets/facility_tariff_view.dart' show formatTl;

const _taskName = 'com.serdarza.rotalink.proUpdates';

@pragma('vm:entry-point')
void rotalinkBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await ProUpdateNotifier.runCheck();
    } catch (e, st) {
      debugPrint('[ProUpdateNotifier] kontrol hatası: $e\n$st');
    }
    return true;
  });
}

/// Tek favori tesisin önceki / yeni tek kişi-gece fiyatları.
typedef FavoritePriceSnapshot = ({double? sivil, double? kamu});

/// Pro: favori tesis fiyatı değişince ve seçilen meslek grubuna yeni kampanya
/// gelince yerel bildirim. Uygulama kapalıyken günde ~2 kez arka planda çalışır;
/// Android pil tasarrufu ve iOS zamanlaması kontrolü geciktirebilir.
abstract final class ProUpdateNotifier {
  static const _kFavSnapshot = 'rotalink_pro_fav_price_snapshot';
  static const _kSeenCampaigns = 'rotalink_pro_seen_campaigns';

  static const _channelId = 'rotalink_pro_updates';
  static const _channelName = 'Fiyat ve kampanya güncellemeleri';
  static const _channelDescription =
      'Favori tesis fiyatı değişince ve mesleğinize yeni kampanya gelince (Pro)';
  static const _idPrice = 920001;
  static const _idCampaign = 920002;

  static Future<void> initialize() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    await Workmanager().initialize(rotalinkBackgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(hours: 12),
      initialDelay: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> runCheck() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!PriceAccess.unlockedWithCachedPro(ProService.cachedEntitlementActive(prefs))) {
      return;
    }
    final price = await _checkFavoritePrices(prefs);
    final campaign = await _checkCampaigns(prefs);
    if (price == null && campaign == null) return;

    final plugin = FlutterLocalNotificationsPlugin();
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
    if (price != null) await _show(plugin, _idPrice, price.title, price.body);
    if (campaign != null) await _show(plugin, _idCampaign, campaign.title, campaign.body);
  }

  static Future<void> _show(
    FlutterLocalNotificationsPlugin plugin,
    int id,
    String title,
    String body,
  ) {
    return plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body, summaryText: 'Rotalink Pro'),
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ favori fiyat

  static Future<({String title, String body})?> _checkFavoritePrices(
    SharedPreferences prefs,
  ) async {
    final favorites = await FavoritesRepository(prefs: prefs).load();
    if (favorites.isEmpty) return null;
    final json = await GithubFiyatDataSource.fetchFiyatlarFromGitHub();
    if (json == null) return null;
    FacilityPriceRepository.instance.applyJsonString(json);

    final next = <String, FavoritePriceSnapshot>{
      for (final m in favorites)
        m.stableFacilityId: (
          sivil: singleNightPriceFor(m, BestValueBasis.sivil)?.amount,
          kamu: singleNightPriceFor(m, BestValueBasis.kamu)?.amount,
        ),
    };
    final raw = prefs.getString(_kFavSnapshot);
    await prefs.setString(_kFavSnapshot, jsonEncode(_encodeSnapshots(next)));
    if (raw == null) return null;

    final previous = _decodeSnapshots(raw);
    final changed = changedFavoritePrices(previous, next, favorites);
    if (changed.isEmpty) return null;
    if (changed.length == 1) {
      final (m, before, after) = changed.single;
      return (
        title: 'Favori tesisinizin fiyatı güncellendi',
        body: '${m.isim.trim()}\n${_priceChangeLine(before, after)}',
      );
    }
    return (
      title: '${changed.length} favori tesisin fiyatı güncellendi',
      body: changed.map((e) => '• ${e.$1.isim.trim()}').join('\n'),
    );
  }

  /// Önceki kaydı olan ve en az bir fiyatı değişen favoriler. Yeni eklenen
  /// favoriler (önceki kaydı yok) ve fiyatı tamamen kalkanlar bildirilmez.
  @visibleForTesting
  static List<(Misafirhane, FavoritePriceSnapshot, FavoritePriceSnapshot)> changedFavoritePrices(
    Map<String, FavoritePriceSnapshot> previous,
    Map<String, FavoritePriceSnapshot> next,
    List<Misafirhane> favorites,
  ) {
    final out = <(Misafirhane, FavoritePriceSnapshot, FavoritePriceSnapshot)>[];
    for (final m in favorites) {
      final before = previous[m.stableFacilityId];
      final after = next[m.stableFacilityId];
      if (before == null || after == null) continue;
      if (after.sivil == null && after.kamu == null) continue;
      if (before.sivil == after.sivil && before.kamu == after.kamu) continue;
      out.add((m, before, after));
    }
    return out;
  }

  static String _priceChangeLine(FavoritePriceSnapshot before, FavoritePriceSnapshot after) {
    String part(String label, double? a, double? b) {
      if (b == null) return '';
      if (a == null) return '$label: ${formatTl(b)}';
      if (a == b) return '$label: ${formatTl(b)}';
      return '$label: ${formatTl(a)} → ${formatTl(b)}';
    }

    final parts = [
      part('Sivil', before.sivil, after.sivil),
      part('Kamu personeli', before.kamu, after.kamu),
    ].where((s) => s.isNotEmpty).join(' · ');
    return '$parts (tek kişi / gece)';
  }

  static Map<String, dynamic> _encodeSnapshots(Map<String, FavoritePriceSnapshot> m) => {
        for (final e in m.entries) e.key: {'s': e.value.sivil, 'k': e.value.kamu},
      };

  static Map<String, FavoritePriceSnapshot> _decodeSnapshots(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (e.value is Map)
            e.key: (
              sivil: ((e.value as Map)['s'] as num?)?.toDouble(),
              kamu: ((e.value as Map)['k'] as num?)?.toDouble(),
            ),
      };
    } catch (_) {
      return const {};
    }
  }

  // ------------------------------------------------------------ kampanya

  static Future<({String title, String body})?> _checkCampaigns(
    SharedPreferences prefs,
  ) async {
    final audience = await CampaignFilterPrefs.getAudience();
    if (audience == null) return null;
    final json = await GithubKampanyaDataSource.fetchKampanyalarFromGitHub();
    if (json == null) return null;
    final campaigns = Campaign.parseListFromRoot(jsonDecode(json));
    if (campaigns.isEmpty) return null;

    final seen = prefs.getStringList(_kSeenCampaigns);
    await prefs.setStringList(
      _kSeenCampaigns,
      campaigns.map(campaignKey).toSet().toList(),
    );
    if (seen == null) return null;

    final fresh = newCampaignsFor(audience, seen.toSet(), campaigns);
    if (fresh.isEmpty) return null;
    final group = audience.label;
    if (fresh.length == 1) {
      return (title: '$group için yeni kampanya', body: fresh.single.title.trim());
    }
    return (
      title: '$group için ${fresh.length} yeni kampanya',
      body: fresh.take(4).map((c) => '• ${c.title.trim()}').join('\n'),
    );
  }

  /// Kampanyanın sıra / kimlikten bağımsız anahtarı (kurum + başlık).
  @visibleForTesting
  static String campaignKey(Campaign c) => foldTr('${c.organization}|${c.title}');

  @visibleForTesting
  static List<Campaign> newCampaignsFor(
    CampaignAudience audience,
    Set<String> seen,
    List<Campaign> campaigns,
  ) =>
      campaigns
          .where((c) => !seen.contains(campaignKey(c)))
          .where((c) => CampaignInsights.of(c).matches(audience))
          .toList();
}
