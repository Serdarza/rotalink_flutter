import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
// ignore: implementation_imports — [PopupEvent] public export yok.
import 'package:flutter_map_marker_popup/src/state/popup_event.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads/ad_service.dart';
import '../data/app_rating_prefs.dart';
import '../data/favorites_repository.dart';
import '../data/firebase_rota_repository.dart';
import '../data/history_repository.dart';
import '../data/saved_routes_repository.dart';
import '../data/user_location_cache.dart';
import '../l10n/app_strings.dart';
import '../map_location_state.dart';
import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
import '../models/route_plan_outcome.dart';
import '../models/route_stop.dart';
import '../services/osrm_route_service.dart';
import '../services/holiday_notification_scheduler.dart';
import '../services/simple_location_service.dart';
import '../theme/app_colors.dart';
import '../utils/geo_helpers.dart';
import '../utils/maps_launch.dart';
import '../utils/misafirhane_compact_sheet_height.dart';
import '../utils/route_facility_lookup.dart';
import '../utils/safe_map_coordinates.dart';
import '../utils/main_map_search.dart';
import '../widgets/app_rating_dialog.dart';
import '../widgets/distance_permission_chip.dart';
import '../widgets/emergency_bottom_sheet.dart';
import '../widgets/custom_search_bar.dart';
import '../widgets/map_facility_preview_card.dart';
import '../widgets/misafirhane_map_marker.dart';
import '../widgets/misafirhane_marker_info_popup.dart';
import '../widgets/misafirhane_search_results_sheet.dart';
import '../widgets/rotalink_banner_ad.dart';
import '../widgets/weather_bottom_sheet.dart';
import '../services/review_repository.dart';
import 'about_screen.dart';
import 'discover_screen.dart';
import 'holidays_screen.dart';
import 'route_plan_screen.dart';
import 'suggestion_screen.dart';
import 'yorum_screen.dart';

/// Yüksek doğruluk istemez; aksi halde Google Play "Konum doğruluğu" penceresi sık tetiklenir.
const _kRotalinkLocationSettingsLow = LocationSettings(
  accuracy: LocationAccuracy.low,
  timeLimit: Duration(seconds: 15),
);

/// Canlı konum akışı: pil tasarrufu için düşük doğruluk + 50 metre eşliği.
const _kLocationStreamSettings = LocationSettings(
  accuracy: LocationAccuracy.low,
  distanceFilter: 50,
);

/// `activity_main.xml` + `MainActivity` ana iskeleti: çekmece, teal toolbar,
/// harita alanı, arama kartı, FAB’lar, banner alanı, alt gezinme çubuğu.
class MainMapScreen extends StatefulWidget {
  const MainMapScreen({super.key, required this.repository});

  final FirebaseRotaRepository repository;

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _mapController = MapController();
  final PopupController _popupController = PopupController();
  final TextEditingController _searchController = TextEditingController();

  LatLng _center = kTurkeyMapFallbackCenter;
  double _zoom = kTurkeyMapFallbackZoom;

  /// Açılışta bir kez tam Türkiye görünümü (padding: arama / alt çubuk).
  bool _initialTurkeyBoundsApplied = false;
  String _versionLabel = '—';

  /// Kotlin `filteredMisafirhaneList` / `lastSearchMisafirhaneList`; `null` = ana ekran (RTDB `misafirhaneler`).
  List<Misafirhane>? _markerOverride;

  /// Kotlin `currentRouteStops` + OSRM polyline.
  List<RouteStop>? _activeRouteStops;
  List<Polyline<Object>> _routePolylines = const [];
  List<Marker> _routeLabelMarkers = const [];
  double? _routeSummaryDistanceM;
  double? _routeSummaryDurationS;
  int _routeLoadGen = 0;
  RotaDataState? _cachedRotaData;

  final SavedRoutesRepository _savedRoutes = SavedRoutesRepository();
  final FavoritesRepository _favoritesRepo = FavoritesRepository();
  final HistoryRepository _historyRepo = HistoryRepository();

  /// Kotlin `loadListFromPrefs("favorites")`.
  List<Misafirhane> _favoritesCache = const [];

  /// Kotlin `loadListFromPrefs("history")`.
  List<Misafirhane> _historyCache = const [];

  /// Kotlin `isShowingFavorites` — harita işaretleri favori listesinden gelir.
  bool _favoritesBrowseActive = false;

  /// Kotlin `isShowingHistory`.
  bool _historyBrowseActive = false;

  /// Marker seçiminde altta gösterilen önizleme kartı.
  Misafirhane? _mapPreviewFacility;

  /// Önizleme kapanırken kısa çıkış animasyonu (harita kaydırma / dokunuş ile tetiklenir).
  bool _previewClosing = false;

  /// Ana haritada misafirhane marker bilgi balonu açık mı ([PopupMarkerLayer]).
  bool _misafirhaneFacilityPopupOpen = false;

  StreamSubscription<MapEvent>? _mapPreviewDismissSub;

  /// Arama sonucu listesinde kaydırılacak tesis (FAB ile sheet açılınca kullanılır).
  Misafirhane? _searchSheetHighlight;

  /// [showBottomSheet] ile açılan kalıcı alt sayfa — modal bariyer yok; yenisi açılmadan kapatılır.
  PersistentBottomSheetController? _attachedBottomSheet;

  /// Arama sonucu sekmeli panel ([DraggableScrollableSheet]) görünür mü.
  bool isSheetVisible = true;

  /// Geri tuşu: önce paneli gizle → tekrar aç + çıkış hazır → ana ekran sıfırlama.
  bool readyToExit = false;

  /// Yalnızca açık arama sonuçları paneline bağlı; her açılışta yenilenir.
  DraggableScrollableController? _searchSheetExtentController;

  /// Arama sonuçları (Tesis/Gezi/…) paneli harita [Stack] içinde — Scaffold bottom sheet değil.
  bool _inlineTabbedSearchOpen = false;
  List<Misafirhane> _tabbedSheetFacilities = const [];
  RotaDataState? _tabbedSheetRotaData;
  Misafirhane? _tabbedSheetHighlight;

  /// [MainMapSearchBar] için ana ekrana dönüşte arama çubuğu state’ini sıfırlamak.
  int _searchBarSession = 0;

  DateTime? _lastExitBackAt;

  /// Yalnızca Konumum FAB başarısından sonra gösterilen kullanıcı pini (sürekli takip yok).
  LatLng? _userLocationLatLng;

  /// Kullanıcı sistem Ayarlar / GPS ayarlarına yönlendirildi.
  /// Uygulama ön plana döndüğünde ([didChangeAppLifecycleState]) konum kontrolü yapılır.
  bool _pendingLocationCheckAfterSettings = false;

  /// Kullanıcı konumu değiştikçe mesafeleri güncelleyen sürekli GPS akışı.
  StreamSubscription<Position>? _locationStreamSub;

  /// Arama / favori / geçmiş mesafe satırları için paylaşılan konum durumu.
  final MapLocationState _mapLocationState = MapLocationState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    PackageInfo.fromPlatform().then((p) {
      if (mounted) {
        setState(() => _versionLabel = '${p.version}+${p.buildNumber}');
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AdService.adsEnabled) {
        unawaited(AdService.instance.scheduleLaunchInterstitialPattern());
      }
      unawaited(_maybeOpenHolidaysFromNotification());
    });
    unawaited(_reloadFavoritesCache());
    unawaited(_reloadHistoryCache());
    _mapPreviewDismissSub = _mapController.mapEventStream.listen(_onMapControllerEvent);
    unawaited(_syncLocationUiFromPermissionOnly());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _stopLocationStream(); // Arka planda stream durdur — pil tasarrufu
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshLocationStateOnResume());
      unawaited(HolidayNotificationScheduler.scheduleUpcomingHolidayReminders());
      unawaited(_maybeOpenHolidaysFromNotification());
    }
  }

  // ─── Konum stream yönetimi ──────────────────────────────────────────────────

  /// İzin ve GPS varsa sürekli konum güncellemesi başlatır.
  /// Her 50 metrede bir [_mapLocationState] güncellenir → listeler yeniden çizilir.
  void _startLocationStream() {
    _locationStreamSub?.cancel();
    _locationStreamSub = Geolocator.getPositionStream(
      locationSettings: _kLocationStreamSettings,
    ).listen(
      (pos) {
        if (!mounted) return;
        if (!isValidWgs84LatLng(pos.latitude, pos.longitude)) return;
        final ll = LatLng(pos.latitude, pos.longitude);
        _userLocationLatLng = ll;
        unawaited(UserLocationCache.save(ll));
        _mapLocationState.update(ll, true);
      },
      onError: (_) => _stopLocationStream(),
      cancelOnError: false,
    );
  }

  void _stopLocationStream() {
    _locationStreamSub?.cancel();
    _locationStreamSub = null;
  }

  Future<void> _maybeOpenHolidaysFromNotification() async {
    final open = await HolidayNotificationScheduler.consumePendingOpenHolidaysNavigation();
    if (!open || !mounted || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const HolidaysScreen()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLocationStream();
    _dismissAttachedBottomSheet();
    _disposeSearchSheetExtentController();
    _mapPreviewDismissSub?.cancel();
    AdService.instance.cancelLaunchInterstitialTimer();
    _searchController.dispose();
    _popupController.dispose();
    _mapLocationState.dispose();
    super.dispose();
  }

  void _disposeSearchSheetExtentController() {
    final c = _searchSheetExtentController;
    if (c == null) return;
    c.removeListener(_onSearchSheetExtentChanged);
    _searchSheetExtentController = null;
    try {
      c.dispose();
    } catch (_) {}
  }

  /// Önceki sheet kapandıktan sonra çağrılmalı. Her sheet için tek kullanımlık denetleyici.
  DraggableScrollableController _allocateSearchSheetExtentController() {
    _disposeSearchSheetExtentController();
    final c = DraggableScrollableController();
    c.addListener(_onSearchSheetExtentChanged);
    _searchSheetExtentController = c;
    return c;
  }

  void _onSearchSheetExtentChanged() {
    if (!mounted) return;
    final c = _searchSheetExtentController;
    if (c == null || !c.isAttached) return;
    final visible = c.size > 0.06;
    if (visible != isSheetVisible) {
      setState(() => isSheetVisible = visible);
    }
  }

  Future<void> _collapseSearchResultsSheet() async {
    final c = _searchSheetExtentController;
    if (c == null || !c.isAttached) return;
    await c.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _expandSearchResultsSheet() async {
    final c = _searchSheetExtentController;
    if (c == null || !c.isAttached) return;
    await c.animateTo(
      kMisafirhaneSearchSheetOpenExtent,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _handleSearchSheetBackNavigation() async {
    if (!mounted) return;
    final c = _searchSheetExtentController;

    if (isSheetVisible && !readyToExit) {
      await _collapseSearchResultsSheet();
      if (mounted) setState(() => isSheetVisible = false);
      return;
    }
    if (!isSheetVisible) {
      if (c != null && c.isAttached) {
        await _expandSearchResultsSheet();
        if (mounted) {
          setState(() {
            isSheetVisible = true;
            readyToExit = true;
          });
        }
      } else {
        final data = _cachedRotaData;
        final facilities = _markerOverride;
        if (data != null && facilities != null && facilities.isNotEmpty) {
          await _openTabbedSearchResults(
            context,
            data,
            facilities,
            highlightTarget: _searchSheetHighlight,
            reopenNextBackExitsSearch: true,
          );
        } else if (mounted) {
          resetToInitialState();
        }
      }
      return;
    }
    if (isSheetVisible && readyToExit) {
      resetToInitialState();
    }
  }

  /// Ana harita ilk açılış / arama sıfırlandı (Geri tuşu 3. adım).
  void resetToInitialState() {
    if (!mounted) return;
    _popupController.hideAllPopups();
    _dismissAttachedBottomSheet();
    FocusManager.instance.primaryFocus?.unfocus();
    _searchController.clear();
    setState(() {
      readyToExit = false;
      isSheetVisible = true;
      _markerOverride = null;
      _searchSheetHighlight = null;
      _mapPreviewFacility = null;
      _favoritesBrowseActive = false;
      _historyBrowseActive = false;
      _clearRouteOnly();
    });
    setState(() => _searchBarSession++);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitTurkeyOverviewCamera();
    });
  }

  void _closeInlineTabbedSearchPanel() {
    if (!_inlineTabbedSearchOpen) return;
    setState(() {
      _inlineTabbedSearchOpen = false;
      _tabbedSheetFacilities = const [];
      _tabbedSheetRotaData = null;
      _tabbedSheetHighlight = null;
    });
    _disposeSearchSheetExtentController();
  }

  void _dismissAttachedBottomSheet() {
    _closeInlineTabbedSearchPanel();
    final c = _attachedBottomSheet;
    if (c == null) return;
    _attachedBottomSheet = null;
    try {
      c.close();
    } catch (_) {}
  }

  void _onMapControllerEvent(MapEvent e) {
    _onMapEventForPreview(e);
  }

  void _onMapEventForPreview(MapEvent e) {
    if (_mapPreviewFacility == null) return;
    if (_shouldDismissPreviewForMapEvent(e)) {
      unawaited(_closeMapPreviewAnimated());
      return;
    }
    if (mounted) setState(() {});
  }

  bool _shouldDismissPreviewForMapEvent(MapEvent e) {
    if (e is MapEventMove) {
      return e.source == MapEventSource.onDrag || e.source == MapEventSource.onMultiFinger;
    }
    if (e is MapEventFlingAnimation) return true;
    if (e is MapEventDoubleTapZoom) return true;
    if (e is MapEventScrollWheelZoom) return true;
    return false;
  }

  Future<void> _closeMapPreviewAnimated() async {
    if (_mapPreviewFacility == null || _previewClosing) return;
    setState(() => _previewClosing = true);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() {
      _mapPreviewFacility = null;
      _previewClosing = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreCameraAfterPreviewClose();
    });
  }

  void _onMainSearchCleared() {
    if (!mounted) return;
    _popupController.hideAllPopups();
    _dismissAttachedBottomSheet();
    setState(() {
      readyToExit = false;
      isSheetVisible = true;
      _mapPreviewFacility = null;
      _markerOverride = null;
      _favoritesBrowseActive = false;
      _historyBrowseActive = false;
      _searchSheetHighlight = null;
      _clearRouteOnly();
    });
  }

  /// Arama çubuğu metni ve odak — harita durumundan bağımsız UI sıfırlama.
  void resetSearchState() {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    setState(() => _searchBarSession++);
  }

  /// Türkiye ana haritası: arama + filtre + rota + önizleme temiz; çubuk ilk açılış gibi.
  void _goToInitialMapHome() {
    if (!mounted) return;
    _popupController.hideAllPopups();
    _dismissAttachedBottomSheet();
    setState(() {
      readyToExit = false;
      isSheetVisible = true;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    } else {
      _onMainSearchCleared();
      setState(() => _searchBarSession++);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitTurkeyOverviewCamera();
      });
    }
  }

  void _clearRouteOnly() {
    _routeLoadGen++;
    _activeRouteStops = null;
    _routePolylines = const [];
    _routeLabelMarkers = const [];
    _routeSummaryDistanceM = null;
    _routeSummaryDurationS = null;
  }

  /// Türkiye ana kara + margin; SW/NE köşeleri [CameraFit] ile sığdırılır.
  void _fitTurkeyOverviewCamera() {
    const sw = LatLng(35.58, 25.72);
    const ne = LatLng(42.4, 44.92);
    try {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: [sw, ne],
          padding: const EdgeInsets.fromLTRB(8, 96, 8, 156),
        ),
      );
    } catch (_) {
      try {
        _mapController.move(kTurkeyMapFallbackCenter, kTurkeyMapFallbackZoom);
      } catch (_) {}
    }
  }

  bool _validFacilityCoords(Misafirhane m) =>
      m.latitude != 0 &&
      m.longitude != 0 &&
      isValidWgs84LatLng(m.latitude, m.longitude);

  /// [CameraFit.coordinates] tek benzersiz noktada (veya tüm noktalar aynı yerde) sınır
  /// genişliği 0 olunca zoom NaN/sonsuz üretebiliyor; harita çizilemiyor.
  void _fitLatLngsOrMoveCamera(
    List<LatLng> raw, {
    EdgeInsets padding = const EdgeInsets.fromLTRB(48, 120, 48, 100),
    double singlePointZoom = 12,
  }) {
    final pts = onlyValidLatLngs(raw);
    final z = clampZoom(singlePointZoom);
    if (pts.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(kTurkeyMapFallbackCenter, kTurkeyMapFallbackZoom);
        } catch (_) {}
      });
      return;
    }
    final distinct = pts.toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (distinct.length == 1) {
          _mapController.move(distinct.first, z);
          return;
        }
        _mapController.fitCamera(
          CameraFit.coordinates(coordinates: pts, padding: padding),
        );
      } catch (_) {
        try {
          _mapController.move(pts.first, z);
        } catch (_) {
          try {
            _mapController.move(kTurkeyMapFallbackCenter, kTurkeyMapFallbackZoom);
          } catch (_) {}
        }
      }
    });
  }

  List<Misafirhane> _markersSource(RotaDataState? snapshotData) {
    final effective = (snapshotData != null && snapshotData.errorMessage != null)
        ? _cachedRotaData
        : (snapshotData ?? _cachedRotaData);
    if (_historyBrowseActive) {
      return _resolveSavedAgainstLive(_historyCache, effective);
    }
    if (_favoritesBrowseActive) {
      return _resolveSavedAgainstLive(_favoritesCache, effective);
    }
    if (effective == null) return const [];
    return _markerOverride ?? effective.misafirhaneler;
  }

  Future<void> _reloadFavoritesCache() async {
    final list = await _favoritesRepo.load();
    if (!mounted) return;
    setState(() => _favoritesCache = list);
  }

  Future<void> _reloadHistoryCache() async {
    final list = await _historyRepo.load();
    if (!mounted) return;
    setState(() => _historyCache = list);
  }

  Future<void> _recordHistoryVisit(Misafirhane m) async {
    final list = await _historyRepo.recordVisit(m);
    if (!mounted) return;
    setState(() => _historyCache = list);
  }

  List<Marker> _misafirhaneMapMarkers(
    List<Misafirhane> list,
    Misafirhane? primaryHighlight,
  ) {
    final hl = primaryHighlight;
    // Aynı stableFacilityId'ye sahip tekrarlı tesisleri filtrele;
    // aksi hâlde PopupMarkerLayer "Duplicate keys" hatasıyla çöker.
    final seen = <String>{};
    return list
        .where(_validFacilityCoords)
        .where((m) => seen.add(m.stableFacilityId))
        .map(
          (m) => MisafirhaneMapMarker(
            misafirhane: m,
            primaryHighlight: hl != null && m.sameFavoriteIdentity(hl),
          ),
        )
        .toList();
  }

  void _onMisafirhanePopupEvent(PopupEvent event, List<Marker> selectedMarkers) {
    _misafirhaneFacilityPopupOpen =
        selectedMarkers.any((m) => m is MisafirhaneMapMarker);
    for (final m in selectedMarkers) {
      if (m is MisafirhaneMapMarker) {
        unawaited(_recordHistoryVisit(m.misafirhane));
        unawaited(_animateTowardsMisafirhane(m.misafirhane));
      }
    }
    if (selectedMarkers.isNotEmpty && mounted && _mapPreviewFacility != null) {
      setState(() => _mapPreviewFacility = null);
    }
  }

  void _showMisafirhanePopupFor(Misafirhane m) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hl = _searchSheetHighlight;
      _popupController.showPopupsOnlyFor([
        MisafirhaneMapMarker(
          misafirhane: m,
          primaryHighlight: hl != null && m.sameFavoriteIdentity(hl),
        ),
      ]);
    });
  }

  Future<void> _animateTowardsMisafirhane(Misafirhane m) async {
    if (!_validFacilityCoords(m)) return;
    final c = latLngOrFallback(m.latitude, m.longitude);
    try {
      // Kotlin [centerMapOnMarker]: zoom ~17
      _mapController.move(c, 15);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      _mapController.move(c, 17);
    } catch (_) {}
  }

  void _restoreCameraAfterPreviewClose() {
    if (!mounted) return;
    if (_markerOverride != null && _markerOverride!.isNotEmpty) {
      _fitFacilitiesCamera(_markerOverride!);
      return;
    }
    if (_favoritesBrowseActive || _historyBrowseActive) {
      final data = _cachedRotaData;
      final src = _markersSource(data);
      if (src.isNotEmpty) {
        _fitFacilitiesCamera(src);
      }
      return;
    }
    _fitTurkeyOverviewCamera();
  }

  Future<void> _handleSystemBack() async {
    if (!mounted) return;

    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }

    if (_mapPreviewFacility != null) {
      if (_previewClosing) return;
      unawaited(_closeMapPreviewAnimated());
      return;
    }

    if (_misafirhaneFacilityPopupOpen) {
      _popupController.hideAllPopups();
      _lastExitBackAt = null;
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreCameraAfterPreviewClose();
      });
      return;
    }

    if (_markerOverride != null) {
      await _handleSearchSheetBackNavigation();
      return;
    }

    if (_attachedBottomSheet != null) {
      _dismissAttachedBottomSheet();
      return;
    }

    if (_favoritesBrowseActive || _historyBrowseActive) {
      setState(() {
        _favoritesBrowseActive = false;
        _historyBrowseActive = false;
        _mapPreviewFacility = null;
      });
      _goToInitialMapHome();
      return;
    }

    if (_activeRouteStops != null && _activeRouteStops!.isNotEmpty) {
      _goToInitialMapHome();
      return;
    }

    await _handleDoubleBackExit();
  }

  Future<void> _handleDoubleBackExit() async {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastExitBackAt != null &&
        now.difference(_lastExitBackAt!) < const Duration(seconds: 2)) {
      _lastExitBackAt = null;
      if (await AppRatingPrefs.getHasRated()) {
        if (mounted) SystemNavigator.pop();
        return;
      }
      if (await AppRatingPrefs.shouldPromptRatingBeforeExit()) {
        if (context.mounted) {
          await showAppRatingDialog(context);
        }
      }
      if (mounted) SystemNavigator.pop();
    } else {
      _lastExitBackAt = now;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Çıkmak için tekrar geri tuşuna basın'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Kayıtlı sırayı (favori / geçmiş) canlı RTDB ile eşleştirip güncel konumu tercih eder.
  List<Misafirhane> _resolveSavedAgainstLive(
    List<Misafirhane> savedOrdered,
    RotaDataState? data,
  ) {
    if (savedOrdered.isEmpty) return const [];
    if (data == null) return List<Misafirhane>.from(savedOrdered);
    final kaynak = MainMapSearch.tesisKaynagiArama(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    final live = <Misafirhane>[...data.misafirhaneler, ...kaynak];
    return savedOrdered.map((f) {
      for (final m in live) {
        if (m.sameFavoriteIdentity(f)) return m;
      }
      return f;
    }).toList();
  }

  void _fitFacilitiesCamera(List<Misafirhane> list) {
    final pts = list
        .where(_validFacilityCoords)
        .map((m) => LatLng(m.latitude, m.longitude))
        .toList();
    _fitLatLngsOrMoveCamera(pts);
  }

  Future<void> _openFavoritesTab(BuildContext context) async {
    await _reloadFavoritesCache();
    if (!mounted || !context.mounted) return;
    if (_favoritesCache.isEmpty) {
      _toast(context, AppStrings.favoritesEmpty);
      return;
    }
    final display = _resolveSavedAgainstLive(_favoritesCache, _cachedRotaData);
    if (!display.any(_validFacilityCoords)) {
      _toast(context, AppStrings.mapDataLoading);
      return;
    }
    _popupController.hideAllPopups();
    if (_inlineTabbedSearchOpen) {
      _disposeSearchSheetExtentController();
    }
    setState(() {
      _inlineTabbedSearchOpen = false;
      _tabbedSheetFacilities = const [];
      _tabbedSheetRotaData = null;
      _tabbedSheetHighlight = null;
      _favoritesBrowseActive = true;
      _historyBrowseActive = false;
      _markerOverride = null;
      _searchSheetHighlight = null;
      _clearRouteOnly();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.mounted) return;
      _fitFacilitiesCamera(display);
      _openMisafirhaneSheet(
        display,
        liveFavoriteList: true,
      );
    });
  }

  Future<void> _openHistoryTab(BuildContext context) async {
    await _reloadHistoryCache();
    if (!mounted || !context.mounted) return;
    final display = _resolveSavedAgainstLive(_historyCache, _cachedRotaData);
    if (!display.any(_validFacilityCoords)) {
      _toast(context, AppStrings.mapDataLoading);
      return;
    }
    _popupController.hideAllPopups();
    if (_inlineTabbedSearchOpen) {
      _disposeSearchSheetExtentController();
    }
    setState(() {
      _inlineTabbedSearchOpen = false;
      _tabbedSheetFacilities = const [];
      _tabbedSheetRotaData = null;
      _tabbedSheetHighlight = null;
      _historyBrowseActive = true;
      _favoritesBrowseActive = false;
      _markerOverride = null;
      _searchSheetHighlight = null;
      _clearRouteOnly();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.mounted) return;
      if (display.isNotEmpty) {
        _fitFacilitiesCamera(display);
      }
      _openMisafirhaneSheet(
        display,
        liveHistoryList: true,
      );
    });
  }

  /// Arama sırasında [Geolocator] çağrılmaz; yalnızca izin bayrağı + önbellekteki pin UI’a yansır.
  Future<void> _prepareLocationForSearch() async {
    try {
      if (!mounted) return;
      await _syncLocationUiFromPermissionOnly();
    } catch (e, st) {
      debugPrint('Konum (arama hazırlık): $e\n$st');
    }
  }

  /// Uygulama ön plana gelince: izin/GPS kontrolü + stream yönetimi.
  Future<void> _refreshLocationStateOnResume() async {
    if (!mounted) return;
    try {
      final granted = await Permission.locationWhenInUse.isGranted;
      if (granted) {
        await SimpleLocationService.prepareForUserInitiatedPermissionDialog();
      }
      if (!mounted) return;

      final gpsOn = await Geolocator.isLocationServiceEnabled();

      // Kullanıcı Ayarlar / GPS ekranından döndü mü?
      if (_pendingLocationCheckAfterSettings) {
        _pendingLocationCheckAfterSettings = false;
        if (gpsOn && granted) {
          await _applyLocationAfterPermissionGranted(); // konum al + stream başlat
          await _reopenSearchSheetIfLocationGranted();
          return;
        }
      }

      // GPS kapandıysa stream durdur.
      if (!gpsOn || !granted) _stopLocationStream();

      // GPS ve izin varsa ama stream yoksa yeniden başlat.
      if (gpsOn && granted && _locationStreamSub == null) {
        _startLocationStream();
      }

      await _syncLocationUiFromPermissionOnly();
    } catch (e, st) {
      debugPrint('Konum (resume): $e\n$st');
    }
  }

  /// Çizim / StreamBuilder zincirinde [Geolocator] yok; izin + GPS + önbellekten konum.
  ///
  /// GPS kapalıyken önbellek yüklenmez: eski konumdan hesaplanan mesafe gösterilmez.
  Future<void> _syncLocationUiFromPermissionOnly() async {
    if (!mounted) return;
    try {
      final granted = await Permission.locationWhenInUse.isGranted;
      if (!mounted) return;
      if (!granted) {
        await UserLocationCache.clear();
        _userLocationLatLng = null;
      } else if (_userLocationLatLng == null ||
          !isValidWgs84LatLng(
            _userLocationLatLng!.latitude,
            _userLocationLatLng!.longitude,
          )) {
        // GPS kapalıyken eski önbellek yüklenmez; aksi halde eski mesafe görünür.
        final gpsOn = await Geolocator.isLocationServiceEnabled();
        if (!mounted) return;
        if (gpsOn) {
          final cached = await UserLocationCache.load();
          if (!mounted) return;
          if (cached != null) _userLocationLatLng = cached;
        } else {
          _userLocationLatLng = null;
        }
      }
      if (!mounted) return;
      _mapLocationState.update(_userLocationLatLng, granted);
      setState(() {});
    } catch (e, st) {
      debugPrint('Konum (UI senkron): $e\n$st');
    }
  }

  /// Mesafe satırı chip dokunuşu: GPS → İzin → Kalıcı Red → Ayarlar zinciri.
  Future<void> _onSearchSheetRequestLocation() async {
    await _handleChipTapLocationRequest();
  }

  /// Chip dokunuşunda tam akış:
  ///   1. İzin → OS diyalog (veya kalıcı redde Ayarlar)
  ///   2. İzin verildi ama GPS kapalı → GPS ayarları
  ///   3. Her ikisi hazır → konum al + stream başlat
  Future<void> _handleChipTapLocationRequest() async {
    // 1. İzin önce: OS izin diyalogı (kalıcı redde openAppSettings).
    final outcome = await SimpleLocationService.requestFromUserTap();
    if (!mounted) return;

    switch (outcome) {
      case PermissionRequestOutcome.openedSettings:
        _pendingLocationCheckAfterSettings = true;
        return;
      case PermissionRequestOutcome.denied:
        return;
      case PermissionRequestOutcome.granted:
        break;
    }

    // 2. İzin verildi — GPS kontrolü.
    final gpsOn = await Geolocator.isLocationServiceEnabled();
    if (!gpsOn) {
      _pendingLocationCheckAfterSettings = true;
      await Geolocator.openLocationSettings();
      return;
    }

    // 3. Her ikisi hazır → konum al + stream.
    await _applyLocationAfterPermissionGranted();
    await _reopenSearchSheetIfLocationGranted();
  }

  Future<void> _applyLocationAfterPermissionGranted() async {
    if (SimpleLocationService.shouldSuppressPlayServicesLocationActivity) {
      _stopLocationStream();
      if (mounted) {
        _toast(context, AppStrings.locationServicesOffSnack);
      }
      await _syncLocationUiFromPermissionOnly();
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: _kRotalinkLocationSettingsLow,
      );
      if (!mounted) return;
      if (isValidWgs84LatLng(pos.latitude, pos.longitude)) {
        final ll = LatLng(pos.latitude, pos.longitude);
        _userLocationLatLng = ll;
        unawaited(UserLocationCache.save(ll));
        _startLocationStream(); // Konum alındı → sürekli güncelleme başlat
      }
    } catch (_) {
      SimpleLocationService.markSessionPlayServicesLocationPromptDeclined();
      _stopLocationStream();
      if (mounted) {
        _toast(context, AppStrings.locationServicesOffSnack);
      }
    }
    await _syncLocationUiFromPermissionOnly();
  }

  Future<void> _ensureLocationPermissionAndLocationForLists({
    bool fromDistanceChip = false,
  }) async {
    // Kural 2: İzin + GPS var → sessizce hesapla.
    if (await Permission.locationWhenInUse.isGranted &&
        await Geolocator.isLocationServiceEnabled()) {
      await _applyLocationAfterPermissionGranted();
      await _reopenSearchSheetIfLocationGranted();
      return;
    }

    // Chip dokunuşu: GPS → İzin → Ayarlar tam zinciri.
    if (fromDistanceChip) {
      await _handleChipTapLocationRequest();
      return;
    }

    // Otomatik tetik (arama vb.): İzin var ama GPS kapalı → bu oturumda bir kez GPS ekranı aç.
    if (await Permission.locationWhenInUse.isGranted &&
        !await Geolocator.isLocationServiceEnabled() &&
        !_pendingLocationCheckAfterSettings) {
      _pendingLocationCheckAfterSettings = true;
      await Geolocator.openLocationSettings();
      return;
    }

    // Otomatik tetik: oturum bloğuna uyar.
    if (await SimpleLocationService.isLocationPermissionDeclinedByUser()) return;
    await SimpleLocationService.ensureLocationPermissionFromUserAction();
    if (!mounted) return;
    if (!await Permission.locationWhenInUse.isGranted) return;
    await _applyLocationAfterPermissionGranted();
    await _reopenSearchSheetIfLocationGranted();
  }

  Future<void> _reopenSearchSheetIfLocationGranted() async {
    await _syncLocationUiFromPermissionOnly();
    if (!mounted) return;
    if (!await Permission.locationWhenInUse.isGranted) return;
    final data = _cachedRotaData;
    final facilities = _markerOverride;
    final highlight = _searchSheetHighlight;
    if (data == null || facilities == null || facilities.isEmpty) return;
    if (_inlineTabbedSearchOpen) {
      _closeInlineTabbedSearchPanel();
      await Future<void>.delayed(Duration.zero);
      if (!mounted || !context.mounted) return;
    } else {
      final ctrl = _attachedBottomSheet;
      if (ctrl == null) return;
      ctrl.close();
      await ctrl.closed;
      if (!mounted || !context.mounted) return;
    }
    await _openTabbedSearchResults(
      context,
      data,
      facilities,
      highlightTarget: highlight,
    );
  }

  Future<void> _performSearch(BuildContext context, RotaDataState data) async {
    FocusScope.of(context).unfocus();
    _popupController.hideAllPopups();
    final prevSheet = _attachedBottomSheet;
    if (prevSheet != null) {
      _attachedBottomSheet = null;
      try {
        prevSheet.close();
      } catch (_) {}
      await prevSheet.closed;
    }
    if (_inlineTabbedSearchOpen) {
      _closeInlineTabbedSearchPanel();
    }
    if (!mounted) return;
    // Klavye kapanırken tam ekran harita + setState aynı anda çalışınca animasyon takılıyor;
    // kısa gecikme ile IME animasyonu ile çizimi ayır.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    setState(() {
      _favoritesBrowseActive = false;
      _historyBrowseActive = false;
      _clearRouteOnly();
      _mapPreviewFacility = null;
    });

    final kaynak = MainMapSearch.tesisKaynagiArama(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    final words = MainMapSearch.queryWords(_searchController.text);
    if (words.isEmpty) {
      setState(() {
        readyToExit = false;
        isSheetVisible = true;
        _markerOverride = null;
        _searchSheetHighlight = null;
      });
      return;
    }

    await _prepareLocationForSearch();
    if (!mounted) return;

    final filtered = MainMapSearch.perform(
      query: _searchController.text,
      kaynak: kaynak,
      mapMisafirhaneler: data.misafirhaneler,
    );

    if (filtered.isEmpty) {
      if (!context.mounted) return;
      _toast(context, AppStrings.searchNoResults);
      setState(() {
        readyToExit = false;
        isSheetVisible = true;
        _markerOverride = const [];
        _mapPreviewFacility = null;
        _searchSheetHighlight = null;
      });
      return;
    }

    final displayList = filtered;

    final narrowForHighlight = MainMapSearch.narrowFuzzyMatches(
      query: _searchController.text,
      kaynak: kaynak,
    );
    final highlightMatch = MainMapSearch.findPrimaryMatchForScroll(
      query: _searchController.text,
      displayedFacilities:
          narrowForHighlight.isNotEmpty ? narrowForHighlight : displayList,
    );
    Misafirhane? highlightTarget = highlightMatch;
    if (highlightMatch != null) {
      for (final m in displayList) {
        if (m.sameFavoriteIdentity(highlightMatch)) {
          highlightTarget = m;
          break;
        }
      }
    }

    setState(() {
      readyToExit = false;
      isSheetVisible = true;
      _markerOverride = displayList;
      _mapPreviewFacility = null;
      _searchSheetHighlight = highlightTarget;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !context.mounted) return;
      final hl = highlightTarget;
      if (hl != null && _validFacilityCoords(hl)) {
        _fitFacilitiesCamera(displayList);
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (!mounted || !context.mounted) return;
        await _animateTowardsMisafirhane(hl);
      } else {
        _fitFacilitiesCamera(displayList);
      }
      await Future<void>.delayed(const Duration(milliseconds: 140));
      if (!mounted || !context.mounted) return;
      await _openTabbedSearchResults(
        context,
        data,
        displayList,
        highlightTarget: hl,
      );
    });
  }

  /// Kullanıcının konumu — yeşil harita pini (tesis işaretçisiyle aynı ikon ailesi).
  Marker _userLocationMarker(LatLng ll) {
    const size = 48.0;
    return Marker(
      point: ll,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Icon(
        Icons.location_on,
        color: const Color(0xFF2E7D32),
        size: size,
        shadows: const [
          Shadow(color: Color(0x59000000), offset: Offset(0, 2), blurRadius: 4),
        ],
      ),
    );
  }

  Future<void> _openTabbedSearchResults(
    BuildContext context,
    RotaDataState data,
    List<Misafirhane> facilities, {
    Misafirhane? highlightTarget,
    bool reopenNextBackExitsSearch = false,
  }) async {
    try {
      if (!mounted || !context.mounted) return;
      final granted = await Permission.locationWhenInUse.isGranted;
      LatLng? userForSort;
      if (granted &&
          _userLocationLatLng != null &&
          isValidWgs84LatLng(_userLocationLatLng!.latitude, _userLocationLatLng!.longitude)) {
        userForSort = _userLocationLatLng;
      }
      if (!mounted || !context.mounted) return;
      if (userForSort != null) {
        _userLocationLatLng = userForSort;
      }
      _mapLocationState.update(_userLocationLatLng, granted);
      final sorted = sortMisafirhaneByDistance(facilities, userForSort);
    Misafirhane? resolvedHighlight;
    if (highlightTarget != null) {
      for (final m in sorted) {
        if (m.sameFavoriteIdentity(highlightTarget)) {
          resolvedHighlight = m;
          break;
        }
      }
    }
    final prevAttached = _attachedBottomSheet;
    if (prevAttached != null) {
      _attachedBottomSheet = null;
      try {
        prevAttached.close();
      } catch (_) {}
      await prevAttached.closed;
    }
    if (!mounted || !context.mounted) return;

    if (_inlineTabbedSearchOpen) {
      setState(() {
        _inlineTabbedSearchOpen = false;
        _tabbedSheetFacilities = const [];
        _tabbedSheetRotaData = null;
        _tabbedSheetHighlight = null;
      });
      _disposeSearchSheetExtentController();
      await Future<void>.delayed(Duration.zero);
      if (!mounted || !context.mounted) return;
    }

    _allocateSearchSheetExtentController();
    if (!mounted || !context.mounted) return;
    setState(() {
      readyToExit = reopenNextBackExitsSearch;
      isSheetVisible = true;
      _inlineTabbedSearchOpen = true;
      _tabbedSheetFacilities = sorted;
      _tabbedSheetRotaData = data;
      _tabbedSheetHighlight = resolvedHighlight;
    });
    // Arama sonuçları açılınca izin yoksa otomatik iste (oturumda red yoksa).
    if (mounted &&
        !await Permission.locationWhenInUse.isGranted &&
        !await SimpleLocationService.isLocationPermissionDeclinedByUser()) {
      unawaited(_ensureLocationPermissionAndLocationForLists());
    }
    } catch (e, st) {
      _disposeSearchSheetExtentController();
      debugPrint('Arama sonuç sheet: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handleSystemBack());
      },
      child: Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      drawer: _buildDrawer(context),
      /// Kalıcı bottom sheet gövdenin üstünde; alt menü burada kalınca sheet menüyü kapatmaz (tıklanır).
      bottomNavigationBar: _MainBottomBar(
        onRoutePlan: () => _openRoutePlanning(context),
        onHistory: () => unawaited(_openHistoryTab(context)),
        onFavorites: () => unawaited(_openFavoritesTab(context)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: StreamBuilder<RotaDataState>(
              stream: widget.repository.watchRoot(),
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data != null && data.errorMessage == null) {
                  _cachedRotaData = data;
                }
                final rotaForUi = (data != null && data.errorMessage != null)
                    ? _cachedRotaData
                    : (data ?? _cachedRotaData);
                final loading = !snapshot.hasData &&
                    snapshot.connectionState == ConnectionState.waiting;
                final inRoute =
                    _activeRouteStops != null && _activeRouteStops!.isNotEmpty;
                final display = _markersSource(data);
                final routeMarkers = (inRoute && rotaForUi != null)
                    ? <Marker>[
                        ..._markersForRoute(rotaForUi, _activeRouteStops!),
                        ..._routeLabelMarkers,
                      ]
                    : const <Marker>[];
                final facilityPopupMarkers = !inRoute
                    ? _misafirhaneMapMarkers(display, _searchSheetHighlight)
                    : const <Marker>[];
                /// Arama sekmeli sheet açıkken tam görünürken gizlenir; küçültülünce veya
                /// tamamen kapatılınca FAB tekrar çıkar (listeyi yeniden açmak için).
                final searchSheetFab = _markerOverride != null &&
                    !inRoute &&
                    !_favoritesBrowseActive &&
                    !_historyBrowseActive &&
                    ((!_inlineTabbedSearchOpen && _attachedBottomSheet == null) || !isSheetVisible);
                final showListFab = inRoute ||
                    _favoritesBrowseActive ||
                    _historyBrowseActive ||
                    searchSheetFab;

                if (snapshot.hasError &&
                    _cachedRotaData == null &&
                    display.isEmpty &&
                    !inRoute) {
                  return Center(child: Text('Hata: ${snapshot.error}'));
                }
                if (data?.errorMessage != null &&
                    _cachedRotaData == null &&
                    display.isEmpty &&
                    !inRoute) {
                  return Center(child: Text(data!.errorMessage!));
                }

                if (snapshot.hasData &&
                    rotaForUi != null &&
                    !loading &&
                    !snapshot.hasError &&
                    data?.errorMessage == null &&
                    !_initialTurkeyBoundsApplied) {
                  _initialTurkeyBoundsApplied = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _fitTurkeyOverviewCamera();
                  });
                }

                final mq = MediaQuery.paddingOf(context);
                final toolbarBottom = mq.top + kToolbarHeight;
                final searchBarTop = toolbarBottom + 24;
                final myLocationFabTop = searchBarTop + 56 + 8;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    RepaintBoundary(
                      child: PopupScope(
                        onPopupEvent: _onMisafirhanePopupEvent,
                        child: FlutterMap(
                          key: const ValueKey<String>('main-map'),
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: sanitizeLatLng(_center),
                            initialZoom: clampZoom(_zoom),
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                            onPositionChanged: (pos, hasGesture) {
                              final c = pos.center;
                              if (isValidWgs84LatLng(c.latitude, c.longitude)) {
                                _center = c;
                              } else {
                                _center = kTurkeyMapFallbackCenter;
                              }
                              _zoom = clampZoom(pos.zoom);
                            },
                            onTap: (tapPosition, point) {
                              _popupController.hideAllPopups();
                              if (_inlineTabbedSearchOpen &&
                                  isSheetVisible &&
                                  (_searchSheetExtentController?.isAttached ?? false)) {
                                unawaited(() async {
                                  await _collapseSearchResultsSheet();
                                  if (mounted) {
                                    setState(() => isSheetVisible = false);
                                  }
                                }());
                              }
                              if (_mapPreviewFacility != null) {
                                unawaited(_closeMapPreviewAnimated());
                              }
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.serdarza.rotalink',
                            ),
                            if (_routePolylines.isNotEmpty)
                              PolylineLayer(polylines: _routePolylines),
                            if (inRoute && rotaForUi != null) ...[
                              MarkerLayer(markers: routeMarkers),
                              if (_userLocationLatLng != null &&
                                  isValidWgs84LatLng(
                                    _userLocationLatLng!.latitude,
                                    _userLocationLatLng!.longitude,
                                  ))
                                MarkerLayer(
                                  markers: [_userLocationMarker(_userLocationLatLng!)],
                                ),
                            ] else ...[
                              PopupMarkerLayer(
                                options: PopupMarkerLayerOptions(
                                  markers: facilityPopupMarkers,
                                  popupController: _popupController,
                                ),
                              ),
                              if (_userLocationLatLng != null &&
                                  isValidWgs84LatLng(
                                    _userLocationLatLng!.latitude,
                                    _userLocationLatLng!.longitude,
                                  ))
                                MarkerLayer(
                                  markers: [_userLocationMarker(_userLocationLatLng!)],
                                ),
                              PopupLayer(
                                popupDisplayOptions: PopupDisplayOptions(
                                  snap: PopupSnap.markerTop,
                                  builder: (ctx, marker) {
                                    if (marker is MisafirhaneMapMarker) {
                                      return MisafirhaneMarkerInfoPopup(
                                        misafirhane: marker.misafirhane,
                                        onInceleHaritaArama: (q) async {
                                          final d = rotaForUi ?? _cachedRotaData;
                                          if (d == null) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Harita verisi henüz yüklenemedi.',
                                                  ),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          if (!mounted || !context.mounted) return;
                                          _searchController.text = q;
                                          await _performSearch(context, d);
                                        },
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (loading)
                      const ColoredBox(
                        color: Color(0x66000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_inlineTabbedSearchOpen &&
                        _tabbedSheetRotaData != null &&
                        _searchSheetExtentController != null)
                      MisafirhaneSearchResultsPanel(
                        key: ValueKey<String>(
                          '${_tabbedSheetFacilities.length}-${_searchSheetHighlight?.stableFacilityId ?? 'h'}',
                        ),
                        sheetExtentController: _searchSheetExtentController!,
                        facilities: _tabbedSheetFacilities,
                        rotaData: _tabbedSheetRotaData!,
                        mapLocationState: _mapLocationState,
                        highlightTarget: _tabbedSheetHighlight,
                        favoritesRepo: _favoritesRepo,
                        onFavoritesChanged: _reloadFavoritesCache,
                        onTesisSelect: (m) async {
                          _showMisafirhanePopupFor(m);
                        },
                        onRequestLocationPermission: _onSearchSheetRequestLocation,
                        onClosePanel: _closeInlineTabbedSearchPanel,
                      ),
                    Positioned(
                      left: 16,
                      right: 16,
                      top: searchBarTop,
                      child: CustomSearchBar(
                        key: ValueKey<int>(_searchBarSession),
                        controller: _searchController,
                        ilOptionsSorted: rotaForUi != null
                            ? MainMapSearch.distinctSortedIller(
                                aramaIcinTumTesisler: rotaForUi.aramaIcinTumTesisler,
                                misafirhaneler: rotaForUi.misafirhaneler,
                              )
                            : null,
                        onSubmitted: rotaForUi != null
                            ? () => unawaited(_performSearch(context, rotaForUi))
                            : null,
                        onSearchCleared: () {
                          if (!mounted) return;
                          FocusManager.instance.primaryFocus?.unfocus();
                          _onMainSearchCleared();
                          setState(() => _searchBarSession++);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _fitTurkeyOverviewCamera();
                          });
                        },
                      ),
                    ),
                    Positioned(
                      right: 16,
                      top: myLocationFabTop,
                      child: Material(
                        elevation: 6,
                        shape: const CircleBorder(),
                        color: AppColors.primary,
                        child: IconButton(
                          tooltip: AppStrings.myLocationTooltip,
                          onPressed: () => unawaited(_goToMyLocation()),
                          icon: Icon(
                            Icons.my_location,
                            color: !_mapLocationState.locationPermissionGranted
                                ? AppColors.white.withValues(alpha: 0.55)
                                : AppColors.white,
                          ),
                        ),
                      ),
                    ),
                    if (_mapPreviewFacility != null)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final m = _mapPreviewFacility!;
                          const cardWMax = 200.0;
                          // ~2 satır + padding; marker ile boşluk
                          const estCardH = 52.0;
                          const markerHalf = 20.0;
                          const gapAboveMarker = 8.0;
                          final minTopBelowSearch = toolbarBottom + 72.0;
                          final cardW = math.min(cardWMax, constraints.maxWidth - 16);

                          double left;
                          double top;
                          if (_validFacilityCoords(m)) {
                            final pt = _mapController.camera.latLngToScreenPoint(
                              latLngOrFallback(m.latitude, m.longitude),
                            );
                            left = (pt.x - cardW / 2).clamp(8.0, constraints.maxWidth - cardW - 8);
                            top = pt.y - markerHalf - gapAboveMarker - estCardH;
                            top = top.clamp(
                              minTopBelowSearch,
                              math.max(
                                minTopBelowSearch,
                                constraints.maxHeight - estCardH - MediaQuery.paddingOf(context).bottom - 16,
                              ),
                            );
                          } else {
                            left = (constraints.maxWidth - cardW) / 2;
                            top = constraints.maxHeight - estCardH - 130;
                          }

                          return Positioned(
                            left: left,
                            top: top,
                            width: cardW,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              opacity: _previewClosing ? 0 : 1,
                              child: AnimatedSlide(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                offset: _previewClosing ? const Offset(0, 0.06) : Offset.zero,
                                child: MapFacilityPreviewCard(
                                  misafirhane: m,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    Positioned(
                      right: 16,
                      bottom: 8,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (showListFab)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10, right: 2),
                              child: FloatingActionButton(
                                heroTag: 'fab_list',
                                backgroundColor: AppColors.primary,
                                elevation: 12,
                                onPressed: () async {
                                  if (inRoute) {
                                    await _openRouteSummarySheet(
                                      context,
                                      _activeRouteStops!,
                                      totalDistanceM: _routeSummaryDistanceM,
                                      totalDurationS: _routeSummaryDurationS,
                                      navWaypoints: rotaForUi != null
                                          ? waypointsForRouteStops(rotaForUi, _activeRouteStops!)
                                          : null,
                                    );
                                  } else if (_favoritesBrowseActive || _historyBrowseActive) {
                                    _openMisafirhaneSheet(
                                      display,
                                      liveFavoriteList: _favoritesBrowseActive,
                                      liveHistoryList: _historyBrowseActive,
                                    );
                                  } else if (rotaForUi != null) {
                                    if (_markerOverride != null &&
                                        _inlineTabbedSearchOpen &&
                                        (_searchSheetExtentController?.isAttached ?? false)) {
                                      await _expandSearchResultsSheet();
                                      if (mounted) {
                                        setState(() => isSheetVisible = true);
                                      }
                                    } else {
                                      await _openTabbedSearchResults(
                                        context,
                                        rotaForUi,
                                        display,
                                        highlightTarget: _searchSheetHighlight,
                                      );
                                    }
                                  }
                                },
                                tooltip: inRoute
                                    ? AppStrings.routePlanSummaryTitle
                                    : AppStrings.fabMisafirhaneList,
                                child: Icon(
                                  searchSheetFab
                                      ? Icons.view_list_rounded
                                      : Icons.keyboard_arrow_up,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          _EmergencyFab(
                            onTap: () => unawaited(showEmergencyBottomSheet(context)),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _RotalinkToolbar(
                        onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                        onTitleTap: _goToInitialMapHome,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          /// AdMob banner: arama sekmeli panel [Stack] içinde olduğundan body ile aynı katmanda engellenmez.
          if (_attachedBottomSheet == null && !_inlineTabbedSearchOpen)
            RotalinkBannerAd(adsEnabled: AdService.adsEnabled),
        ],
      ),
    ),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _goToMyLocation() async {
    if (!mounted) return;
    await _syncLocationUiFromPermissionOnly();
    if (!mounted || !await Permission.locationWhenInUse.isGranted) {
      if (mounted) {
        _toast(
          context,
          'Konum izni yok. İzin için önce arama yapın veya Ayarlardan açın.',
        );
      }
      return;
    }
    if (SimpleLocationService.shouldSuppressPlayServicesLocationActivity) {
      if (mounted) {
        _toast(context, AppStrings.locationServicesOffSnack);
      }
      return;
    }
    if (!mounted) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: _kRotalinkLocationSettingsLow,
      );
      if (!mounted) return;
      if (!isValidWgs84LatLng(pos.latitude, pos.longitude)) {
        if (mounted) {
          setState(() => _userLocationLatLng = null);
          try {
            _mapController.move(kTurkeyMapFallbackCenter, kTurkeyMapFallbackZoom);
          } catch (_) {}
          _toast(context, '${AppStrings.locationFailedPrefix}Geçersiz konum.');
        }
        return;
      }
      final ll = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _userLocationLatLng = ll;
          _center = ll;
        });
      }
      unawaited(UserLocationCache.save(ll));
      _mapLocationState.update(ll, true);
      try {
        _mapController.move(ll, clampZoom(12));
      } catch (_) {
        try {
          _mapController.move(kTurkeyMapFallbackCenter, kTurkeyMapFallbackZoom);
        } catch (_) {}
      }
    } catch (e) {
      SimpleLocationService.markSessionPlayServicesLocationPromptDeclined();
      if (mounted) {
        _toast(context, AppStrings.locationServicesOffSnack);
      }
    }
  }

  Future<void> _dialFacilityPhone(BuildContext context, String phone) async {
    final p = phone.trim();
    if (p.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Telefon numarası yok')),
        );
      }
      return;
    }
    final uri = Uri(scheme: 'tel', path: p.replaceAll(RegExp(r'\s'), ''));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arama başlatılamadı')),
        );
      }
    }
  }

  Future<void> _shareFacility(Misafirhane m) async {
    final mapsUrl = googleMapsShareUrlForMisafirhane(m);
    const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.serdarza.rotalink';
    final text = '${m.isim}\n$mapsUrl\n\n'
        'Telefon: ${m.telefon.isEmpty ? 'Yok' : m.telefon}\n\n'
        'Rotalink uygulamasını bu linkten indirebilirsiniz.\n'
        '$playStoreUrl';
    await Share.share(text);
  }

  Widget _compactSheetActionColumn({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: SizedBox(
          width: 44,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMisafirhaneSheet(
    List<Misafirhane> items, {
    bool liveFavoriteList = false,
    bool liveHistoryList = false,
  }) {
    _popupController.hideAllPopups();
    _dismissAttachedBottomSheet();
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState == null) return;
    final ctrl = scaffoldState.showBottomSheet(
      (sheetCtx) => StatefulBuilder(
          builder: (ctx, setModal) {
            List<Misafirhane> rows() {
              if (liveHistoryList) {
                return _resolveSavedAgainstLive(_historyCache, _cachedRotaData);
              }
              if (liveFavoriteList) {
                return _resolveSavedAgainstLive(_favoritesCache, _cachedRotaData);
              }
              return items;
            }

            Future<void> onHeartToggled(Misafirhane m) async {
              final wasFav = _favoritesCache.any((f) => f.sameFavoriteIdentity(m));
              await _favoritesRepo.toggle(m);
              await _reloadFavoritesCache();
              if (!mounted) return;
              if (liveFavoriteList && _favoritesCache.isEmpty) {
                Navigator.pop(sheetCtx);
                setState(() => _favoritesBrowseActive = false);
                return;
              }
              if (sheetCtx.mounted) {
                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                  SnackBar(
                    content: Text(wasFav ? 'Favorilerden çıkarıldı' : 'Favorilere eklendi'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
              setModal(() {});
              if (liveFavoriteList) {
                _fitFacilitiesCamera(rows());
              }
            }

            Future<void> onRowTap(Misafirhane m) async {
              Navigator.pop(sheetCtx);
              if (!mounted) return;
              _showMisafirhanePopupFor(m);
              if (liveHistoryList || liveFavoriteList) {
                setState(() {});
              }
              if (liveHistoryList) {
                _fitFacilitiesCamera(rows());
              }
            }

            Future<void> requestLocationFromCompactSheet() async {
              await _ensureLocationPermissionAndLocationForLists(
                fromDistanceChip: true,
              );
              if (!mounted || !await Permission.locationWhenInUse.isGranted) return;
              if (!sheetCtx.mounted) return;
              Navigator.pop(sheetCtx);
              if (!mounted) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _openMisafirhaneSheet(
                  items,
                  liveFavoriteList: liveFavoriteList,
                  liveHistoryList: liveHistoryList,
                );
              });
            }

            final list = rows();
            final sheetH = misafirhaneCompactSheetHeight(ctx);
            return SizedBox(
              height: sheetH,
              child: Material(
                color: AppColors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = list[i];
                    final isFav = _favoritesCache.any((f) => f.sameFavoriteIdentity(m));
                    return ListenableBuilder(
                      listenable: _mapLocationState,
                      builder: (context, _) {
                        return InkWell(
                          onTap: () => unawaited(onRowTap(m)),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        m.isim,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 14,
                                          height: 1.15,
                                        ),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    _compactSheetActionColumn(
                                      icon: Icons.call,
                                      color: const Color(0xFF2E7D32),
                                      label: 'Ara',
                                      onTap: () => unawaited(_dialFacilityPhone(context, m.telefon)),
                                    ),
                                    _compactSheetActionColumn(
                                      icon: Icons.share,
                                      color: const Color(0xFF039BE5),
                                      label: 'Paylaş',
                                      onTap: () => unawaited(_shareFacility(m)),
                                    ),
                                    _compactSheetActionColumn(
                                      icon: isFav ? Icons.favorite : Icons.favorite_border,
                                      color: const Color(0xFFC2185B),
                                      label: 'Favori',
                                      onTap: () => unawaited(onHeartToggled(m)),
                                    ),
                                    _compactSheetActionColumn(
                                      icon: Icons.map_outlined,
                                      color: AppColors.primary,
                                      label: 'İncele',
                                      onTap: () => unawaited(openMapSearch(context, m.il, m.isim)),
                                    ),
                                    _compactSheetActionColumn(
                                      icon: Icons.chat_bubble_outline,
                                      color: const Color(0xFFE65100),
                                      label: 'Yorum',
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => YorumScreen(
                                            facilityId: ReviewRepository.sanitizeFacilityId(m.stableFacilityId),
                                            facilityName: m.isim,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                DistancePermissionChip(
                                  userLocation: _mapLocationState.userLocation,
                                  locationPermissionGranted:
                                      _mapLocationState.locationPermissionGranted,
                                  facilityPoint: LatLng(m.latitude, m.longitude),
                                  onRequestLocation: requestLocationFromCompactSheet,
                                  spacingAbove: 4,
                                  fullWidthSingleLine: true,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            );
          },
        ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      enableDrag: true,
    );
    _attachedBottomSheet = ctrl;
    ctrl.closed.then((_) {
      if (!mounted) return;
      if (_attachedBottomSheet != ctrl) return;
      _attachedBottomSheet = null;
    });
  }

  /// Kotlin [RouteTextOverlay] — segment polyline ortası.
  List<Marker> _routeSegmentLabelMarkers(List<OsrmSegment> segments) {
    final out = <Marker>[];
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.points.isEmpty) continue;
      final mid = seg.points[seg.points.length ~/ 2];
      final dist = formatRouteDistanceMeters(seg.distanceM);
      final dur = formatRouteDurationSeconds(seg.durationS);
      out.add(
        Marker(
          key: ValueKey<String>('route-lbl-$i-${mid.latitude}-${mid.longitude}'),
          point: mid,
          width: 104,
          height: 42,
          alignment: Alignment.center,
          rotate: true,
          child: IgnorePointer(
            child: Material(
              color: const Color(0xCC000000),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dist,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      dur,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }

  List<Marker> _markersForRoute(RotaDataState data, List<RouteStop> stops) {
    final out = <Marker>[];
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      final m = firstMisafirhaneForIl(data, s.city);
      if (m == null || !_validFacilityCoords(m)) continue;
      out.add(
        Marker(
          point: latLngOrFallback(m.latitude, m.longitude),
          width: 100,
          height: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.city,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  shadows: [
                    Shadow(color: Colors.white, blurRadius: 4),
                  ],
                ),
              ),
              const Icon(Icons.place, color: Color(0xFFE65100), size: 34),
            ],
          ),
        ),
      );
    }
    return out;
  }

  void _fitRouteCamera(List<LatLng> points) {
    _fitLatLngsOrMoveCamera(points, singlePointZoom: 10);
  }

  Future<void> _openRoutePlanning(BuildContext context) async {
    final outcome = await Navigator.of(context).push<RoutePlanOutcome>(
      MaterialPageRoute<RoutePlanOutcome>(
        builder: (_) => RoutePlanScreen(repository: widget.repository),
      ),
    );
    if (!mounted || outcome == null || outcome.stops.isEmpty) return;
    final data = _cachedRotaData;
    if (data == null) return;
    await _applyRoutePlan(
      context,
      data,
      outcome.stops,
      precomputedSegments: outcome.segments,
    );
  }

  Future<void> _applyRoutePlan(
    BuildContext context,
    RotaDataState data,
    List<RouteStop> stops, {
    List<OsrmSegment>? precomputedSegments,
  }) async {
    final token = ++_routeLoadGen;
    _searchController.clear();
    _popupController.hideAllPopups();
    _dismissAttachedBottomSheet();
    setState(() {
      _favoritesBrowseActive = false;
      _historyBrowseActive = false;
      _markerOverride = null;
      _searchSheetHighlight = null;
      _activeRouteStops = stops;
      _routePolylines = const [];
      _routeLabelMarkers = const [];
      _routeSummaryDistanceM = null;
      _routeSummaryDurationS = null;
    });

    final waypoints = waypointsForRouteStops(data, stops);
    if (waypoints.length < 2) {
      if (mounted) {
        setState(_clearRouteOnly);
        _toast(context, AppStrings.routePlanInsufficientLocations);
      }
      return;
    }

    final segments = precomputedSegments != null && precomputedSegments.isNotEmpty
        ? precomputedSegments
        : await OsrmRouteService.fetchSegments(waypoints);
    if (!mounted || token != _routeLoadGen) return;

    var totalDistanceM = 0.0;
    var totalDurationS = 0.0;
    for (final s in segments) {
      totalDistanceM += s.distanceM;
      totalDurationS += s.durationS;
    }

    final polylines = <Polyline<Object>>[];
    for (final s in segments) {
      final pts = onlyValidLatLngs(s.points);
      if (pts.length < 2) continue;
      polylines.add(
        Polyline<Object>(
          points: pts,
          color: const Color(0xFFD32F2F),
          strokeWidth: 5,
        ),
      );
    }

    final straight = onlyValidLatLngs(OsrmRouteService.straightFallback(waypoints));
    final effectivePolylines = polylines.isNotEmpty
        ? polylines
        : (straight.length >= 2
            ? [
                Polyline<Object>(
                  points: straight,
                  color: const Color(0xFFD32F2F),
                  strokeWidth: 5,
                ),
              ]
            : const <Polyline<Object>>[]);

    final flat = effectivePolylines.expand((p) => p.points).toList();
    final labels = segments.isNotEmpty ? _routeSegmentLabelMarkers(segments) : const <Marker>[];

    final hasOsrmTotals = segments.isNotEmpty && totalDistanceM > 0 && totalDurationS > 0;
    setState(() {
      _routePolylines = effectivePolylines;
      _routeLabelMarkers = labels;
      _routeSummaryDistanceM = hasOsrmTotals ? totalDistanceM : null;
      _routeSummaryDurationS = hasOsrmTotals ? totalDurationS : null;
    });
    _fitRouteCamera(flat);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openRouteSummarySheet(
        context,
        stops,
        totalDistanceM: hasOsrmTotals ? totalDistanceM : null,
        totalDurationS: hasOsrmTotals ? totalDurationS : null,
        navWaypoints: waypointsForRouteStops(data, stops),
      ));
    });
  }

  Future<void> _promptSaveRouteFromMap(BuildContext context, List<RouteStop> stops) async {
    final nameCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(AppStrings.routePlanSaveTitle),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(hintText: AppStrings.routePlanSaveNameHint),
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        _toast(context, AppStrings.routePlanSaveEmptyName);
        return;
      }
      final lites = stops.map((s) => RouteStopLite(city: s.city, days: s.days)).toList();
      await _savedRoutes.upsert(
        SavedRouteRecord(
          name: name,
          savedDateMillis: DateTime.now().millisecondsSinceEpoch,
          stops: lites,
        ),
      );
      if (mounted) _toast(context, AppStrings.routePlanSaveSuccess);
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
      });
    }
  }

  Future<void> _openRouteSummarySheet(
    BuildContext context,
    List<RouteStop> stops, {
    double? totalDistanceM,
    double? totalDurationS,
    List<LatLng>? navWaypoints,
  }) async {
    if (!mounted) return;
    final prevAttached = _attachedBottomSheet;
    if (prevAttached != null) {
      _attachedBottomSheet = null;
      try {
        prevAttached.close();
      } catch (_) {}
      await prevAttached.closed;
    }
    if (!mounted) return;
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState == null) return;
    final mq = MediaQuery.of(context);
    final bottomSafe = mq.padding.bottom;
    final ctrl = scaffoldState.showBottomSheet(
      (sheetCtx) => MediaQuery(
        data: MediaQuery.of(sheetCtx).copyWith(viewInsets: EdgeInsets.zero),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomSafe),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.52,
            minChildSize: 0.28,
            maxChildSize: 0.92,
            builder: (_, scroll) {
            final routeDm = totalDistanceM ?? 0;
            final routeDs = totalDurationS ?? 0;
            final showTotals = routeDm > 0 && routeDs > 0;
            return Material(
              color: AppColors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: ListView(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              children: [
                ListTile(
                  title: Text(
                    AppStrings.routePlanSummaryTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ),
                if (showTotals) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF007B8F), Color(0xFF005F6B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(Icons.route_rounded, color: AppColors.white, size: 26),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppStrings.routePlanTotalDistance,
                                        style: TextStyle(
                                          color: AppColors.white.withValues(alpha: 0.85),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        formatRouteDistanceMeters(routeDm),
                                        style: const TextStyle(
                                          color: AppColors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              AppStrings.routePlanTotalDuration,
                              style: TextStyle(
                                color: AppColors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatRouteDurationSeconds(routeDs),
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              AppStrings.routePlanOsrmNote,
                              style: TextStyle(
                                color: AppColors.white.withValues(alpha: 0.75),
                                fontSize: 11,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                ...stops.asMap().entries.map((e) {
                  final i = e.key;
                  final s = e.value;
                  final title = s.days == 0
                      ? '${i + 1}. ${s.city} · ${AppStrings.routePlanStartNoOvernight}'
                      : '${i + 1}. ${s.city} — ${s.days} ${AppStrings.routePlanDaysLabel}';
                  final children = <Widget>[];
                  if (s.items.isEmpty) {
                    children.add(
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F9FA),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            AppStrings.routePlanNoSuggestions,
                            style: TextStyle(fontSize: 13, color: AppColors.campaignSummaryMuted),
                          ),
                        ),
                      ),
                    );
                  } else {
                    for (final it in s.items) {
                      if (it is Misafirhane) {
                        children.add(
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                            child: Material(
                              color: Colors.white,
                              elevation: 0,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.2)),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: const CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Color(0xFFE3F2FD),
                                    child: Icon(Icons.hotel_rounded, color: Color(0xFF1565C0), size: 20),
                                  ),
                                  title: Text(
                                    it.isim,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    AppStrings.routePlanKonak,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.primary.withValues(alpha: 0.8),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      } else if (it is GeziYemekItem) {
                        final yemek = it.tur == 'Yemek';
                        final label = yemek ? AppStrings.routePlanYemek : AppStrings.routePlanGezi;
                        final accent = yemek ? const Color(0xFFE65100) : const Color(0xFF2E7D32);
                        final dayLabel = it.day != null && s.days > 0
                            ? ' · ${AppStrings.routePlanDayShort} ${it.day}'
                            : '';
                        children.add(
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                            child: Material(
                              color: Colors.white,
                              elevation: 0,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: accent.withValues(alpha: 0.12),
                                    child: Icon(
                                      yemek ? Icons.restaurant_rounded : Icons.park_rounded,
                                      color: accent,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    it.isim,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    '$label$dayLabel',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: accent.withValues(alpha: 0.9),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    }
                  }
                  return ExpansionTile(
                    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    children: children,
                  );
                }),
                if (navWaypoints != null && navWaypoints.length >= 2) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.navigation_rounded, color: AppColors.primary),
                    title: const Text(AppStrings.routePlanStartNavigation),
                    onTap: () {
                      openGoogleDirectionsWaypoints(sheetCtx, navWaypoints);
                    },
                  ),
                ],
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text(AppStrings.routePlanClearRoute),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    setState(_clearRouteOnly);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: const Text(AppStrings.routePlanSaveTitle),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    await _promptSaveRouteFromMap(context, stops);
                  },
                ),
              ],
            ),
            );
          },
        ),
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      enableDrag: true,
    );
    _attachedBottomSheet = ctrl;
    ctrl.closed.then((_) {
      if (!mounted) return;
      if (_attachedBottomSheet == ctrl) {
        _attachedBottomSheet = null;
      }
    });
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      width: 280,
      backgroundColor: AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 180,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.drawerHeaderGradientStart,
                  AppColors.drawerHeaderGradientEnd,
                ],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: const Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.appName,
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.05,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    AppStrings.drawerSubtitle,
                    style: TextStyle(
                      color: Color(0xFFB0E8EE),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _DrawerTile(
                  icon: Icons.wb_sunny_outlined,
                  title: AppStrings.drawerWeather,
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(showWeatherBottomSheet(context));
                  },
                ),
                _DrawerTile(
                  icon: Icons.calendar_month_outlined,
                  title: AppStrings.drawerHolidays,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const HolidaysScreen(),
                      ),
                    );
                  },
                ),
                _DrawerTile(
                  icon: Icons.send_outlined,
                  title: AppStrings.drawerSuggestion,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const SuggestionScreen(),
                      ),
                    );
                  },
                ),
                _DrawerTile(
                  icon: Icons.language_outlined,
                  title: AppStrings.drawerWebsite,
                  onTap: () => unawaited(_openDrawerWebsite(context)),
                ),
                _DrawerTile(
                  icon: Icons.share_outlined,
                  title: AppStrings.drawerShareApp,
                  onTap: () => unawaited(_shareAppFromDrawer(context)),
                ),
                _DrawerTile(
                  icon: Icons.info_outline,
                  title: AppStrings.drawerAbout,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AboutScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 16),
            child: Text(
              '${AppStrings.drawerVersionPrefix}$_versionLabel',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF212121),
                letterSpacing: 0.04,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDrawerWebsite(BuildContext context) async {
    Navigator.pop(context);
    final uri = Uri.parse('https://rotalink.tr');
    try {
      final ok = await canLaunchUrl(uri);
      if (ok) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) _toast(context, 'Web sitesi açılamadı.');
      }
    } catch (_) {
      if (context.mounted) _toast(context, 'Web sitesi açılamadı.');
    }
  }

  Future<void> _shareAppFromDrawer(BuildContext context) async {
    Navigator.pop(context);
    const playStoreUrl =
        'https://play.google.com/store/apps/details?id=com.serdarza.rotalink';
    await Share.share(
      'Rotalink uygulamasını bu linkten indirebilirsiniz:\n$playStoreUrl',
    );
  }
}

/// `bg_toolbar_teal_rounded`: yalnız alt köşeler yuvarlak teal şerit.
class _RotalinkToolbar extends StatelessWidget {
  const _RotalinkToolbar({
    required this.onMenu,
    required this.onTitleTap,
  });

  final VoidCallback onMenu;
  final VoidCallback onTitleTap;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      elevation: 6,
      color: AppColors.primary,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(22),
        bottomRight: Radius.circular(22),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, top, 8, 0),
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                onPressed: onMenu,
                tooltip: AppStrings.menuOpen,
                icon: const Icon(Icons.menu, color: AppColors.white),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: onTitleTap,
                    borderRadius: BorderRadius.circular(10),
                    splashColor: AppColors.white.withValues(alpha: 0.2),
                    highlightColor: AppColors.white.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Text(
                        AppStrings.appName,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyFab extends StatelessWidget {
  const _EmergencyFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: AppStrings.fabEmergency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            elevation: 12,
            shape: const CircleBorder(),
            color: const Color(0xFFD32F2F),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 56,
                height: 56,
                child: const Icon(Icons.priority_high, color: AppColors.white, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AppStrings.emergencyLabel,
            style: TextStyle(
              color: AppColors.emergencyLabel,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.4,
              shadows: const [
                Shadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MainBottomBar extends StatelessWidget {
  const _MainBottomBar({
    required this.onRoutePlan,
    required this.onHistory,
    required this.onFavorites,
  });

  final VoidCallback onRoutePlan;
  final VoidCallback onHistory;
  final VoidCallback onFavorites;

  @override
  Widget build(BuildContext context) {
    void openDiscover() {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => DiscoverScreen()),
      );
    }

    return Material(
      color: AppColors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              _BottomEntry(
                icon: Icons.history,
                iconColor: AppColors.bottomNavHistoryTint,
                label: AppStrings.bottomHistory,
                onTap: onHistory,
              ),
              _BottomEntry(
                icon: Icons.favorite,
                iconColor: const Color(0xFFC2185B),
                label: AppStrings.bottomFavorites,
                onTap: onFavorites,
              ),
              _BottomEntry(
                icon: Icons.alt_route,
                iconColor: AppColors.bottomNavRouteTint,
                label: AppStrings.bottomRoutePlan,
                onTap: onRoutePlan,
              ),
              _BottomEntry(
                icon: Icons.card_giftcard,
                iconColor: AppColors.bottomNavDiscoverTint,
                label: AppStrings.bottomDiscover,
                onTap: openDiscover,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomEntry extends StatelessWidget {
  const _BottomEntry({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
      onTap: onTap,
    );
  }
}
