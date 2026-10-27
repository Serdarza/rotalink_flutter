import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/map_tile_cache_service.dart';

/// Kotlin `MyApplication` / `build.gradle` içindeki Firebase parçalarına denk başlatma.
///
/// **Not:** iOS derlemesi için `ios/Runner/GoogleService-Info.plist` gerekir (Kotlin
/// projesinde yok; Firebase Console → iOS uygulaması → plist indirip Xcode’a ekleyin).

/// Kritik yol: yalnızca [Firebase.initializeApp].
/// Analytics / Remote Config arka planda ısınır — açılışı bloklamaz.
Future<FirebaseApp> initializeFirebase() async {
  final app = await Firebase.initializeApp();

  unawaited(MapTileCacheService.instance.ensureInitialized());
  unawaited(_warmFirebaseServices());
  return app;
}

Future<void> _warmFirebaseServices() async {
  try {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
  } catch (_) {}

  unawaited(primeRemoteConfig());
}

/// Kotlin `MainActivity` içindeki `latest_version_code` varsayılanı ile uyumlu ön yükleme.
Future<void> primeRemoteConfig() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final build = int.tryParse(info.buildNumber) ?? 1;

    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );
    await rc.setDefaults(<String, dynamic>{
      'latest_version_code': build.toString(),
    });
    await rc.fetchAndActivate();
  } catch (_) {
    // Ağ / yapılandırma: ana akışı bloklamayın.
  }
}
