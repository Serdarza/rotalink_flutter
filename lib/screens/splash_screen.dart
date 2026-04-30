import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../data/app_rating_prefs.dart';
import '../data/firebase_rota_repository.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import 'main_map_screen.dart';

/// Tam ekran kurumsal renk; ortada başlık + alt slogan. İkon / logo yok.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.repository});

  final FirebaseRotaRepository repository;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    unawaited(AppRatingPrefs.incrementLaunchCount());

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      unawaited(widget.repository.primeRootSnapshot());
      unawaited(_runSplashSequence());
    });
  }

  Future<void> _runSplashSequence() async {
    await _entrance.forward();
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    _goMain();
  }

  void _goMain() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MainMapScreen(repository: widget.repository),
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
