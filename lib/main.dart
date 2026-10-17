import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'ads/analytics_observer.dart';
import 'ads/firebase_analytics_service.dart';
import 'app.dart';
import 'billing/free_price_quota.dart';
import 'billing/pro_service.dart';
import 'bootstrap/firebase_bootstrap.dart';
import 'deeplink/deep_link_service.dart';
import 'services/announcement_notification_scheduler.dart';
import 'services/campaign_push_service.dart';
import 'services/holiday_notification_scheduler.dart';
import 'services/pro_update_notifier.dart';
import 'theme/system_ui.dart';

/// AnalyticsObserver — MaterialApp içinde kullanılır; Firebase Analytics
/// ısınması [runApp] sonrasına bırakılır.
late final AnalyticsObserver analyticsObserver;

final Stopwatch startupClock = Stopwatch();

void logStartup(String step) {
  debugPrint('[açılış] $step ${startupClock.elapsedMilliseconds}ms');
}

Future<void> main() async {
  startupClock.start();
  WidgetsFlutterBinding.ensureInitialized();
  logStartup('binding');

  unawaited(
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  );
  unawaited(RotalinkSystemUi.applyEdgeToEdge());

  analyticsObserver = AnalyticsObserver(FirebaseAnalyticsService.instance);
  runApp(const ProviderScope(child: RotalinkApp()));
  FlutterNativeSplash.remove();
  logStartup('runApp');

  unawaited(_startBackgroundServices());
}

/// Firebase ve diğer servisler ilk kareden sonra ısınır; açılışı bekletmez.
Future<void> _startBackgroundServices() async {
  try {
    await initializeFirebase();
    logStartup('firebase');
  } catch (e) {
    debugPrint('Firebase başlatılamadı: $e');
  }
  unawaited(DeepLinkService.instance.start());
  unawaited(
    CampaignPushService.initialize().catchError(
      (Object e) => debugPrint('Kampanya bildirimleri başlatılamadı: $e'),
    ),
  );
  unawaited(_requestRuntimePermissions());
  unawaited(_bootstrapSecondary());
}

Future<void> _requestRuntimePermissions() async {
  await Future<void>.delayed(const Duration(seconds: 8));
  try {
    await FirebaseMessaging.instance.requestPermission();
  } catch (_) {}
  try {
    await HolidayNotificationScheduler.requestPermissions();
  } catch (_) {}
}

/// Açılış kritik yolunun dışında kalan servisler.
Future<void> _bootstrapSecondary() async {
  try {
    await FirebaseAnalyticsService.instance.initialize();
    unawaited(FirebaseAnalyticsService.instance.logAppOpen());
  } catch (e) {
    debugPrint('Firebase Analytics başlatılamadı: $e');
  }

  // Bağımsız işler paralel — sıralı await toplam süreyi uzatmasın.
  await Future.wait<void>([
    () async {
      try {
        await ProService.instance.initialize();
      } catch (e) {
        debugPrint('Pro abonelik başlatılamadı: $e');
      }
    }(),
    FreePriceQuota.instance.initialize(),
    () async {
      try {
        await initializeDateFormatting('tr_TR', null);
      } catch (e) {
        debugPrint('Tarih formatı başlatılamadı: $e');
      }
    }(),
    () async {
      try {
        await HolidayNotificationScheduler.initialize();
      } catch (e) {
        debugPrint('Bildirim zamanlayıcı başlatılamadı: $e');
      }
      unawaited(AnnouncementNotificationScheduler.sync().catchError(
        (Object e) => debugPrint('Duyuru bildirimleri zamanlanamadı: $e'),
      ));
      try {
        await ProUpdateNotifier.initialize();
      } catch (e) {
        debugPrint('Pro güncelleme bildirimleri başlatılamadı: $e');
      }
    }(),
  ]);
}
