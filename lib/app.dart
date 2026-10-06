import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'main.dart';
import 'bootstrap/secondary_data.dart';
import 'data/app_rating_prefs.dart';
import 'data/firebase_rota_repository.dart';
import 'data/rota_local_cache.dart';
import 'navigator_keys.dart';
import 'l10n/app_strings.dart';
import 'screens/no_connection_screen.dart';
import 'screens/rotalink_main_shell.dart';
import 'services/holiday_notification_scheduler.dart';
import 'services/network_service.dart';
import 'theme/app_theme.dart';
import 'theme/system_ui.dart';

class RotalinkApp extends StatelessWidget {
  const RotalinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: RotalinkSystemUi.lightIcons,
      child: MaterialApp(
        navigatorKey: rotalinkNavigatorKey,
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: buildRotalinkTheme(),
        home: const _ConnectivityGate(),
        // AnalyticsObserver'ı navigatorObservers'a ekle - ekran izlemeyi etkinleştirir
        navigatorObservers: [analyticsObserver],
      ),
    );
  }
}

/// Uygulama giriş noktası: internet durumunu ve geçmiş açılış sayısını kontrol eder.
///
/// - İlk açılış (hiç önbellek yok) + internet yok → [NoConnectionScreen]
/// - Geri dönen kullanıcı (yerel veri önbelleği var) → internet olmadan da ana ekran
/// - İnternet var → ana ekran
///
/// Ara açılış ekranı yok: ana ekran veriyi beklemeden açılır, harita verisi
/// gelince dolar. Bağlantı geldiğinde [NoConnectionScreen] ana ekrana geçer.
class _ConnectivityGate extends StatefulWidget {
  const _ConnectivityGate();

  @override
  State<_ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<_ConnectivityGate> {
  /// Repository bir kez oluşturulur; uygulama boyunca aynı örnek.
  final _repository = FirebaseRotaRepository();

  /// null = henüz kontrol ediliyor; true = ana ekran; false = bağlantı yok ekranı.
  bool? _showMain;

  @override
  void initState() {
    super.initState();
    unawaited(_decideInitialRoute());
    // İzin diyaloğu runApp() sonrası ilk frame'den itibaren gösterilir.
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
    // Geri dönen kullanıcı: yerel önbellek mevcuttur, çevrimdışı çalışır.
    final launchCount = await AppRatingPrefs.getLaunchCount();
    final hasLocalRota = await RotaLocalCache.hasCache();
    final isReturningUser = launchCount > 1 || hasLocalRota;

    if (isReturningUser) {
      _openMain();
      return;
    }

    // İlk açılış: internet yoksa veri çekilemez → bağlantı ekranı göster.
    final connected = await NetworkService.instance.isConnected();
    if (!mounted) return;

    if (connected) {
      _openMain();
    } else {
      FlutterNativeSplash.remove();
      setState(() => _showMain = false);
    }
  }

  bool _mainStarted = false;

  void _openMain() {
    if (!mounted) return;
    if (!_mainStarted) {
      _mainStarted = true;
      unawaited(AppRatingPrefs.incrementLaunchCount());
      unawaited(RotalinkSystemUi.applyEdgeToEdge());
      unawaited(() async {
        await _repository.ensureLocalDataReady();
        await warmSecondaryData();
      }());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FlutterNativeSplash.remove();
      });
    }
    setState(() => _showMain = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_showMain == null) {
      return const Scaffold(backgroundColor: Colors.transparent);
    }

    if (_showMain!) {
      return RotalinkMainShell(repository: _repository);
    }

    return NoConnectionScreen(onConnected: _openMain);
  }
}
