import 'widgets/admin_popup_host.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'main.dart';
import 'bootstrap/secondary_data.dart';
import 'data/app_rating_prefs.dart';
import 'data/firebase_rota_repository.dart';
import 'navigator_keys.dart';
import 'l10n/app_strings.dart';
import 'screens/rotalink_main_shell.dart';
import 'theme/app_theme.dart';
import 'theme/system_ui.dart';
import 'theme/theme_mode_prefs.dart';

class RotalinkApp extends StatelessWidget {
  const RotalinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModePrefs.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: rotalinkNavigatorKey,
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          locale: const Locale('tr', 'TR'),
          supportedLocales: const [Locale('tr', 'TR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildRotalinkTheme(),
          darkTheme: buildRotalinkDarkTheme(),
          themeMode: themeMode,
          builder: (context, child) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: RotalinkSystemUi.forBrightness(
                Theme.of(context).brightness,
              ),
              child: AdminPopupHost(child: child ?? const SizedBox.shrink()),
            );
          },
          home: const _ConnectivityGate(),
          navigatorObservers: [analyticsObserver],
        );
      },
    );
  }
}

/// Native splash sonrası doğrudan ana ekran; veri arka planda dolar.
class _ConnectivityGate extends StatefulWidget {
  const _ConnectivityGate();

  @override
  State<_ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<_ConnectivityGate> {
  final _repository = FirebaseRotaRepository();
  bool _mainStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      logStartup('ilk kare');
      if (!kIsWeb) FlutterNativeSplash.remove();
      unawaited(
        WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
          if (mounted) _startBackgroundAfterShell();
        }),
      );
    });
  }

  void _startBackgroundAfterShell() {
    if (_mainStarted) return;
    _mainStarted = true;
    unawaited(AppRatingPrefs.incrementLaunchCount());
    unawaited(RotalinkSystemUi.applyEdgeToEdge());
    unawaited(() async {
      await _repository.ensureLocalDataReady();
      logStartup('yerel veri');
      await warmSecondaryData();
      logStartup('ikincil veri');
    }());
  }

  @override
  Widget build(BuildContext context) {
    return RotalinkMainShell(repository: _repository);
  }
}
