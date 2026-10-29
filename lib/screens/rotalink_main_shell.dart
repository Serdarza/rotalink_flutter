import 'dart:async';

import 'package:flutter/material.dart';

import '../billing/pro_service.dart';
import '../data/firebase_rota_repository.dart';
import '../data/recent_search_store.dart';
import '../data/pro_support_banner_prefs.dart';
import '../deeplink/deep_link_service.dart';
import '../deeplink/deep_link_target.dart';
import '../kami/kami_page.dart';
import '../models/route_plan_outcome.dart';
import '../navigation/main_map_nav_bridge.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../navigation/rotalink_shell_scope.dart';
import '../navigator_keys.dart';
import '../services/campaign_push_service.dart';
import '../theme/system_ui.dart';
import '../widgets/pro_support_banner.dart';
import '../widgets/rotalink_glass_bottom_nav.dart';
import '../widgets/feedback_report_button.dart';
import 'nearby_guesthouses_screen.dart';
import 'location_discovery_screen.dart';
import 'about_screen.dart';
import 'discover_screen.dart';
import 'favorites_hub_screen.dart';
import 'deferred_main_map.dart';
import 'home_dashboard_screen.dart';
import 'holidays_screen.dart';
import 'kis_kesfet_screen.dart';
import 'pro_screen.dart';
import 'search_hub_screen.dart';
import 'settings_screen.dart';
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
  final _feedbackPage = ValueNotifier<String>('/');
  late final _feedbackObserver = _FeedbackPageObserver(_feedbackPage);
  RotalinkBottomNavItem _selected = RotalinkBottomNavItem.home;
  bool _showDashboard = true;
  bool _showSearchHub = false;
  bool _showFavoritesHub = false;
  bool _returnToSearchHubOnSearchBack = false;
  int _surfaceEpoch = 0;

  Timer? _proSupportTimer;
  bool _showProSupportBanner = false;
  bool _proSupportScheduled = false;
  bool _proSupportDelayElapsed = false;

  @override
  void initState() {
    super.initState();
    _navBridge.onDetailVisibilityChanged = () {
      if (mounted) setState(() {});
    };
    _navBridge.onExternalSurfaceChanged = (visible) {
      if (!mounted || _selected != RotalinkBottomNavItem.home) return;
      setState(() {
        _showDashboard = !visible;
        _showSearchHub = false;
        _showFavoritesHub = false;
      });
    };
    ProService.instance.isPro.addListener(_onProChanged);
    DeepLinkService.instance.pending.addListener(_onDeepLink);
    CampaignPushService.openRequests.addListener(_onCampaignNotificationOpen);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleProSupportBanner();
      // Uygulama kapalıyken kampanya bildirimine dokunulduysa istek zaten bekliyordur.
      _onCampaignNotificationOpen();
    });
  }

  /// "Yeni kampanya" bildirimine dokunuldu (kapalı / arka plan / ön plan):
  /// ana sayfa değil, doğrudan Kampanya sekmesi açılır.
  void _onCampaignNotificationOpen() {
    if (!CampaignPushService.hasPendingOpen) return;
    unawaited(_openCampaignsFromNotification());
  }

  Future<void> _openCampaignsFromNotification() async {
    for (var i = 0; i < 60 && mounted && _bodyNav == null; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || _bodyNav == null) return;
    if (!CampaignPushService.consumePendingOpen()) return;
    _openDiscoverTab();
  }

  /// Web linki: içerik ana haritada açılır; alt menü de oraya döner.
  void _onDeepLink() {
    final target = DeepLinkService.instance.pending.value;
    if (!mounted || target == null || target.kind == DeepLinkKind.home) return;
    if (_selected != RotalinkBottomNavItem.home) {
      setState(() {
        _selected = RotalinkBottomNavItem.home;
        _showDashboard = false;
        _showSearchHub = false;
        _showFavoritesHub = false;
      });
    } else if (_showDashboard) {
      setState(() {
        _showDashboard = false;
        _showSearchHub = false;
        _showFavoritesHub = false;
      });
    }
  }

  void _onProChanged() {
    if (!mounted) return;
    if (ProService.instance.hasProAccess && _showProSupportBanner) {
      setState(() => _showProSupportBanner = false);
    }
  }

  void _scheduleProSupportBanner() {
    if (_proSupportScheduled) return;
    _proSupportScheduled = true;
    _proSupportTimer?.cancel();
    _proSupportTimer = Timer(ProSupportBannerPrefs.sessionDelay, () {
      _proSupportDelayElapsed = true;
      unawaited(_tryShowProSupportBanner());
    });
  }

  Future<void> _tryShowProSupportBanner() async {
    if (!mounted || _showProSupportBanner) return;
    if (!_proSupportDelayElapsed) return;
    if (ProService.instance.hasProAccess) return;
    if (await ProSupportBannerPrefs.wasShownToday()) return;
    if (!mounted) return;

    await ProSupportBannerPrefs.markShownToday();
    if (!mounted) return;
    setState(() => _showProSupportBanner = true);
  }

  void _dismissProSupportBanner() {
    if (!_showProSupportBanner) return;
    setState(() => _showProSupportBanner = false);
  }

  void _openProFromSupportBanner() {
    _dismissProSupportBanner();
    unawaited(_openDashboardRoute(RotalinkShellRoutes.pro));
  }

  @override
  void dispose() {
    _proSupportTimer?.cancel();
    ProService.instance.isPro.removeListener(_onProChanged);
    DeepLinkService.instance.pending.removeListener(_onDeepLink);
    CampaignPushService.openRequests.removeListener(
      _onCampaignNotificationOpen,
    );
    _feedbackPage.dispose();
    _navBridge.dispose();
    super.dispose();
  }

  NavigatorState? get _bodyNav => rotalinkShellBodyNavigatorKey.currentState;

  int _bumpSurface() => ++_surfaceEpoch;

  bool _surfaceCurrent(int epoch) => mounted && epoch == _surfaceEpoch;

  /// Ara seçiliyken sonuçsuz kalan eski haritayı kapatır.
  void _returnToSearchHub() {
    if (!mounted || _selected != RotalinkBottomNavItem.search) return;
    if (_navBridge.hasActiveOverlay?.call() ?? false) return;
    if (_showSearchHub) return;
    _bumpSurface();
    setState(() {
      _showDashboard = false;
      _showSearchHub = true;
      _showFavoritesHub = false;
    });
  }

  void _goHome() {
    _bumpSurface();
    _returnToSearchHubOnSearchBack = false;
    unawaited(RotalinkSystemUi.applyEdgeToEdge());
    setState(() {
      _selected = RotalinkBottomNavItem.home;
      _showDashboard = true;
      _showSearchHub = false;
      _showFavoritesHub = false;
    });
    _bodyNav?.popUntil((route) => route.isFirst);
    _navBridge.resetToHome?.call();
  }

  void _openMap() => _openRoutePlan();

  void _openFavorites() {
    _bumpSurface();
    _returnToSearchHubOnSearchBack = false;
    unawaited(RotalinkSystemUi.applyEdgeToEdge());
    setState(() {
      _selected = RotalinkBottomNavItem.favorites;
      _showSearchHub = false;
      _showFavoritesHub = true;
    });
    _bodyNav?.popUntil((route) => route.isFirst);
  }

  void _openFavoritesOnMap() {
    final epoch = _bumpSurface();
    _returnToSearchHubOnSearchBack = false;
    unawaited(RotalinkSystemUi.applyEdgeToEdge());
    unawaited(() async {
      await _ensureMapReady();
      if (!mounted || epoch != _surfaceEpoch) return;
      final ctx = _bodyNav?.context;
      if (ctx == null || !ctx.mounted) return;
      await _navBridge.openFavorites?.call(ctx);
      if (!_surfaceCurrent(epoch)) return;
      setState(() {
        _selected = RotalinkBottomNavItem.favorites;
        _showDashboard = false;
        _showSearchHub = false;
        _showFavoritesHub = false;
      });
    }());
  }

  void _openSearch() {
    _bumpSurface();
    _returnToSearchHubOnSearchBack = false;
    unawaited(RotalinkSystemUi.applyEdgeToEdge());
    setState(() {
      _selected = RotalinkBottomNavItem.search;
      _showSearchHub = true;
      _showFavoritesHub = false;
    });
    _bodyNav?.popUntil((route) => route.isFirst);
  }

  void _submitSearchQuery(String query) {
    unawaited(RecentSearchStore.instance.add(query));
    unawaited(RotalinkSystemUi.applyEdgeToEdge());
    unawaited(
      _openMapSurface(() async {
        final ctx = _bodyNav?.context;
        if (ctx == null) return;
        await _navBridge.openSearchQuery?.call(ctx, query);
      }, selected: RotalinkBottomNavItem.search),
    );
  }

  void _submitSearchHubCityQuery(String query) {
    _returnToSearchHubOnSearchBack = true;
    _submitSearchQuery(query);
  }

  void _openNearbyFromSearchHub() {
    _returnToSearchHubOnSearchBack = false;
    final nav = _bodyNav;
    if (nav == null) return;
    final epoch = _bumpSurface();
    setState(() => _selected = RotalinkBottomNavItem.search);
    unawaited(() async {
      final opened = nav.pushNamed(RotalinkShellRoutes.nearby);
      for (var i = 0; i < 30 && _surfaceCurrent(epoch); i++) {
        if (_currentRouteName(nav) == RotalinkShellRoutes.nearby) break;
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!_surfaceCurrent(epoch)) return;
      if (_currentRouteName(nav) != RotalinkShellRoutes.nearby) return;
      setState(() {
        _showDashboard = false;
        _showSearchHub = false;
        _showFavoritesHub = false;
      });
      await opened;
      if (!_surfaceCurrent(epoch)) return;
      setState(() {
        _selected = RotalinkBottomNavItem.search;
        _showDashboard = false;
        _showSearchHub = true;
        _showFavoritesHub = false;
      });
    }());
  }

  void _openRoutePlan() {
    _returnToSearchHubOnSearchBack = false;
    final epoch = _bumpSurface();
    unawaited(RotalinkSystemUi.applyEdgeToEdge());
    setState(() => _selected = RotalinkBottomNavItem.route);
    // Kampanya açıkken popUntil anasayfayı bir kare gösterir; rota sayfası
    // üst sayfanın yerine konur ([pushOrReplaceOnShellNavigator]).
    unawaited(() async {
      await _ensureMapReady();
      if (!_surfaceCurrent(epoch)) return;
      await _revealAfterRoutePush(
        _bodyNav?.pushNamed(RotalinkShellRoutes.locationDiscovery),
        epoch: epoch,
      );
    }());
  }

  void _openDiscoverTab() {
    _returnToSearchHubOnSearchBack = false;
    final epoch = _bumpSurface();
    unawaited(RotalinkSystemUi.applyEdgeToEdge());
    setState(() => _selected = RotalinkBottomNavItem.discover);
    final nav = _bodyNav;
    if (nav != null && nav.canPop()) {
      // Rota gibi üst sayfa varken önce ana rotaya inmek, geçiş animasyonunda
      // ana ekranı gösterir. Üst sayfanın yerine Kampanya konur.
      nav.pushReplacementNamed(RotalinkShellRoutes.discover);
    } else {
      nav?.pushNamedAndRemoveUntil(
        RotalinkShellRoutes.discover,
        (route) => route.settings.name == RotalinkShellRoutes.home,
      );
    }
    unawaited(_revealAfterRoutePush(null, epoch: epoch));
  }

  Future<void> _openKami() async {
    final outcome = await pushOnRootNavigator<RoutePlanOutcome>(
      MaterialPageRoute<RoutePlanOutcome>(
        builder: (_) => KamiPage(
          repository: widget.repository,
          initialData: widget.repository.currentState,
        ),
      ),
    );
    if (!mounted || outcome == null || outcome.stops.isEmpty) return;
    await _ensureMapReady();
    if (!mounted) return;
    setState(() {
      _showDashboard = false;
      _showSearchHub = false;
      _showFavoritesHub = false;
    });
    await _navBridge.applyRoutePlan?.call(outcome);
  }

  /// Harita ilk kareden sonra ısınır; tuşa basınca köprü hazır olana kadar bekler.
  Future<void> _ensureMapReady() async {
    for (var i = 0; i < 45 && mounted; i++) {
      if (_navBridge.openCategory != null) return;
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Harita sonuçları hazır olana kadar yeni ekranı kapatma.
  Future<void> _openMapSurface(
    Future<void> Function() work, {
    required RotalinkBottomNavItem selected,
  }) async {
    final epoch = _bumpSurface();
    setState(() => _selected = selected);
    _bodyNav?.popUntil((route) => route.isFirst);
    await _ensureMapReady();
    if (!_surfaceCurrent(epoch)) return;
    await work();
    await WidgetsBinding.instance.endOfFrame;
    if (!_surfaceCurrent(epoch)) return;
    final idleOnSearch = selected == RotalinkBottomNavItem.search &&
        !(_navBridge.hasActiveOverlay?.call() ?? false);
    setState(() {
      _showDashboard = false;
      _showFavoritesHub = false;
      _showSearchHub = idleOnSearch;
    });
  }

  /// Tam sayfa rota Navigator'da belirdikten sonra overlay'i kaldır.
  Future<void> _revealAfterRoutePush(
    Future<void>? pending, {
    required int epoch,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    // Sayfa kayma animasyonu bitmeden overlay kalkarsa eski harita görünür.
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!_surfaceCurrent(epoch)) return;
    setState(() {
      _showDashboard = false;
      _showSearchHub = false;
      _showFavoritesHub = false;
    });
    if (pending != null) await pending;
  }

  String? _currentRouteName(NavigatorState nav) {
    String? name;
    nav.popUntil((route) {
      name = route.settings.name;
      return true;
    });
    return name;
  }

  Future<void> _handleShellBack() async {
    if (!mounted) return;

    // Üst sayfa (yorum, karşılaştırma, keşfet vb.) → bir adım geri.
    final nav = _bodyNav;
    if (nav != null && nav.canPop()) {
      final onMap = _currentRouteName(nav) == RotalinkShellRoutes.locationDiscovery;
      if (onMap && LocationDiscoveryScreen.tryConsumeBack?.call() == true) {
        return;
      }
      // Keşfet tam sayfa sekmedir; son rota kapanınca ana menüye dön.
      // Arama/favori/rota harita üstündedir — Yorum/karşılaştır kapanınca
      // listeyi bozma.
      final leavingDiscover = _selected == RotalinkBottomNavItem.discover;
      nav.pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final canStillPop = _bodyNav?.canPop() ?? false;
        if (!canStillPop && leavingDiscover) {
          setState(() {
            _selected = RotalinkBottomNavItem.home;
            _showDashboard = true;
            _showSearchHub = false;
            _showFavoritesHub = false;
          });
          _navBridge.resetToHome?.call();
        }
      });
      return;
    }

    if (_showSearchHub || _showFavoritesHub) {
      _goHome();
      return;
    }

    // Haritada kart / arama listesi / rota varsa önce onları kapat.
    if (!_showDashboard) {
      final overlay = _navBridge.hasActiveOverlay?.call() ?? false;
      if (overlay) {
        final handler = _navBridge.handleSystemBack;
        if (handler != null) {
          await handler();
          if (!mounted) return;
          if (_returnToSearchHubOnSearchBack &&
              !(_navBridge.hasActiveOverlay?.call() ?? false)) {
            _returnToSearchHubOnSearchBack = false;
            setState(() {
              _selected = RotalinkBottomNavItem.search;
              _showDashboard = false;
              _showSearchHub = true;
              _showFavoritesHub = false;
            });
          }
          return;
        }
      }
      _goHome();
      return;
    }

    if (_selected != RotalinkBottomNavItem.home) {
      _goHome();
      return;
    }

    final handler = _navBridge.handleSystemBack;
    if (handler != null) {
      await handler();
    }
  }

  void _openCategory(int tabIndex) {
    _returnToSearchHubOnSearchBack = false;
    unawaited(RotalinkSystemUi.applyEdgeToEdge());
    unawaited(
      _openMapSurface(() async {
        final ctx = _bodyNav?.context;
        if (ctx == null) return;
        await _navBridge.openCategory?.call(ctx, tabIndex);
      }, selected: RotalinkBottomNavItem.search),
    );
  }

  Future<void> _openDashboardRoute(String routeName) async {
    final nav = _bodyNav;
    if (nav == null) return;
    final epoch = _bumpSurface();
    await _revealAfterRoutePush(nav.pushNamed(routeName), epoch: epoch);
    if (!_surfaceCurrent(epoch) || _selected != RotalinkBottomNavItem.home) {
      return;
    }
    if (!mounted || _selected != RotalinkBottomNavItem.home) return;
    setState(() {
      _showDashboard = true;
      _showSearchHub = false;
      _showFavoritesHub = false;
    });
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RotalinkShellRoutes.discover:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              DiscoverScreen(embeddedInShell: true, showBackButton: false),
        );
      case RotalinkShellRoutes.about:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const AboutScreen(),
        );
      case RotalinkShellRoutes.settings:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SettingsScreen(),
        );
      case RotalinkShellRoutes.holidays:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const HolidaysScreen(),
        );
      case RotalinkShellRoutes.nearby:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => NearbyGuesthousesScreen(
            repository: widget.repository,
            onOpenFacility: (facility) => unawaited(
              _openMapSurface(() async {
                await _navBridge.openFacility?.call(context, facility);
              }, selected: RotalinkBottomNavItem.search),
            ),
          ),
        );
      case RotalinkShellRoutes.locationDiscovery:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              LocationDiscoveryScreen(repository: widget.repository),
        );
      case RotalinkShellRoutes.winterDiscover:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const KisKesfetScreen(),
        );
      case RotalinkShellRoutes.suggestion:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SuggestionScreen(),
        );
      case RotalinkShellRoutes.pro:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ProScreen(
            closeWhenPurchased: settings.arguments == true,
          ),
        );
      case RotalinkShellRoutes.home:
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => DeferredMainMap(
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
      // Başka sekmeye geçildiyse rota sayfası da kapanır; bunu ana sayfaya
      // dönüş sayma. Aksi halde Kampanya açılırken ana ekran bir an görünür.
      if (_selected != RotalinkBottomNavItem.route) return;
      setState(() {
        _selected = RotalinkBottomNavItem.home;
        _showDashboard = true;
        _showSearchHub = false;
        _showFavoritesHub = false;
      });
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handleShellBack());
      },
      child: RotalinkShellScope(
        goHome: _goHome,
        returnToSearchHub: _returnToSearchHub,
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
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.endFloat,
              floatingActionButton:
                  MediaQuery.viewInsetsOf(context).bottom > 0 ||
                      (_feedbackPage.value == RotalinkShellRoutes.home &&
                          !_showDashboard &&
                          !_showSearchHub &&
                          !_showFavoritesHub &&
                          (_navBridge.isFacilityDetailOpen?.call() ?? false))
                  ? null
                  : ValueListenableBuilder<String>(
                      valueListenable: _feedbackPage,
                      builder: (context, page, _) => page == 'konum-facility'
                          ? const SizedBox.shrink()
                          : FeedbackReportButton(
                        sourcePage: _showDashboard
                            ? 'Ana Sayfa'
                            : _showSearchHub
                            ? 'Ara'
                            : _showFavoritesHub
                            ? 'Favorilerim'
                            : page == '/'
                            ? _selected.name
                            : page,
                        facility:
                            !_showDashboard &&
                                !_showSearchHub &&
                                !_showFavoritesHub &&
                                page == '/'
                            ? () => _navBridge.feedbackFacility?.call()
                            : null,
                      ),
                    ),
              body: Stack(
                children: [
                  Navigator(
                    key: rotalinkShellBodyNavigatorKey,
                    initialRoute: RotalinkShellRoutes.home,
                    onGenerateRoute: _onGenerateRoute,
                    observers: [_feedbackObserver],
                  ),
                  if (_showDashboard)
                    Positioned.fill(
                      child: HomeDashboardScreen(
                        repository: widget.repository,
                        onOpenMap: _openMap,
                        onOpenSearch: _openSearch,
                        onSubmitQuery: _submitSearchQuery,
                        onOpenCategory: _openCategory,
                        onOpenFavorites: _openFavorites,
                        onOpenRoutePlan: _openRoutePlan,
                        onOpenDiscover: _openDiscoverTab,
                        onOpenNamedRoute: (route) =>
                            unawaited(_openDashboardRoute(route)),
                        onOpenKami: () => unawaited(_openKami()),
                      ),
                    ),
                  if (_showSearchHub)
                    Positioned.fill(
                      child: SearchHubScreen(
                        repository: widget.repository,
                        onBack: _goHome,
                        onQuery: _submitSearchQuery,
                        onCitySelected: _submitSearchHubCityQuery,
                        onNearby: _openNearbyFromSearchHub,
                      ),
                    ),
                  if (_showFavoritesHub)
                    Positioned.fill(
                      child: FavoritesHubScreen(
                        onBack: _goHome,
                        onOpenMap: _openFavoritesOnMap,
                        onExplore: _openMap,
                      ),
                    ),
                ],
              ),
              bottomNavigationBar: RotalinkGlassBottomNav(
                selected: _selected,
                onHome: _goHome,
                onFavorites: _openFavorites,
                onSearch: _openSearch,
                onRoutePlan: _openRoutePlan,
                onDiscover: _openDiscoverTab,
              ),
            ),
            if (_showProSupportBanner)
              Positioned.fill(
                child: ProSupportBanner(
                  onOpenPro: _openProFromSupportBanner,
                  onDismiss: _dismissProSupportBanner,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackPageObserver extends NavigatorObserver {
  _FeedbackPageObserver(this.page);
  final ValueNotifier<String> page;
  bool _scheduled = false;
  String _latest = '/';
  void _update(Route<dynamic>? route) {
    _latest = route == null ? '/' : route.settings.name ?? '/sayfa';
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (navigator?.mounted ?? false) page.value = _latest;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _update(newRoute);
}
