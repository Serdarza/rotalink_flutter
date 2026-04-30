import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/firebase_rota_repository.dart';

/// Kotlin `MyApplication` / `build.gradle` içindeki Firebase parçalarına denk başlatma.
///
/// **Not:** iOS derlemesi için `ios/Runner/GoogleService-Info.plist` gerekir (Kotlin
/// projesinde yok; Firebase Console → iOS uygulaması → plist indirip Xcode’a ekleyin).

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// [Firebase.initializeApp] ve isteğe bağlı servis ön yükleme.
Future<FirebaseApp> initializeFirebase() async {
  final app = await Firebase.initializeApp();

  FirebaseRotaRepository.configureOfflinePersistence();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await FirebaseMessaging.instance.setAutoInitEnabled(true);
  await FirebaseMessaging.instance.requestPermission();

  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);

  unawaited(_primeRemoteConfig());

  return app;
}

/// Kotlin `MainActivity` içindeki `latest_version_code` varsayılanı ile uyumlu ön yükleme.
Future<void> _primeRemoteConfig() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final build = int.tryParse(info.buildNumber) ?? 1;

    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
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
