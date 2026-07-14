import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'ads/ad_config_bootstrap.dart';
import 'ads/ad_service.dart';
import 'ads/analytics_observer.dart';
import 'ads/firebase_analytics_service.dart';
import 'app.dart';
import 'bootstrap/firebase_bootstrap.dart';
import 'services/holiday_notification_scheduler.dart';

/// AnalyticsObserver — MaterialApp içinde kullanılır; Firebase Analytics
/// ısınması [runApp] sonrasına bırakılır.
late final AnalyticsObserver analyticsObserver;

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Yönlendirme UI'yı bloklamasın.
  unawaited(
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  );

  // Kritik: Firebase Core — harita / RTDB / splash buna ihtiyaç duyar.
  try {
    await initializeFirebase();
  } catch (e) {
    debugPrint('Firebase başlatılamadı: $e');
  }

  analyticsObserver = AnalyticsObserver(FirebaseAnalyticsService.instance);

  runApp(const ProviderScope(child: RotalinkApp()));

  // Reklam, Analytics, bildirim, tarih — ilk frame'den sonra.
  unawaited(_bootstrapSecondary());
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
        await syncAdCooldown();
        await AdService.instance.initialize();
        await syncAdCooldown();
      } catch (e) {
        debugPrint('AdMob başlatılamadı: $e');
      }
    }(),
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
    }(),
  ]);
}
