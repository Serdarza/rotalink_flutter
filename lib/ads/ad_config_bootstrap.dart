import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../data/github_ad_config_data_source.dart';
import 'ad_service.dart';

/// Reklam bekleme süresi — önce GitHub [reklam_ayar.json], yedek Firebase Remote Config.
Future<void> syncAdCooldown() async {
  try {
    final policy = await GithubAdConfigDataSource.fetchPolicy();
    if (policy != null) {
      AdService.instance.setAdCooldownMinutes(policy.cooldownMinutes);
      debugPrint(
        'AdService: GitHub reklam_bekleme_suresi=${AdService.instance.intervalMinutes} dk',
      );
      return;
    }
  } catch (e) {
    debugPrint('AdService: GitHub reklam ayarı okunamadı ($e)');
  }

  _syncFromRemoteConfig();
}

void _syncFromRemoteConfig() {
  try {
    final remoteConfig = FirebaseRemoteConfig.instance;
    final cooldownMinutes = remoteConfig.getInt('reklam_bekleme_suresi');
    final minutes = cooldownMinutes <= 0 ? 5 : cooldownMinutes;
    AdService.instance.setAdCooldownMinutes(minutes);
    debugPrint(
      'AdService: Remote Config reklam_bekleme_suresi=${AdService.instance.intervalMinutes} dk',
    );
  } catch (e) {
    AdService.instance.setAdCooldownMinutes(5);
    debugPrint('AdService: varsayılan 5 dk ($e)');
  }
}

/// Geriye dönük uyumluluk.
@Deprecated('syncAdCooldown kullanın')
void syncAdCooldownWithRemoteConfig() => _syncFromRemoteConfig();
