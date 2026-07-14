import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
// ignore: implementation_imports — [PopupEvent] public export yok.
import 'package:flutter_map_marker_popup/src/state/popup_event.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads/ad_service.dart';
import '../constants/store_links.dart';
import '../data/app_rating_prefs.dart';
import '../data/favorites_repository.dart';
import '../data/firebase_rota_repository.dart';
import '../providers/rota_data_provider.dart';
import '../navigator_keys.dart';
import '../navigation/main_map_nav_bridge.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../navigation/rotalink_shell_scope.dart';
import '../onboarding/app_onboarding_controller.dart';
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
import '../services/version_check_service.dart';
import '../widgets/update_required_dialog.dart';
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
import '../kami/kami_overlay.dart';
import '../widgets/emergency_bottom_sheet.dart';
import '../providers/facility_filter_provider.dart';
import '../providers/main_map_search_ui_provider.dart';
import '../widgets/main_map_search_chrome.dart';
import '../widgets/map_facility_markers_layer.dart';
import '../widgets/city_overview_marker.dart';
import '../widgets/map_facility_preview_card.dart';
import '../widgets/misafirhane_map_marker.dart';
import '../widgets/misafirhane_marker_info_popup.dart';
import '../widgets/misafirhane_search_results_sheet.dart';
import '../widgets/rotalink_banner_ad.dart';
import '../widgets/rotalink_tile_layer.dart';
import '../widgets/map_weather_chip.dart';
import '../widgets/weather_bottom_sheet.dart';
import '../widgets/drawer_social_section.dart';
import '../services/review_repository.dart';
import 'route_plan_screen.dart';
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

const double _kOverviewCityZoomThreshold = 8;

const List<String> _kOverviewCityNames = <String>[
  'İstanbul',
  'Ankara',
  'İzmir',
  'Bursa',
  'Antalya',
  'Adana',
  'Konya',
  'Eskişehir',
  'Samsun',
  'Kastamonu',
  'Trabzon',
  'Erzurum',
  'Diyarbakır',
  'Mardin',
  'Van',
  'Kayseri',
  'Gaziantep',
  'Mersin',
  'Denizli',
  'Muğla',
  'Aydın',
];

String _normalizeCityKey(String raw) {
  const replacements = <String, String>{
    'ı': 'i',
    'İ': 'i',
    'I': 'i',
    'ş': 's',
    'Ş': 's',
    'ğ': 'g',
    'Ğ': 'g',
    'ü': 'u',
    'Ü': 'u',
    'ö': 'o',
    'Ö': 'o',
    'ç': 'c',
    'Ç': 'c',
  };
  final sb = StringBuffer();
  for (final rune in raw.trim().runes) {
    final ch = String.fromCharCode(rune);
    sb.write(replacements[ch] ?? ch.toLowerCase());
  }
  return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

final Set<String> _kOverviewCityKeys =
    _kOverviewCityNames.map(_normalizeCityKey).toSet();

final Map<String, LatLng> _kOverviewCityAnchorPoints = <String, LatLng>{
  'istanbul': LatLng(41.0082, 28.9784),
  'ankara': LatLng(39.9334, 32.8597),
  'izmir': LatLng(38.4237, 27.1428),
  'bursa': LatLng(40.1950, 29.0600),
  'antalya': LatLng(36.8969, 30.7133),
  'adana': LatLng(37.0000, 35.3213),
  'konya': LatLng(37.8746, 32.4932),
  'eskisehir': LatLng(39.7767, 30.5206),
  'samsun': LatLng(41.2867, 36.3300),
  'kastamonu': LatLng(41.3887, 33.7827),
  'trabzon': LatLng(41.0015, 39.7178),
  'erzurum': LatLng(39.9043, 41.2679),
  'diyarbakir': LatLng(37.9144, 40.2306),
  'mardin': LatLng(37.3212, 40.7245),
  'van': LatLng(38.4891, 43.4089),
  'kayseri': LatLng(38.7312, 35.4787),
  'gaziantep': LatLng(37.0662, 37.3833),
  'mersin': LatLng(36.8121, 34.6415),
  'denizli': LatLng(37.7765, 29.0864),
  'mugla': LatLng(37.2153, 28.3636),
  'aydin': LatLng(37.8450, 27.8396),
};

/// `activity_main.xml` + `MainActivity` ana iskeleti: çekmece, teal toolbar,
/// harita alanı, arama kartı, FAB’lar, banner alanı, alt gezinme çubuğu.
class MainMapScreen extends ConsumerStatefulWidget {
  const MainMapScreen({
    super.key,
    required this.repository,
    this.navBridge,
  });

  final FirebaseRotaRepository repository;
  final MainMapNavBridge? navBridge;

  @override
  ConsumerState<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends ConsumerState<MainMapScreen> with WidgetsBindingObserver {
  /// Harita pan/zoom event'lerinde sadece önizleme kartını yeniden çizmek için.
  /// [setState] yerine bu notifier güncellenir → tüm ekran rebuild olmaz.
  final ValueNotifier<int> _previewPositionTick = ValueNotifier<int>(0);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _mapController = MapController();
  final PopupController _popupController = PopupController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchBarFocusNode = FocusNode();

  LatLng _center = kTurkeyMapFallbackCenter;
  double _zoom = kTurkeyMapFallbackZoom;

  /// Kullanıcı haritayı kaydırdı/yakınlaştırdı — geri tuşu önce Türkiye görünümüne döner.
  bool _mapCameraUserAdjusted = false;

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

  /// Kotlin `loadListFromPrefs("favorites")`.
  List<Misafirhane> _favoritesCache = const [];

  /// Kotlin `isShowingFavorites` — harita işaretleri favori listesinden gelir.
  bool _favoritesBrowseActive = false;

  /// Marker seçiminde altta gösterilen önizleme kartı.
  Misafirhane? _mapPreviewFacility;

  /// Ana ekran genel Türkiye görünümünden il görünümüne marker dokunuşuyla geçildi mi.
  /// `null` ise henüz il odaklı görünüm yoktur.
  String? _mainMapFocusedCity;

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

  /// Geri tuşu: 1↓ 2↑ 3 uyarı 4 ana ekran (il araması paneli açıkken).
  int _searchBackPressCount = 0;

  /// Geri tuşu: önce paneli gizle → tekrar aç + çıkış hazır → ana ekran sıfırlama.
  bool readyToExit = false;

  /// Yalnızca açık arama sonuçları paneline bağlı; her açılışta yenilenir.
  DraggableScrollableController? _searchSheetExtentController;

  /// Arama sonuçları (Tesis/Gezi/…) paneli harita [Stack] içinde — Scaffold bottom sheet değil.
  bool _inlineTabbedSearchOpen = false;
  List<Misafirhane> _tabbedSheetFacilities = const [];
  RotaDataState? _tabbedSheetRotaData;
  Misafirhane? _tabbedSheetHighlight;
  int _tabbedSheetInitialTab = 0;
  String? _tabbedSheetGeziYemekHighlight;

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

  /// Arama / favori mesafe satırları için paylaşılan konum durumu.
  final MapLocationState _mapLocationState = MapLocationState();

  // ─── Marker önbelleği — her build'de yeni nesne oluşturulmasın ──────────────

  // ─── Ana ekran il özet marker önbelleği ───────────────────────────────────
  RotaDataState? _cachedOverviewCitiesData;
  List<_OverviewCitySummary>? _cachedOverviewCities;
  String? _cachedOverviewCitiesFilter;
  RotaDataState? _cachedOverviewCityMarkersData;
  List<Marker>? _cachedOverviewCityMarkers;
  String? _cachedOverviewCityMarkersFilter;

  // ─── Orta zoom görünür alan marker önbelleği ──────────────────────────────
  Timer? _viewportRefreshDebounce;

  // ─── İl listesi önbelleği ─────────────────────────────────────────────────
  List<String>? _cachedIlOptions;
  RotaDataState? _cachedIlOptionsSource;

  late final Stream<RotaDataState> _rotaStream;

  @override
  void initState() {
    super.initState();
    _cachedRotaData = widget.repository.currentState;
    _rotaStream = widget.repository.watchRoot();
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
        unawaited(AdService.instance.preloadInterstitial());
      }
      unawaited(_maybeOpenHolidaysFromNotification());
      unawaited(_checkForUpdate());
    });
    unawaited(_reloadFavoritesCache());
    _mapPreviewDismissSub = _mapController.mapEventStream.listen(_onMapControllerEvent);
    unawaited(_syncLocationUiFromPermissionOnly());
    _registerNavBridge();
  }

  void _registerNavBridge() {
    final bridge = widget.navBridge;
    if (bridge == null) return;
    bridge.resetToHome = _resetSearchToHome;
    bridge.openFavorites = _openFavoritesTab;
    bridge.openSearch = (ctx, data) =>
        _openSearchFromBottomNav(ctx, data ?? _cachedRotaData);
    bridge.openRoutePlan = _openRoutePlanning;
    bridge.handleSystemBack = _handleSystemBack;
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
    await Navigator.of(context).pushNamed(RotalinkShellRoutes.holidays);
  }

  Future<void> _checkForUpdate() async {
    if (!mounted || !context.mounted) return;
    
    final isUpdateRequired = await VersionCheckService.instance.isUpdateRequired();
    if (!isUpdateRequired) return;
    
    final currentVersion = await VersionCheckService.instance.getCurrentVersionInfo();
    final message = await VersionCheckService.instance.getUpdateMessage();
    final storeUrl = await VersionCheckService.instance.getStoreUrl();
    if (!mounted || !context.mounted) return;
    
    await UpdateRequiredDialog.show(
      context,
      currentVersion: currentVersion,
      message: message,
      storeUrl: storeUrl,
      onDismiss: () {
        // Kullanıcı daha sonra dediğinde tekrar kontrol etmemek için
        // SharedPreferences'a kaydedilebilir (isteğe bağlı)
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _previewPositionTick.dispose();
    _stopLocationStream();
    _dismissAttachedBottomSheet();
    _disposeSearchSheetExtentController();
    _mapPreviewDismissSub?.cancel();
    _viewportRefreshDebounce?.cancel();
    AdService.instance.disposeInterstitial();
    _searchController.dispose();
    _searchBarFocusNode.dispose();
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

  void _syncSearchPanelOpen(bool open) {
    ref.read(searchPanelOpenProvider.notifier).state = open;
    if (!open) {
      ref.read(searchPanelFacilitiesSourceProvider.notifier).state = const [];
    }
  }

  void _onSearchBarFocusChanged(bool focused) {
    ref.read(searchBarFocusedProvider.notifier).state = focused;
  }

  /// Ana harita ilk açılış / arama sıfırlandı.
  void resetToInitialState() {
    if (!mounted) return;
    ref.read(facilityTypeFilterProvider.notifier).state = kFacilityFilterAll;
    ref.read(searchBarFocusedProvider.notifier).state = false;
    _syncSearchPanelOpen(false);
    _popupController.hideAllPopups();
    _dismissAttachedBottomSheet();
    FocusManager.instance.primaryFocus?.unfocus();
    _searchController.clear();
    setState(() {
      readyToExit = false;
      isSheetVisible = true;
      _markerOverride = null;
      _mainMapFocusedCity = null;
      _searchSheetHighlight = null;
      _mapPreviewFacility = null;
      _favoritesBrowseActive = false;
      _clearRouteOnly();
      _mapCameraUserAdjusted = false;
    });
    setState(() => _searchBarSession++);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitTurkeyOverviewCamera();
    });
  }

  void _closeInlineTabbedSearchPanel() {
    if (!_inlineTabbedSearchOpen) return;
    _syncSearchPanelOpen(false);
    setState(() {
      _inlineTabbedSearchOpen = false;
      _tabbedSheetFacilities = const [];
      _tabbedSheetRotaData = null;
      _tabbedSheetHighlight = null;
      _tabbedSheetInitialTab = 0;
      _tabbedSheetGeziYemekHighlight = null;
      _searchBackPressCount = 0;
    });
    _disposeSearchSheetExtentController();
  }

  /// İl araması paneli açıkken geri tuşu adımları.
  Future<bool> _handleSearchPanelBack() async {
    if (!_inlineTabbedSearchOpen) return false;

    if (_searchController.text.trim().isEmpty) {
      _resetSearchToHome();
      return true;
    }

    _searchBackPressCount++;
    _lastExitBackAt = null;

    switch (_searchBackPressCount) {
      case 1:
        await _collapseSearchResultsSheet();
        if (mounted) setState(() => isSheetVisible = false);
        return true;
      case 2:
        await _expandSearchResultsSheet();
        if (mounted) setState(() => isSheetVisible = true);
        return true;
      case 3:
        await _collapseSearchResultsSheet();
        if (mounted) setState(() => isSheetVisible = false);
        return true;
      default:
        _resetSearchToHome();
        return true;
    }
  }

  /// Arama paneli + harita: ilk açılış görünümüne dön.
  void _resetSearchToHome() {
    if (!mounted) return;
    ref.read(facilityTypeFilterProvider.notifier).state = kFacilityFilterAll;
    ref.read(searchBarFocusedProvider.notifier).state = false;
    _syncSearchPanelOpen(false);
    _popupController.hideAllPopups();
    FocusManager.instance.primaryFocus?.unfocus();
    _closeInlineTabbedSearchPanel();
    _searchController.clear();
    setState(() {
      _searchBackPressCount = 0;
      readyToExit = false;
      isSheetVisible = true;
      _markerOverride = null;
      _mainMapFocusedCity = null;
      _searchSheetHighlight = null;
      _mapPreviewFacility = null;
      _favoritesBrowseActive = false;
      _misafirhaneFacilityPopupOpen = false;
      _clearRouteOnly();
      _mapCameraUserAdjusted = false;
    });
    setState(() => _searchBarSession++);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitTurkeyOverviewCamera();
    });
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
    _scheduleViewportFacilityRefresh(e);
  }

  /// Orta zoom'da harita kaydırılınca görünür alan tesis marker'larını günceller.
  void _scheduleViewportFacilityRefresh(MapEvent e) {
    if (!_isMainMapOverviewActive ||
        _mainMapFocusedCity != null ||
        _zoom < _kOverviewCityZoomThreshold) {
      return;
    }
    final shouldRefresh = e is MapEventMove ||
        e is MapEventFlingAnimation ||
        e is MapEventScrollWheelZoom ||
        e is MapEventDoubleTapZoom;
    if (!shouldRefresh) return;

    _viewportRefreshDebounce?.cancel();
    _viewportRefreshDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _onMapEventForPreview(MapEvent e) {
    if (_mapPreviewFacility == null) return;
    if (_shouldDismissPreviewForMapEvent(e)) {
      unawaited(_closeMapPreviewAnimated());
      return;
    }
    // Sadece önizleme kartını yeniden konumlandır — tüm ekranı rebuild etme.
    _previewPositionTick.value++;
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
      _mainMapFocusedCity = null;
      _favoritesBrowseActive = false;
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
      _mainMapFocusedCity = null;
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
          padding: const EdgeInsets.fromLTRB(8, 248, 8, 156),
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

  /// RTDB akışından güvenli veri; hata anında son başarılı snapshot kullanılır.
  RotaDataState? _effectiveRotaData(RotaDataState? snapshotData) {
    if (snapshotData != null && snapshotData.errorMessage != null) {
      return _cachedRotaData;
    }
    return snapshotData ?? _cachedRotaData;
  }

  /// Riverpod state build sırasında güncellenmez — kırmızı hata ekranını önler.
  void _publishRotaDataToProvider(RotaDataState data) {
    if (identical(ref.read(rotaDataStateProvider), data)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(rotaDataStateProvider.notifier).state = data;
    });
  }

  /// Harita marker/arama için tüm tesis listesi (il başına tek kayıt değil).
  List<Misafirhane> _allFacilitiesForMap(RotaDataState? snapshotData) {
    final effective = _effectiveRotaData(snapshotData);
    if (effective == null) return const [];
    return effective.aramaIcinTumTesisler;
  }

  LatLng _overviewCityCenter(String cityKey, List<Misafirhane> facilities) {
    // Yakın illerde (Kocaeli–Sakarya vb.) tesis kümesi yerine sabit il merkezi kullan.
    final anchor = _kOverviewCityAnchorPoints[cityKey];
    if (anchor != null) return anchor;

    final points = facilities
        .where(_validFacilityCoords)
        .map((m) => LatLng(m.latitude, m.longitude))
        .toList();
    if (points.isEmpty) {
      return kTurkeyMapFallbackCenter;
    }
    if (points.length == 1) {
      return points.first;
    }
    return LatLngBounds.fromPoints(points).center;
  }

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
    if (_favoritesBrowseActive) {
      return _resolveSavedAgainstLive(_favoritesCache, effective);
    }
    if (effective == null) return const [];
    return _markerOverride ?? effective.misafirhaneler;
  }

  List<_OverviewCitySummary> _overviewCitySummaries(
    RotaDataState? snapshotData,
    String typeFilter,
  ) {
    final effective = _effectiveRotaData(snapshotData);
    if (effective == null) return const [];
    if (identical(effective, _cachedOverviewCitiesData) &&
        _cachedOverviewCitiesFilter == typeFilter &&
        _cachedOverviewCities != null) {
      return _cachedOverviewCities!;
    }

    final groups = <String, List<Misafirhane>>{
      for (final city in _kOverviewCityNames) _normalizeCityKey(city): <Misafirhane>[],
    };
    final seenByCity = <String, Set<String>>{
      for (final city in _kOverviewCityNames) _normalizeCityKey(city): <String>{},
    };

    // Tüm tesisler üzerinden il bazlı sayım — misafirhaneler yalnızca il başına 1 kayıt içerir.
    for (final facility in effective.aramaIcinTumTesisler) {
      if (!facilityMatchesTypeFilter(facility.tip, typeFilter)) continue;
      final cityKey = _normalizeCityKey(facility.il);
      if (!_kOverviewCityKeys.contains(cityKey)) continue;
      final citySeen = seenByCity[cityKey]!;
      if (!citySeen.add(facility.stableFacilityId)) continue;
      groups[cityKey]!.add(facility);
    }

    final summaries = <_OverviewCitySummary>[];
    for (final city in _kOverviewCityNames) {
      final cityKey = _normalizeCityKey(city);
      final facilities = groups[cityKey]!;
      if (facilities.isEmpty) continue;
      summaries.add(
        _OverviewCitySummary(
          cityName: city,
          facilities: List<Misafirhane>.unmodifiable(facilities),
          center: _overviewCityCenter(cityKey, facilities),
        ),
      );
    }

    _cachedOverviewCitiesData = effective;
    _cachedOverviewCitiesFilter = typeFilter;
    _cachedOverviewCities = summaries;
    return summaries;
  }

  List<Marker> _overviewCityMarkersFor(
    RotaDataState? snapshotData,
    String typeFilter,
  ) {
    final effective = _effectiveRotaData(snapshotData);
    if (effective == null) return const [];
    if (identical(effective, _cachedOverviewCityMarkersData) &&
        _cachedOverviewCityMarkersFilter == typeFilter &&
        _cachedOverviewCityMarkers != null) {
      return _cachedOverviewCityMarkers!;
    }

    final markers = _overviewCitySummaries(effective, typeFilter)
        .map(
          (summary) => Marker(
            point: summary.center,
            width: summary.markerSize,
            height: summary.markerSize,
            alignment: Alignment.center,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _handleOverviewCityTap(summary),
              child: CityOverviewMarker(
                cityName: summary.cityName,
                facilityCount: summary.facilityCount,
                size: summary.markerSize,
              ),
            ),
          ),
        )
        .toList(growable: false);

    _cachedOverviewCityMarkersData = effective;
    _cachedOverviewCityMarkersFilter = typeFilter;
    _cachedOverviewCityMarkers = markers;
    return markers;
  }

  List<Misafirhane> _visibleOverviewFacilities(RotaDataState? snapshotData) {
    final effective = _effectiveRotaData(snapshotData);
    if (effective == null) return const [];

    LatLngBounds visibleBounds;
    try {
      visibleBounds = _mapController.camera.visibleBounds;
    } catch (_) {
      return const [];
    }

    const margin = 0.20;
    final paddedBounds = LatLngBounds.unsafe(
      north: math.min(LatLngBounds.maxLatitude, visibleBounds.north + margin),
      south: math.max(LatLngBounds.minLatitude, visibleBounds.south - margin),
      east: math.min(LatLngBounds.maxLongitude, visibleBounds.east + margin),
      west: math.max(LatLngBounds.minLongitude, visibleBounds.west - margin),
    );

    final seen = <String>{};
    return effective.aramaIcinTumTesisler
        .where(_validFacilityCoords)
        .where((m) => seen.add(m.stableFacilityId))
        .where((m) => paddedBounds.contains(LatLng(m.latitude, m.longitude)))
        .toList(growable: false);
  }

  List<Misafirhane> _mapFacilitiesForCurrentZoom(
    RotaDataState? snapshotData, {
    required bool inRoute,
  }) {
    if (inRoute) return const [];
    if (_isMainMapOverviewActive && _zoom < _kOverviewCityZoomThreshold) {
      return const [];
    }
    if (_isMainMapOverviewActive &&
        _mainMapFocusedCity == null &&
        _zoom >= _kOverviewCityZoomThreshold) {
      return _visibleOverviewFacilities(snapshotData);
    }
    return _markersSource(snapshotData);
  }

  Future<void> _reloadFavoritesCache() async {
    final list = await _favoritesRepo.load();
    if (!mounted) return;
    setState(() => _favoritesCache = list);
  }

  /// Önbellekten il listesi — veri değişmedikçe yeniden sıralanmaz.
  List<String>? _getIlOptions(RotaDataState? data) {
    if (data == null) return null;
    if (identical(data, _cachedIlOptionsSource) && _cachedIlOptions != null) {
      return _cachedIlOptions;
    }
    _cachedIlOptionsSource = data;
    _cachedIlOptions = MainMapSearch.distinctSortedIller(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    return _cachedIlOptions;
  }

  void _onMisafirhanePopupEvent(PopupEvent event, List<Marker> selectedMarkers) {
    _misafirhaneFacilityPopupOpen =
        selectedMarkers.any((m) => m is MisafirhaneMapMarker);
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

  bool get _isMainMapOverviewActive =>
      _markerOverride == null &&
      !_favoritesBrowseActive &&
      (_activeRouteStops == null || _activeRouteStops!.isEmpty);

  bool get _hasMainMapUiOverlay {
    if (_inlineTabbedSearchOpen && _searchController.text.trim().isNotEmpty) {
      return false;
    }
    return !_isMainMapOverviewActive ||
        _attachedBottomSheet != null ||
        _mainMapFocusedCity != null ||
        _searchController.text.trim().isNotEmpty ||
        _mapPreviewFacility != null ||
        _misafirhaneFacilityPopupOpen;
  }

  bool get _shouldInterceptMainMapMarkerTap =>
      _isMainMapOverviewActive && _mainMapFocusedCity == null;

  void _handleMarkerTapOnMainOverview(Marker marker) {
    if (marker is! MisafirhaneMapMarker) return;
    final cityKey = _normalizeCityKey(marker.misafirhane.il);
    _OverviewCitySummary? summary;
    for (final item in _overviewCitySummaries(
      _cachedRotaData,
      ref.read(facilityTypeFilterProvider),
    )) {
      if (_normalizeCityKey(item.cityName) == cityKey) {
        summary = item;
        break;
      }
    }
    if (summary == null) return;
    _handleOverviewCityTap(summary);
  }

  void _handleOverviewCityTap(_OverviewCitySummary summary) {
    if (summary.facilities.isEmpty) return;
    final data = _cachedRotaData;
    if (data == null || !mounted) return;

    _popupController.hideAllPopups();
    _dismissAttachedBottomSheet();

    _searchController.text = summary.cityName;

    setState(() {
      _lastExitBackAt = null;
      _mainMapFocusedCity = null;
      _markerOverride = summary.facilities;
      _searchSheetHighlight = null;
      _mapPreviewFacility = null;
      _misafirhaneFacilityPopupOpen = false;
      readyToExit = false;
      isSheetVisible = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !context.mounted) return;
      _fitFacilitiesCamera(summary.facilities);
      await Future<void>.delayed(const Duration(milliseconds: 140));
      if (!mounted || !context.mounted) return;
      await _openTabbedSearchResults(
        context,
        data,
        summary.facilities,
      );
    });
  }

  void _maybeRestoreOverviewMarkers(double nextZoom) {
    if (_mainMapFocusedCity == null || nextZoom >= _kOverviewCityZoomThreshold) {
      return;
    }
    _popupController.hideAllPopups();
    setState(() {
      _lastExitBackAt = null;
      _mainMapFocusedCity = null;
      _markerOverride = null;
      _searchSheetHighlight = null;
      _mapPreviewFacility = null;
      _misafirhaneFacilityPopupOpen = false;
    });
  }

  void _restoreCameraAfterPreviewClose() {
    if (!mounted) return;
    if (_markerOverride != null && _markerOverride!.isNotEmpty) {
      _fitFacilitiesCamera(_markerOverride!);
      return;
    }
    if (_mainMapFocusedCity != null && _mainMapFocusedCity!.trim().isNotEmpty) {
      final focusedKey = _normalizeCityKey(_mainMapFocusedCity!);
      final focusedCityFacilities = _allFacilitiesForMap(_cachedRotaData)
          .where((m) => _normalizeCityKey(m.il) == focusedKey)
          .toList();
      if (focusedCityFacilities.any(_validFacilityCoords)) {
        _fitFacilitiesCamera(focusedCityFacilities);
        return;
      }
    }
    if (_favoritesBrowseActive) {
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

    if (await _handleSearchPanelBack()) {
      return;
    }

    if (ref.read(searchBarFocusedProvider)) {
      _lastExitBackAt = null;
      ref.read(searchBarFocusedProvider.notifier).state = false;
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }

    if (_hasMainMapUiOverlay) {
      _lastExitBackAt = null;
      resetToInitialState();
      return;
    }

    if (_isMainMapOverviewActive &&
        (_mapCameraUserAdjusted || _zoom >= _kOverviewCityZoomThreshold)) {
      _lastExitBackAt = null;
      _mapCameraUserAdjusted = false;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitTurkeyOverviewCamera();
      });
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
      _mainMapFocusedCity = null;
      _favoritesBrowseActive = true;
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

  Future<void> _openSearchFromBottomNav(
    BuildContext context,
    RotaDataState? data,
  ) async {
    if (data == null) {
      _toast(context, AppStrings.mapDataLoading);
      return;
    }
    _popupController.hideAllPopups();
    setState(() {
      _favoritesBrowseActive = false;
      _mapPreviewFacility = null;
    });

    // Ara: yalnızca üst arama çubuğuna odaklan; sekmeli alt panel açılmasın.
    _closeInlineTabbedSearchPanel();

    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      await _performSearch(context, data);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchBarFocusNode.requestFocus();
    });
  }

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
      final granted = await SimpleLocationService.isLocationGranted();
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
      final granted = await SimpleLocationService.isLocationGranted();
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
    if (await SimpleLocationService.isLocationGranted() &&
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
    if (await SimpleLocationService.isLocationGranted() &&
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
    if (!await SimpleLocationService.isLocationGranted()) return;
    await _applyLocationAfterPermissionGranted();
    await _reopenSearchSheetIfLocationGranted();
  }

  Future<void> _reopenSearchSheetIfLocationGranted() async {
    await _syncLocationUiFromPermissionOnly();
    if (!mounted) return;
    if (!await SimpleLocationService.isLocationGranted()) return;
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
        _mainMapFocusedCity = null;
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
      _searchBackPressCount = 0;
      _mainMapFocusedCity = null;
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
    int initialTabIndex = 0,
    String? geziYemekHighlight,
  }) async {
    try {
      if (!mounted || !context.mounted) return;
      final granted = await SimpleLocationService.isLocationGranted();
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
    ref.read(searchPanelFacilitiesSourceProvider.notifier).state =
        List<Misafirhane>.unmodifiable(sorted);
    setState(() {
      readyToExit = reopenNextBackExitsSearch;
      isSheetVisible = true;
      _searchBackPressCount = 0;
      _inlineTabbedSearchOpen = true;
      _tabbedSheetFacilities = sorted;
      _tabbedSheetRotaData = data;
      _tabbedSheetHighlight = resolvedHighlight;
      _tabbedSheetInitialTab = initialTabIndex;
      _tabbedSheetGeziYemekHighlight = geziYemekHighlight;
    });
    _syncSearchPanelOpen(true);
    // Arama sonuçları açılınca izin yoksa otomatik iste (oturumda red yoksa).
    if (mounted &&
        !await SimpleLocationService.isLocationGranted() &&
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
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      drawer: _buildDrawer(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: StreamBuilder<RotaDataState>(
              stream: _rotaStream,
              initialData: _cachedRotaData ?? widget.repository.currentState,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data != null && data.errorMessage == null) {
                  _cachedRotaData = data;
                  _publishRotaDataToProvider(data);
                }
                final rotaForUi = (data != null && data.errorMessage != null)
                    ? _cachedRotaData
                    : (data ?? _cachedRotaData);
                final loading = !snapshot.hasData &&
                    snapshot.connectionState == ConnectionState.waiting;
                final inRoute =
                    _activeRouteStops != null && _activeRouteStops!.isNotEmpty;
                final rawDisplay = _markersSource(data);
                final baseDisplay = _mapFacilitiesForCurrentZoom(
                  data,
                  inRoute: inRoute,
                );
                final routeMarkers = (inRoute && rotaForUi != null)
                    ? <Marker>[
                        ..._markersForRoute(rotaForUi, _activeRouteStops!),
                        ..._routeLabelMarkers,
                      ]
                    : const <Marker>[];
                final showOverviewCityMarkers =
                    !inRoute &&
                    _isMainMapOverviewActive &&
                    _zoom < _kOverviewCityZoomThreshold;
                final showFacilityMarkers = !inRoute && baseDisplay.isNotEmpty;
                /// Arama sekmeli sheet açıkken tam görünürken gizlenir; aşağı indirilince
                /// yukarı ok FAB ile tekrar açılabilir.
                final showExpandSearchPanelFab =
                    _inlineTabbedSearchOpen && !isSheetVisible;
                final searchSheetFab = _markerOverride != null &&
                    !inRoute &&
                    !_favoritesBrowseActive &&
                    ((!_inlineTabbedSearchOpen && _attachedBottomSheet == null) ||
                        showExpandSearchPanelFab);
                final showListFab = inRoute ||
                    _favoritesBrowseActive ||
                    searchSheetFab;

                if (loading &&
                    _cachedRotaData == null &&
                    rawDisplay.isEmpty &&
                    !inRoute) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                if (snapshot.hasError &&
                    _cachedRotaData == null &&
                    rawDisplay.isEmpty &&
                    !inRoute) {
                  return Center(child: Text('Hata: ${snapshot.error}'));
                }
                if (data?.errorMessage != null &&
                    _cachedRotaData == null &&
                    rawDisplay.isEmpty &&
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
                final searchChromeTop =
                    toolbarBottom + MainMapSearchChrome.topGapBelowToolbar;
                final searchChromeActive = ref.watch(isMapSearchChromeActiveProvider);
                final hideMapOverlayButtons =
                    searchChromeActive && !showExpandSearchPanelFab;
                final onboarding = RotalinkShellScope.maybeOf(context)?.onboarding;

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
                              final prevZoom = _zoom;
                              final nextZoom = clampZoom(pos.zoom);
                              final wasOverviewZoom =
                                  prevZoom < _kOverviewCityZoomThreshold;
                              final isOverviewZoom =
                                  nextZoom < _kOverviewCityZoomThreshold;
                              _zoom = nextZoom;
                              if (hasGesture) {
                                _maybeRestoreOverviewMarkers(nextZoom);
                                if (_isMainMapOverviewActive &&
                                    !_inlineTabbedSearchOpen &&
                                    _attachedBottomSheet == null &&
                                    _mainMapFocusedCity == null &&
                                    _searchController.text.trim().isEmpty &&
                                    _mapPreviewFacility == null &&
                                    !_misafirhaneFacilityPopupOpen) {
                                  _mapCameraUserAdjusted = true;
                                }
                              }
                              // Zoom eşiği geçildiğinde il/tesis marker geçişini tetikle.
                              if (wasOverviewZoom != isOverviewZoom &&
                                  _isMainMapOverviewActive &&
                                  _mainMapFocusedCity == null) {
                                setState(() {});
                              }
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
                            const RotalinkTileLayer(),
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
                              MapOverviewCityMarkersLayer(
                                visible: showOverviewCityMarkers,
                                buildMarkers: (filter) =>
                                    _overviewCityMarkersFor(rotaForUi, filter),
                              ),
                              MapFacilityPopupMarkersLayer(
                                baseFacilities: baseDisplay,
                                highlight: _searchSheetHighlight,
                                visible: showFacilityMarkers,
                                popupController: _popupController,
                                onMarkerTap: (
                                  popupSpec,
                                  popupState,
                                  popupController,
                                ) {
                                  if (_shouldInterceptMainMapMarkerTap) {
                                    _handleMarkerTapOnMainOverview(popupSpec.marker);
                                    return;
                                  }

                                  if (popupState.selectedPopupSpecs.contains(popupSpec)) {
                                    popupController.hideAllPopups();
                                  } else {
                                    popupController.showPopupsOnlyForSpecs([popupSpec]);
                                  }
                                },
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
                          '${_tabbedSheetFacilities.length}-${_searchSheetHighlight?.stableFacilityId ?? 'h'}-$_tabbedSheetInitialTab-${_tabbedSheetGeziYemekHighlight ?? ''}',
                        ),
                        sheetExtentController: _searchSheetExtentController!,
                        rotaData: _tabbedSheetRotaData!,
                        mapLocationState: _mapLocationState,
                        highlightTarget: _tabbedSheetHighlight,
                        initialTabIndex: _tabbedSheetInitialTab,
                        geziYemekHighlight: _tabbedSheetGeziYemekHighlight,
                        favoritesRepo: _favoritesRepo,
                        onFavoritesChanged: _reloadFavoritesCache,
                        onTesisSelect: (m) async {
                          _showMisafirhanePopupFor(m);
                        },
                        onRequestLocationPermission: _onSearchSheetRequestLocation,
                        onClosePanel: _closeInlineTabbedSearchPanel,
                      ),
                    ValueListenableBuilder<int>(
                      valueListenable: _previewPositionTick,
                      builder: (__, a, b) {
                        if (_mapPreviewFacility == null) return const SizedBox.shrink();
                        return LayoutBuilder(
                          builder: (context, constraints) {
                          final m = _mapPreviewFacility!;
                          const cardWMax = 200.0;
                          // ~2 satır + padding; marker ile boşluk
                          const estCardH = 52.0;
                          const markerHalf = 20.0;
                          const gapAboveMarker = 8.0;
                          final minTopBelowSearch =
                              toolbarBottom + MainMapSearchChrome.blockHeight + 8;
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
                        );
                      },
                    ),
                    Positioned(
                      right: 16,
                      bottom: 8,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        opacity: (hideMapOverlayButtons && !showExpandSearchPanelFab)
                            ? 0
                            : 1,
                        child: IgnorePointer(
                          ignoring: hideMapOverlayButtons && !showExpandSearchPanelFab,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (showExpandSearchPanelFab)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10, right: 2),
                                  child: FloatingActionButton(
                                    heroTag: 'fab_expand_search',
                                    backgroundColor: AppColors.primary,
                                    elevation: 12,
                                    onPressed: () async {
                                      await _expandSearchResultsSheet();
                                      if (mounted) {
                                        setState(() => isSheetVisible = true);
                                      }
                                    },
                                    tooltip: 'Arama sonuçlarını aç',
                                    child: const Icon(
                                      Icons.keyboard_arrow_up_rounded,
                                      color: AppColors.white,
                                    ),
                                  ),
                                ),
                              if (showListFab && !showExpandSearchPanelFab)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10, right: 2),
                                  child: FloatingActionButton(
                                    heroTag: 'fab_list',
                                    backgroundColor: AppColors.primary,
                                    elevation: 12,
                                    onPressed: () async {
                                      final mapFacilities = ref.read(
                                        filteredFacilitiesProvider(baseDisplay),
                                      );
                                      if (inRoute) {
                                        await _openRouteSummarySheet(
                                          context,
                                          _activeRouteStops!,
                                          totalDistanceM: _routeSummaryDistanceM,
                                          totalDurationS: _routeSummaryDurationS,
                                          navWaypoints: rotaForUi != null
                                              ? waypointsForRouteStops(
                                                  rotaForUi,
                                                  _activeRouteStops!,
                                                )
                                              : null,
                                        );
                                      } else if (_favoritesBrowseActive) {
                                        _openMisafirhaneSheet(
                                          mapFacilities,
                                          liveFavoriteList: true,
                                        );
                                      } else if (rotaForUi != null) {
                                        await _openTabbedSearchResults(
                                          context,
                                          rotaForUi,
                                          mapFacilities,
                                          highlightTarget: _searchSheetHighlight,
                                        );
                                      }
                                    },
                                    tooltip: inRoute
                                        ? AppStrings.routePlanSummaryTitle
                                        : AppStrings.fabMisafirhaneList,
                                    child: const Icon(
                                      Icons.view_list_rounded,
                                      color: AppColors.white,
                                    ),
                                  ),
                                ),
                              if (!showListFab &&
                                  !_inlineTabbedSearchOpen &&
                                  _attachedBottomSheet == null) ...[
                                KamiMapOverlay(
                                  repository: widget.repository,
                                  initialData: _cachedRotaData,
                                  userLocationHint: _userLocationLatLng,
                                  fabAnchorKey: onboarding?.targetKey(
                                    OnboardingTarget.kami,
                                  ),
                                  onRoutePlan: (outcome) async {
                                    final data = _cachedRotaData;
                                    if (data == null) return;
                                    await _applyRoutePlan(
                                      context,
                                      data,
                                      outcome.stops,
                                      precomputedSegments: outcome.segments,
                                    );
                                  },
                                ),
                                const IgnorePointer(
                                  child: SizedBox(
                                    height: KamiMapOverlay.gapAboveEmergencyFab,
                                  ),
                                ),
                                _EmergencyFab(
                                  anchorKey: onboarding?.targetKey(
                                    OnboardingTarget.emergency,
                                  ),
                                  onTap: () =>
                                      unawaited(showEmergencyBottomSheet(context)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _RotalinkToolbar(
                        onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                        onTitleTap: _goToInitialMapHome,
                        menuAnchorKey: onboarding?.targetKey(OnboardingTarget.menu),
                        trailing: KeyedSubtree(
                          key: onboarding?.targetKey(OnboardingTarget.weather),
                          child: MapWeatherChip(
                            compact: true,
                            liveGps: _userLocationLatLng,
                            locationGranted:
                                _mapLocationState.locationPermissionGranted,
                            focusedCity: _mainMapFocusedCity,
                            mapCenter: _center,
                            rotaData: rotaForUi,
                          ),
                        ),
                      ),
                    ),
                    MainMapSearchChrome(
                      anchorKey: onboarding?.targetKey(OnboardingTarget.searchChrome),
                      top: searchChromeTop,
                      searchBarSession: _searchBarSession,
                      controller: _searchController,
                      ilOptionsSorted: _getIlOptions(rotaForUi),
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
                      focusNode: _searchBarFocusNode,
                      onFocusChanged: _onSearchBarFocusChanged,
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
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
  }) {
    _popupController.hideAllPopups();
    _dismissAttachedBottomSheet();
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState == null) return;
    final ctrl = scaffoldState.showBottomSheet(
      (sheetCtx) => StatefulBuilder(
          builder: (ctx, setModal) {
            List<Misafirhane> rows() {
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
              if (liveFavoriteList) {
                setState(() {});
              }
            }

            Future<void> requestLocationFromCompactSheet() async {
              await _ensureLocationPermissionAndLocationForLists(
                fromDistanceChip: true,
              );
              if (!mounted || !await SimpleLocationService.isLocationGranted()) return;
              if (!sheetCtx.mounted) return;
              Navigator.pop(sheetCtx);
              if (!mounted) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _openMisafirhaneSheet(
                  items,
                  liveFavoriteList: liveFavoriteList,
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

  Future<void> _openRoutePlanning() async {
    final outcome = await pushOnShellNavigator<RoutePlanOutcome>(
      MaterialPageRoute<RoutePlanOutcome>(
        builder: (_) => RoutePlanScreen(
          repository: widget.repository,
          embeddedInShell: true,
        ),
      ),
    );
    if (outcome == null || outcome.stops.isEmpty) {
      widget.navBridge?.onRoutePlanningDismissed?.call();
      return;
    }
    final data = _cachedRotaData;
    if (data == null || !mounted) return;
    await _applyRoutePlan(
      context,
      data,
      outcome.stops,
      precomputedSegments: outcome.segments,
    );
    widget.navBridge?.onRoutePlanningDismissed?.call();
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
      _mainMapFocusedCity = null;
      _favoritesBrowseActive = false;
      _markerOverride = null;
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
      final lites = stops.map(RouteStopLite.fromRouteStop).toList();
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
                    Navigator.of(context).pushNamed(RotalinkShellRoutes.holidays);
                  },
                ),
                _DrawerTile(
                  icon: Icons.send_outlined,
                  title: AppStrings.drawerSuggestion,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).pushNamed(RotalinkShellRoutes.suggestion);
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
                const DrawerSocialSection(),
                _DrawerTile(
                  icon: Icons.info_outline,
                  title: AppStrings.drawerAbout,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).pushNamed(RotalinkShellRoutes.about);
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
    await Share.share(StoreLinks.drawerShareMessage());
  }
}

/// Düz teal üst çubuk — yuvarlak köşe yok.
class _RotalinkToolbar extends StatelessWidget {
  const _RotalinkToolbar({
    required this.onMenu,
    required this.onTitleTap,
    this.menuAnchorKey,
    this.trailing,
  });

  final VoidCallback onMenu;
  final VoidCallback onTitleTap;
  final Key? menuAnchorKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      elevation: 4,
      color: AppColors.primary,
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, top, 8, 0),
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              KeyedSubtree(
                key: menuAnchorKey,
                child: IconButton(
                  onPressed: onMenu,
                  tooltip: AppStrings.menuOpen,
                  icon: const Icon(Icons.menu, color: AppColors.white),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: onTitleTap,
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
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyFab extends StatelessWidget {
  const _EmergencyFab({
    required this.onTap,
    this.anchorKey,
  });

  final VoidCallback onTap;
  final Key? anchorKey;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: anchorKey,
      child: Tooltip(
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
      ),
    );
  }
}

class _OverviewCitySummary {
  const _OverviewCitySummary({
    required this.cityName,
    required this.facilities,
    required this.center,
  });

  final String cityName;
  final List<Misafirhane> facilities;
  final LatLng center;

  int get facilityCount => facilities.length;

  double get markerSize => facilityCount >= 100 ? 30 : 26;
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
