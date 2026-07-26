import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../data/app_rating_prefs.dart';
import '../ads/ad_service.dart';
import '../ads/discover_native_ad_pool.dart';
import '../billing/pro_service.dart';
import '../data/campaign_repository.dart';
import '../data/facility_address_repository.dart';
import '../data/facility_image_repository.dart';
import '../data/facility_price_repository.dart';
import '../data/gezi_yemek_repository.dart';
import '../data/firebase_rota_repository.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/system_ui.dart';
import 'rotalink_main_shell.dart';

/// Tam ekran kurumsal renk; ortada başlık + alt slogan. İkon / logo yok.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.repository});

  final FirebaseRotaRepository repository;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    unawaited(AppRatingPrefs.incrementLaunchCount());

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);

    unawaited(RotalinkSystemUi.applyEdgeToEdge());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      unawaited(_runSplashSequence());
    });
  }

  Future<void> _runSplashSequence() async {
    // Kısa marka anı + veri (çoğu zaman ConnectivityGate'te başlamış olur).
    unawaited(_entrance.forward());
    await Future.wait<void>([
      widget.repository.ensureLocalDataReady(),
      Future<void>.delayed(const Duration(milliseconds: 220)),
    ]);

    // Overlay / kampanya: ana ekranı bekletmesin.
    unawaited(_warmSecondaryData());

    if (!mounted) return;
    _goMain();
  }

  Future<void> _warmSecondaryData() async {
    await Future.wait<void>([
      CampaignRepository.instance.ensureLocalDataReady(),
      FacilityPriceRepository.instance.ensureLocalDataReady(),
      FacilityImageRepository.instance.ensureLocalDataReady(),
      FacilityAddressRepository.instance.ensureLocalDataReady(),
      GeziYemekRepository.instance.ensureLocalDataReady(),
    ]);
    final campaignCount = CampaignRepository.instance.currentCampaigns.length;
    if (campaignCount > 0 && !ProService.instance.isAdFree) {
      // AdMob SDK hazır olmadan istek atılmasın (Android/iOS).
      await AdService.instance.whenSdkReady();
      if (!ProService.instance.isAdFree) {
        unawaited(DiscoverNativeAdPool.instance.ensureAds(campaignCount));
      }
    }
  }

  void _goMain() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) =>
            RotalinkMainShell(repository: widget.repository),
        transitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const titleStyle = TextStyle(
      color: AppColors.white,
      fontSize: 32,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
    );
    final subtitleStyle = TextStyle(
      color: AppColors.white.withValues(alpha: 0.92),
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.25,
    );

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(AppStrings.appName, style: titleStyle),
                const SizedBox(height: 12),
                Text(
                  AppStrings.splashTagline,
                  textAlign: TextAlign.center,
                  style: subtitleStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
