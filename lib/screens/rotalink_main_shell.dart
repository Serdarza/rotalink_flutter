import 'dart:async';

import 'package:flutter/material.dart';

import '../data/firebase_rota_repository.dart';
import '../navigation/main_map_nav_bridge.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../navigation/rotalink_shell_scope.dart';
import '../navigator_keys.dart';
import '../onboarding/app_onboarding_controller.dart';
import '../onboarding/app_onboarding_overlay.dart';
import '../onboarding/onboarding_prefs.dart';
import '../widgets/rotalink_glass_bottom_nav.dart';
import 'about_screen.dart';
import 'discover_screen.dart';
import 'holidays_screen.dart';
import 'main_map_screen.dart';
import 'suggestion_screen.dart';

/// Uygulama ana iskeleti — tüm sayfalarda sabit alt menü.
class RotalinkMainShell extends StatefulWidget {
  const RotalinkMainShell({super.key, required this.repository});

  final FirebaseRotaRepository repository;

  @override
  State<RotalinkMainShell> createState() => _RotalinkMainShellState();
}

class _RotalinkMainShellState extends State<RotalinkMainShell> {
  final MainMapNavBridge _navBridge = MainMapNavBridge();
  late final AppOnboardingController _onboarding;
  RotalinkBottomNavItem _selected = RotalinkBottomNavItem.home;

  @override
  void initState() {
    super.initState();
    _onboarding = AppOnboardingController(onEnsureHome: _goHome);
    _onboarding.addListener(_onOnboardingChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeStartOnboarding());
    });
  }

  void _onOnboardingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _maybeStartOnboarding() async {
    if (!await OnboardingPrefs.shouldShow()) return;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _goHome();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    _onboarding.start();
  }

  @override
  void dispose() {
    _onboarding.removeListener(_onOnboardingChanged);
    _onboarding.dispose();
    _navBridge.dispose();
    super.dispose();
  }

  NavigatorState? get _bodyNav => rotalinkShellBodyNavigatorKey.currentState;

  void _goHome() {
    setState(() => _selected = RotalinkBottomNavItem.home);
    _bodyNav?.popUntil((route) => route.isFirst);
    _navBridge.resetToHome?.call();
  }

  void _openFavorites() {
    setState(() => _selected = RotalinkBottomNavItem.favorites);
    _bodyNav?.popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _bodyNav?.context;
      if (ctx != null) {
        unawaited(_navBridge.openFavorites?.call(ctx));
      }
    });
  }

  void _openSearch() {
    _bodyNav?.popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _bodyNav?.context;
      if (ctx != null) {
        unawaited(_navBridge.openSearch?.call(ctx, null));
      }
    });
  }

  void _openRoutePlan() {
    setState(() => _selected = RotalinkBottomNavItem.route);
    _bodyNav?.popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_navBridge.openRoutePlan?.call());
    });
  }

  void _openDiscoverTab() {
    setState(() => _selected = RotalinkBottomNavItem.discover);
    _bodyNav?.pushNamedAndRemoveUntil(
      RotalinkShellRoutes.discover,
      (route) => route.settings.name == RotalinkShellRoutes.home,
    );
  }

  Future<void> _handleShellBack() async {
    if (!mounted) return;

    // Üst sayfa (kampanya detayı, keşfet vb.) → bir adım geri.
    final nav = _bodyNav;
    if (nav != null && nav.canPop()) {
      nav.pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final canStillPop = _bodyNav?.canPop() ?? false;
        if (!canStillPop) {
          setState(() => _selected = RotalinkBottomNavItem.home);
          _navBridge.resetToHome?.call();
        }
      });
      return;
    }

    // Alt menüde ana sayfa dışı sekme seçiliyse → ana harita.
    if (_selected != RotalinkBottomNavItem.home) {
      _goHome();
      return;
    }

    // Ana haritada arama / çift basış çıkış kuralları.
    final handler = _navBridge.handleSystemBack;
    if (handler != null) {
      await handler();
    }
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RotalinkShellRoutes.discover:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => DiscoverScreen(
            embeddedInShell: true,
            showBackButton: false,
          ),
        );
      case RotalinkShellRoutes.about:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const AboutScreen(),
        );
      case RotalinkShellRoutes.holidays:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const HolidaysScreen(),
        );
      case RotalinkShellRoutes.suggestion:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SuggestionScreen(),
        );
      case RotalinkShellRoutes.home:
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => MainMapScreen(
            repository: widget.repository,
            navBridge: _navBridge,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    _navBridge.onRoutePlanningDismissed = () {
      if (!mounted) return;
      setState(() => _selected = RotalinkBottomNavItem.home);
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handleShellBack());
      },
      child: RotalinkShellScope(
        goHome: _goHome,
        onboarding: _onboarding,
        selectTab: (tab) {
          switch (tab) {
            case RotalinkBottomNavItem.home:
              _goHome();
            case RotalinkBottomNavItem.favorites:
              _openFavorites();
            case RotalinkBottomNavItem.search:
              _openSearch();
            case RotalinkBottomNavItem.route:
              _openRoutePlan();
            case RotalinkBottomNavItem.discover:
              _openDiscoverTab();
          }
        },
        child: Stack(
          children: [
            Scaffold(
              resizeToAvoidBottomInset: false,
              body: Navigator(
                key: rotalinkShellBodyNavigatorKey,
                initialRoute: RotalinkShellRoutes.home,
                onGenerateRoute: _onGenerateRoute,
              ),
              bottomNavigationBar: RotalinkGlassBottomNav(
                selected: _selected,
                onHome: _goHome,
                onFavorites: _openFavorites,
                onSearch: _openSearch,
                onRoutePlan: _openRoutePlan,
                onDiscover: _openDiscoverTab,
                navTargetKeys: {
                  OnboardingTarget.navSearch:
                      _onboarding.targetKey(OnboardingTarget.navSearch),
                  OnboardingTarget.navDiscover:
                      _onboarding.targetKey(OnboardingTarget.navDiscover),
                  OnboardingTarget.navRoute:
                      _onboarding.targetKey(OnboardingTarget.navRoute),
                  OnboardingTarget.navFavorites:
                      _onboarding.targetKey(OnboardingTarget.navFavorites),
                },
              ),
            ),
            if (_onboarding.active)
              Positioned.fill(
                child: AppOnboardingOverlay(controller: _onboarding),
              ),
          ],
        ),
      ),
    );
  }
}
