import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'data/app_rating_prefs.dart';
import 'data/firebase_rota_repository.dart';
import 'navigator_keys.dart';
import 'l10n/app_strings.dart';
import 'screens/no_connection_screen.dart';
import 'screens/splash_screen.dart';
import 'services/holiday_notification_scheduler.dart';
import 'services/network_service.dart';
import 'theme/app_theme.dart';

class RotalinkApp extends StatelessWidget {
  const RotalinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rotalinkNavigatorKey,
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: buildRotalinkTheme(),
      home: const _ConnectivityGate(),
    );
  }
}

/// Uygulama giriş noktası: internet durumunu ve geçmiş açılış sayısını kontrol eder.
///
/// - İlk açılış (hiç önbellek yok) + internet yok → [NoConnectionScreen]
/// - Geri dönen kullanıcı (RTDB disk önbelleği var) → internet olmadan da [SplashScreen]
/// - İnternet var → [SplashScreen]
///
/// Bağlantı geldiğinde [NoConnectionScreen] otomatik olarak [SplashScreen]'e geçer.
class _ConnectivityGate extends StatefulWidget {
  const _ConnectivityGate();

  @override
  State<_ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<_ConnectivityGate> {
  /// Repository bir kez oluşturulur; splash → main akışı boyunca aynı örnek.
  final _repository = FirebaseRotaRepository();

  /// null = henüz kontrol ediliyor; true = splash göster; false = bağlantı yok ekranı.
  bool? _showSplash;

  @override
  void initState() {
    super.initState();
    unawaited(_decideInitialRoute());
    // İzin diyaloğu runApp() sonrası ilk frame'den itibaren gösterilir.
    // Önce gösterilirse iOS launch screen erken kapanır → siyah ekran.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_requestPermissions());
    });
  }

  Future<void> _requestPermissions() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}
    try {
      await HolidayNotificationScheduler.requestPermissions();
    } catch (_) {}
  }

  Future<void> _decideInitialRoute() async {
    // Geri dönen kullanıcı: RTDB disk önbelleği mevcuttur, çevrimdışı çalışır.
    final launchCount = await AppRatingPrefs.getLaunchCount();
    final isReturningUser = launchCount > 0;

    if (isReturningUser) {
      if (mounted) setState(() => _showSplash = true);
      return;
    }

    // İlk açılış: internet yoksa veri çekilemez → bağlantı ekranı göster.
    final connected = await NetworkService.instance.isConnected();
    if (!mounted) return;

    if (connected) {
      setState(() => _showSplash = true);
    } else {
      // Native splash'i kaldır ve "Bağlantı Yok" ekranını göster.
      FlutterNativeSplash.remove();
      setState(() => _showSplash = false);
    }
  }

  void _onConnected() {
    if (!mounted) return;
    setState(() => _showSplash = true);
  }

  @override
  Widget build(BuildContext context) {
    // Karar henüz verilmedi: native splash hâlâ ekranda, boş scaffold yeterli.
    if (_showSplash == null) {
      return const Scaffold(backgroundColor: Colors.transparent);
    }

    if (_showSplash!) {
      return SplashScreen(repository: _repository);
    }

    return NoConnectionScreen(onConnected: _onConnected);
  }
}
