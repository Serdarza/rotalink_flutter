import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/campaign.dart';
import '../services/network_service.dart';
import 'github_kampanya_data_source.dart';
import 'kampanya_local_cache.dart';
import 'kampanya_sync_prefs.dart';

/// Keşfet kampanyaları GitHub'daki [kampanya.json] dosyasından okunur.
class CampaignRepository {
  CampaignRepository._();

  static final CampaignRepository instance = CampaignRepository._();

  factory CampaignRepository() => instance;

  List<Campaign>? _memoryCampaigns;
  Future<List<Campaign>>? _resolveInFlight;
  Future<void>? _syncInFlight;
  final StreamController<List<Campaign>> _updates =
      StreamController<List<Campaign>>.broadcast();

  List<Campaign> get currentCampaigns => _memoryCampaigns ?? const [];

  bool get isReady => _memoryCampaigns != null;

  /// İlk kurulumda GitHub'dan indirir; sonraki açılışlarda yerel önbellek + günlük kontrol.
  Future<void> ensureLocalDataReady() async {
    if (await KampanyaLocalCache.hasCache()) {
      await _loadFromLocalCache();
      unawaited(_maybeSyncIfRemoteVersionChanged());
      return;
    }
    if (!await NetworkService.instance.isConnected()) return;
    await _downloadAndPersist();
  }

  /// Mevcut listeyi hemen, sonra arka planda indirilen her yeni listeyi yayınlar.
  Stream<List<Campaign>> watchCampaignsOrdered() async* {
    yield _memoryCampaigns ?? await _resolveCampaigns();
    yield* _updates.stream;
  }

  /// Aşağı çekerek yenileme: aralığı beklemeden sunucu sürümünü kontrol eder.
  Future<void> refresh() => _maybeSyncIfRemoteVersionChanged(force: true);

  Future<List<Campaign>> _resolveCampaigns() {
    if (_memoryCampaigns != null) {
      return Future.value(_memoryCampaigns!);
    }
    return _resolveInFlight ??= _resolveCampaignsBody().whenComplete(() {
      _resolveInFlight = null;
    });
  }

  Future<List<Campaign>> _resolveCampaignsBody() async {
    if (_memoryCampaigns != null) return _memoryCampaigns!;
    if (await KampanyaLocalCache.hasCache()) {
      return _loadFromLocalCache();
    }
    if (!await NetworkService.instance.isConnected()) {
      return _memoryCampaigns = const [];
    }
    await _downloadAndPersist();
    return _memoryCampaigns ?? const [];
  }

  Future<List<Campaign>> _loadFromLocalCache() async {
    try {
      final raw = await KampanyaLocalCache.readJson();
      if (raw == null) {
        return _memoryCampaigns = const [];
      }
      final decoded = jsonDecode(raw);
      return _memoryCampaigns = Campaign.parseListFromRoot(decoded);
    } catch (err, st) {
      _log('Yerel kampanya önbelleği okunamadı: $err', st);
      return _memoryCampaigns = const [];
    }
  }

  Future<void> _maybeSyncIfRemoteVersionChanged({bool force = false}) {
    return _syncInFlight ??= _syncBody(force: force).whenComplete(() {
      _syncInFlight = null;
    });
  }

  Future<void> _syncBody({required bool force}) async {
    if (!await NetworkService.instance.isConnected()) return;
    if (!force && !await KampanyaSyncPrefs.isCheckDue()) return;

    await KampanyaSyncPrefs.markVersionCheckCompleted();

    final remoteVersion = await GithubKampanyaDataSource.fetchRemoteVersion();
    if (remoteVersion == null) return;

    final localVersion = await KampanyaSyncPrefs.getLocalVersion();
    if (localVersion == remoteVersion) return;

    await _downloadAndPersist(expectedVersion: remoteVersion);
  }

  Future<void> _downloadAndPersist({String? expectedVersion}) async {
    try {
      if (!await NetworkService.instance.isConnected()) {
        _log('İnternet yok; GitHub kampanyaları indirilemedi.');
        return;
      }

      final json = await GithubKampanyaDataSource.fetchKampanyalarFromGitHub();
      if (json == null) {
        _log('GitHub kampanyaları boş veya ulaşılamadı.');
        return;
      }

      final decoded = jsonDecode(json);
      await KampanyaLocalCache.writeJson(json);
      final campaigns = Campaign.parseListFromRoot(decoded);
      _memoryCampaigns = campaigns;
      _updates.add(campaigns);

      final version =
          expectedVersion ??
          await GithubKampanyaDataSource.fetchRemoteVersion();
      if (version != null) {
        await KampanyaSyncPrefs.setLocalVersion(version);
      }
    } catch (e, st) {
      _log('Kampanya işleme hatası: $e', st);
    }
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[CampaignRepository] $message');
    if (kDebugMode && st != null) {
      debugPrint(st.toString());
    }
  }
}
