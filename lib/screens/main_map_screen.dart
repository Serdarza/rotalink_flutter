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
import 'package:share_plus/share_plus.dart';

import '../constants/store_links.dart';
import '../data/app_rating_prefs.dart';
import '../data/facility_address_repository.dart';
import '../data/favorites_repository.dart';
import '../data/firebase_rota_repository.dart';
import '../data/recent_search_store.dart';
import '../deeplink/deep_link_service.dart';
import '../deeplink/deep_link_target.dart';
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
import '../services/announcement_notification_scheduler.dart';
import '../services/holiday_notification_scheduler.dart';
import '../services/version_check_service.dart';
import '../widgets/update_required_dialog.dart';
import '../services/simple_location_service.dart';
import '../theme/app_colors.dart';
import '../theme/system_ui.dart';
import '../utils/geo_helpers.dart';
import '../utils/facility_phone_dialer.dart';
import '../utils/maps_launch.dart';
import '../utils/misafirhane_compact_sheet_height.dart';
import '../utils/route_facility_lookup.dart';
import '../utils/safe_map_coordinates.dart';
import '../utils/il_ilce.dart';
import '../utils/main_map_search.dart';
import '../widgets/app_rating_dialog.dart';
import '../widgets/distance_permission_chip.dart';
import '../widgets/facility_detail_card.dart';
import '../providers/facility_filter_provider.dart';
import '../providers/main_map_search_ui_provider.dart';
import '../widgets/main_map_search_chrome.dart';
import '../widgets/map_facility_markers_layer.dart';
import '../widgets/city_overview_marker.dart';
import '../widgets/map_facility_preview_card.dart';
import '../widgets/misafirhane_map_marker.dart';
import '../widgets/misafirhane_search_results_sheet.dart';
import '../widgets/rotalink_tile_layer.dart';
import '../widgets/map_weather_chip.dart';
import '../widgets/emergency_bottom_sheet.dart';
import '../widgets/weather_bottom_sheet.dart';
import '../widgets/rotalink_app_drawer.dart';
import '../widgets/rotalink_app_header.dart';
import '../services/review_repository.dart';
import 'route_plan_screen.dart';
import 'yorum_screen.dart';

/// Yüksek doğruluk istemez; aksi halde Google Play "Konum doğruluğu" penceresi sık tetiklenir.
const _kRotalinkLocationSettingsLow = LocationSettings(
  accuracy: LocationAccuracy.low,
  timeLimit: Duration(seconds: 12),
);

/// Canlı konum: ~25 m veya yeni fix → mesafe satırları güncellenir.
const _kLocationStreamSettings = LocationSettings(
  accuracy: LocationAccuracy.low,
  distanceFilter: 25,
);

const double _kOverviewCityZoomThreshold = 8;

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
  const MainMapScreen({super.key, required this.repository, this.navBridge});

  final FirebaseRotaRepository repository;
  final MainMapNavBridge? navBridge;

  @override
  ConsumerState<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends ConsumerState<MainMapScreen>
    with WidgetsBindingObserver {
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

  /// Harita pin'inden açılan Google Maps tarzı alt detay kartı.
  Misafirhane? _mapMarkerDetailFacility;

  /// Ana ekran genel Türkiye görünümünden il görünümüne marker dokunuşuyla geçildi mi.
  /// `null` ise henüz il odaklı görünüm yoktur.
  String? _mainMapFocusedCity;

  /// Aktif aramada baskın il — hava durumu bu ile göre gösterilir.
  String? _weatherSearchCity;

  /// Önizleme kapanırken kısa çıkış animasyonu (harita kaydırma / dokunuş ile tetiklenir).
  bool _previewClosing = false;

  /// Ana haritada misafirhane marker bilgi balonu açık mı ([PopupMarkerLayer]).
  bool _misafirhaneFacilityPopupOpen = false;

  StreamSubscription<MapEvent>? _mapPreviewDismissSub;

  /// Arama sonucu listesinde kaydırılacak tesis (FAB ile sheet açılınca kullanılır).
  Misafirhane? _searchSheetHighlight;

  /// [showBottomSheet] ile açılan kalıcı alt sayfa — modal bariyer yok; yenisi açılmadan kapatılır.
  PersistentBottomSheetController? _attachedBottomSheet;

  /// Arama sonuç paneli: `true` = Liste görünümü (varsayılan, harita gizli),
  /// `false` = Harita görünümü. Panel/harita widget'ları yeniden oluşturulmaz.
  bool isSheetVisible = true;

  /// Geri tuşu / arama paneli durumu.
  bool readyToExit = false;

  /// Arama sonuçları paneli — detay kartı geri tuşu için.
  final GlobalKey<MisafirhaneSearchResultsPanelState> _searchResultsPanelKey =
      GlobalKey<MisafirhaneSearchResultsPanelState>();

  /// Favori / kompakt liste sheet'inde detay açıksa kapatmak için.
  VoidCallback? _closeCompactFacilityDetail;
  bool _compactFacilityDetailOpen = false;

  /// Arama sonuçları (Konaklama/Gezi/…) paneli harita [Stack] içinde — Scaffold bottom sheet değil.
  bool _inlineTabbedSearchOpen = false;
  bool _facilityDetailVisible = false;
  bool get _detailPresentationVisible =>
      (_inlineTabbedSearchOpen && _facilityDetailVisible) ||
      _compactFacilityDetailOpen ||
      _mapMarkerDetailFacility != null;
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
    ref.listenManual<IlceSelection?>(
      facilityIlceFilterProvider,
      _onIlceFilterChanged,
    );
    unawaited(RotalinkSystemUi.applyEdgeToEdge());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeOpenHolidaysFromNotification());
      unawaited(_checkForUpdate());
    });
    unawaited(_reloadFavoritesCache());
    _mapPreviewDismissSub = _mapController.mapEventStream.listen(
      _onMapControllerEvent,
    );
    unawaited(_syncLocationUiFromPermissionOnly());
    _registerNavBridge();
    DeepLinkService.instance.pending.addListener(_onDeepLinkPending);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onDeepLinkPending());
  }

  void _registerNavBridge() {
    final bridge = widget.navBridge;
    if (bridge == null) return;
    bridge.resetToHome = _resetSearchToHome;
    bridge.openFavorites = _openFavoritesTab;
    bridge.openSearch = (ctx, data) =>
        _openSearchFromBottomNav(ctx, data ?? _cachedRotaData);
    bridge.openSearchQuery = (ctx, query) async {
      final data = _cachedRotaData;
      if (data == null) {
        _toast(ctx, AppStrings.mapDataLoading);
        return;
      }
      _searchController.text = query.trim();
      await _performSearch(ctx, data);
      await _waitUntilSearchResultsVisible();
    };
    bridge.isFacilityDetailOpen = () => _detailPresentationVisible;
    bridge.openCategory = _openCategoryFromDashboard;
    bridge.feedbackFacility = () =>
        _searchResultsPanelKey.currentState?.visibleFacility ??
        _mapPreviewFacility;
    bridge.openFacility = (ctx, facility) async {
      final data = _cachedRotaData;
      if (data == null || !mounted) return;
      await _openTabbedSearchResults(
        ctx,
        data,
        [facility],
        highlightTarget: facility,
        requestLocation: false,
      );
      await _openFacilityDetailInPanel(facility);
    };
    bridge.openRoutePlan = _openRoutePlanning;
    bridge.applyRoutePlan = (outcome) async {
      final data = _cachedRotaData;
      if (data == null || !mounted) return;
      await _applyRoutePlan(
        context,
        data,
        outcome.stops,
        precomputedSegments: outcome.segments,
      );
    };
    bridge.openMenu = () => _scaffoldKey.currentState?.openDrawer();
    bridge.openWeather = (ctx) => showWeatherBottomSheet(ctx);
    bridge.openEmergency = (ctx) => showEmergencyBottomSheet(ctx);
    bridge.hasActiveOverlay = () => _hasMainMapUiOverlay;
    bridge.handleSystemBack = _handleSystemBack;
  }

  Future<void> _openCategoryFromDashboard(
    BuildContext context,
    int tabIndex,
  ) async {
    final data = _cachedRotaData;
    if (data == null) {
      _toast(context, AppStrings.mapDataLoading);
      return;
    }
    _popupController.hideAllPopups();
    _searchController.clear();
    setState(() {
      _favoritesBrowseActive = false;
      _mainMapFocusedCity = null;
      _markerOverride = null;
      _mapPreviewFacility = null;
    });
    final safeTabIndex = tabIndex < 0 ? 0 : (tabIndex > 5 ? 5 : tabIndex);
    await _openTabbedSearchResults(
      context,
      data,
      data.misafirhaneler,
      initialTabIndex: safeTabIndex,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopLocationStream(); // Arka planda stream durdur — pil tasarrufu
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshLocationStateOnResume());
      unawaited(
        HolidayNotificationScheduler.scheduleUpcomingHolidayReminders(),
      );
      unawaited(AnnouncementNotificationScheduler.sync(forceFetch: false));
      unawaited(_maybeOpenHolidaysFromNotification());
    }
  }

  // ─── Konum stream yönetimi ──────────────────────────────────────────────────

  /// İzin ve GPS varsa sürekli konum güncellemesi başlatır.
  /// Konum değişince [_mapLocationState] güncellenir → arama listesinde mesafe yenilenir.
  void _startLocationStream() {
    if (_locationStreamSub != null) return;
    _locationStreamSub =
        Geolocator.getPositionStream(
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
          onError: (_) {
            _stopLocationStream();
            // Kısa süre sonra yeniden dene — tek hatada mesafe sonsuza kadar donmasın.
            Future<void>.delayed(const Duration(seconds: 8), () {
              if (!mounted) return;
              unawaited(() async {
                if (await SimpleLocationService.isLocationGranted() &&
                    await Geolocator.isLocationServiceEnabled()) {
                  _startLocationStream();
                }
              }());
            });
          },
          cancelOnError: false,
        );
  }

  void _stopLocationStream() {
    _locationStreamSub?.cancel();
    _locationStreamSub = null;
  }

  Future<void> _maybeOpenHolidaysFromNotification() async {
    final route =
        await HolidayNotificationScheduler.consumePendingRouteFromNotification();
    final open =
        await HolidayNotificationScheduler.consumePendingOpenHolidaysNavigation();
    final target = route ?? (open ? RotalinkShellRoutes.holidays : null);
    if (target == null || !mounted || !context.mounted) return;
    widget.navBridge?.onExternalSurfaceChanged?.call(true);
    try {
      await Navigator.of(context).pushNamed(target);
    } finally {
      widget.navBridge?.onExternalSurfaceChanged?.call(false);
    }
  }

  Future<void> _checkForUpdate() async {
    if (!mounted || !context.mounted) return;

    final isUpdateRequired = await VersionCheckService.instance
        .isUpdateRequired();
    if (!isUpdateRequired) return;

    final currentVersion = await VersionCheckService.instance
        .getCurrentVersionInfo();
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
    DeepLinkService.instance.pending.removeListener(_onDeepLinkPending);
    _previewPositionTick.dispose();
    _stopLocationStream();
    _dismissAttachedBottomSheet();
    _mapPreviewDismissSub?.cancel();
    _viewportRefreshDebounce?.cancel();
    _searchController.dispose();
    _searchBarFocusNode.dispose();
    _popupController.dispose();
    _mapLocationState.dispose();
    super.dispose();
  }

  /// Liste (`true`) / Harita (`false`) görünümü. Arama, filtre, kategori ve
  /// marker seçimi korunur; harita yalnızca açığa çıkar/gizlenir.
  void _setSearchListVisible(bool showList) {
    if (!mounted || !_inlineTabbedSearchOpen) return;
    if (showList == isSheetVisible) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => isSheetVisible = showList);
  }

  /// Arama paneli açık ve Liste görünümü ön planda (harita gizli).
  bool get _searchListShowing => _inlineTabbedSearchOpen && isSheetVisible;

  void _syncSearchPanelOpen(bool open) {
    ref.read(searchPanelOpenProvider.notifier).state = open;
    if (!open) {
      ref.read(searchPanelFacilitiesSourceProvider.notifier).state = const [];
      ref.read(facilityIlceFilterProvider.notifier).state = null;
    }
  }

  /// İlçe filtresi değişince harita yalnız görünen tesislere odaklanır.
  void _onIlceFilterChanged(IlceSelection? prev, IlceSelection? next) {
    final base = _markerOverride;
    if (prev == next || base == null || base.isEmpty || !mounted) return;
    final shown = filterFacilities(
      base,
      ref.read(facilityTypeFilterProvider),
      next,
    );
    if (shown.isNotEmpty) _fitFacilitiesCamera(shown);
  }

  /// Aynı adlı ilçe birden çok ilde varsa ("Edremit") kullanıcıya sorar.
  Future<IlIlceMatch?> _pickAmbiguousIlce(
    BuildContext context,
    List<IlIlceMatch> options,
    List<Misafirhane> kaynak,
  ) {
    final ilceOf = FacilityAddressRepository.instance.ilceOf;
    int countOf(IlIlceMatch o) => kaynak
        .where((m) => IlIlce.sameIl(m.il, o.il) && ilceOf(m) == o.ilce)
        .length;
    return showModalBottomSheet<IlIlceMatch>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Hangi ${options.first.ilce}?',
              style: Theme.of(
                ctx,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (final o in options)
            ListTile(
              leading: const Icon(
                Icons.place_outlined,
                color: AppColors.primary,
              ),
              title: Text(IlIlce.label(o.il, o.ilce!)),
              trailing: Text(
                countOf(o) == 0 ? 'Tesis yok' : '${countOf(o)} tesis',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () => Navigator.of(ctx).pop(o),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// Sonuç panelindeki il seçici: o il için yeni arama.
  void _searchIlFromPanel(String il) {
    final data = _tabbedSheetRotaData ?? _cachedRotaData;
    if (data == null || !mounted) return;
    _searchController.text = il;
    unawaited(_performSearch(context, data));
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
      _facilityDetailVisible = false;
      _tabbedSheetRotaData = null;
      _tabbedSheetHighlight = null;
      _tabbedSheetInitialTab = 0;
      _tabbedSheetGeziYemekHighlight = null;
      isSheetVisible = true;
    });
  }

  /// Arama paneli geri yığını:
  /// detay kartı / marker önizleme → harita → liste → liste → önceki menü.
  Future<bool> _handleSearchPanelBack() async {
    if (!_inlineTabbedSearchOpen) return false;

    _lastExitBackAt = null;

    // Konaklama detay kartı — arama metni boş olsa da önce listeye dön.
    if (_searchResultsPanelKey.currentState?.closeDetailIfOpen() ?? false) {
      return true;
    }

    // Harita görünümü → Liste görünümü (filtre / kategori / sorgu korunur).
    if (!isSheetVisible) {
      _setSearchListVisible(true);
      return true;
    }

    // Liste görünümü → önceki menü: kategori ile açıldıysa ana menü,
    // arama ile açıldıysa temiz harita.
    final fromCategory = _searchController.text.trim().isEmpty;
    _resetSearchToHome();
    if (fromCategory) RotalinkShellScope.find(context)?.goHome();
    return true;
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
    _closeAttachedBottomSheetOnly();
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
    final shouldRefresh =
        e is MapEventMove ||
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
      return e.source == MapEventSource.onDrag ||
          e.source == MapEventSource.onMultiFinger;
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
      _mapMarkerDetailFacility = null;
      _markerOverride = null;
      _mainMapFocusedCity = null;
      _weatherSearchCity = null;
      _favoritesBrowseActive = false;
      _searchSheetHighlight = null;
      _clearRouteOnly();
    });
  }

  /// Arama sonuçlarındaki baskın il (önce vurgulanan tesis, yoksa en çok tekrar eden il).
  String? _dominantCityOf(List<Misafirhane> list, Misafirhane? highlight) {
    final hlCity = highlight?.il.trim();
    if (hlCity != null && hlCity.isNotEmpty) return hlCity;
    if (list.isEmpty) return null;
    final counts = <String, int>{};
    String? best;
    var bestCount = 0;
    for (final m in list) {
      final il = m.il.trim();
      if (il.isEmpty) continue;
      final n = (counts[il] ?? 0) + 1;
      counts[il] = n;
      if (n > bestCount) {
        bestCount = n;
        best = il;
      }
    }
    return best;
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
            _mapController.move(
              kTurkeyMapFallbackCenter,
              kTurkeyMapFallbackZoom,
            );
          } catch (_) {}
        }
      }
    });
  }

  List<Misafirhane> _markersSource(RotaDataState? snapshotData) {
    final effective =
        (snapshotData != null && snapshotData.errorMessage != null)
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

    final groups = <String, List<Misafirhane>>{};
    final seenByCity = <String, Set<String>>{};
    final displayName = <String, String>{};

    // Tüm iller: tesisin ili neyse o dairenin sayısına eklenir.
    for (final facility in effective.aramaIcinTumTesisler) {
      if (!facilityMatchesTypeFilter(facility.tip, typeFilter)) continue;
      final cityName = IlIlce.canonicalIl(facility.il) ?? facility.il.trim();
      if (cityName.isEmpty) continue;
      final cityKey = _normalizeCityKey(cityName);
      final citySeen = seenByCity.putIfAbsent(cityKey, () => <String>{});
      if (!citySeen.add(facility.stableFacilityId)) continue;
      groups.putIfAbsent(cityKey, () => <Misafirhane>[]).add(facility);
      displayName.putIfAbsent(cityKey, () => cityName);
    }

    final summaries = <_OverviewCitySummary>[];
    for (final entry in groups.entries) {
      final facilities = entry.value;
      if (facilities.isEmpty) continue;
      summaries.add(
        _OverviewCitySummary(
          cityName: displayName[entry.key]!,
          facilities: List<Misafirhane>.unmodifiable(facilities),
          center: _overviewCityCenter(entry.key, facilities),
        ),
      );
    }
    summaries.sort((a, b) => a.cityName.compareTo(b.cityName));

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

  void _onMisafirhanePopupEvent(
    PopupEvent event,
    List<Marker> selectedMarkers,
  ) {
    _misafirhaneFacilityPopupOpen = selectedMarkers.any(
      (m) => m is MisafirhaneMapMarker,
    );
    if (selectedMarkers.isNotEmpty && mounted && _mapPreviewFacility != null) {
      setState(() => _mapPreviewFacility = null);
    }
  }

  void _showMisafirhanePopupFor(Misafirhane m) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hl = _mapMarkerDetailFacility ?? _searchSheetHighlight;
      _popupController.showPopupsOnlyFor([
        MisafirhaneMapMarker(
          misafirhane: m,
          primaryHighlight: hl != null && m.sameFavoriteIdentity(hl),
        ),
      ]);
    });
  }

  int _ignoreMapTapUntilMs = 0;

  void _selectFacilityOnMap(Misafirhane m) {
    final alreadyOpen =
        _mapMarkerDetailFacility != null &&
        _mapMarkerDetailFacility!.sameFavoriteIdentity(m) &&
        _attachedBottomSheet != null;
    if (alreadyOpen) {
      _dismissMapFacilitySelection();
      return;
    }
    _ignoreMapTapUntilMs = DateTime.now().millisecondsSinceEpoch + 450;
    setState(() => _mapMarkerDetailFacility = m);
    _showMisafirhanePopupFor(m);
    _openFacilityMapSheet(m);
    _focusFacilityForMapSheet(m);
  }

  void _dismissMapFacilitySelection() {
    _mapMarkerDetailFacility = null;
    _popupController.hideAllPopups();
    _closeAttachedBottomSheetOnly();
    if (mounted) setState(() {});
  }

  void _openFacilityMapSheet(Misafirhane m) {
    if (_attachedBottomSheet != null) {
      _closeAttachedBottomSheetOnly();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_mapMarkerDetailFacility == null ||
            !_mapMarkerDetailFacility!.sameFavoriteIdentity(m)) {
          return;
        }
        _presentFacilityMapSheet(m);
      });
      return;
    }
    _presentFacilityMapSheet(m);
  }

  void _focusFacilityForMapSheet(Misafirhane m) {
    if (!_validFacilityCoords(m)) return;
    final dest = latLngOrFallback(m.latitude, m.longitude);
    try {
      final cam = _mapController.camera;
      if (cam.zoom < 13) {
        _mapController.move(dest, 15);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_mapMarkerDetailFacility == null ||
              !_mapMarkerDetailFacility!.sameFavoriteIdentity(m)) {
            return;
          }
          _nudgeMapForFacilitySheet(m);
        });
        return;
      }
      _nudgeMapForFacilitySheet(m);
    } catch (_) {}
  }

  void _nudgeMapForFacilitySheet(Misafirhane m) {
    if (!_validFacilityCoords(m)) return;
    try {
      final cam = _mapController.camera;
      final dest = latLngOrFallback(m.latitude, m.longitude);
      final sp = cam.latLngToScreenPoint(dest);
      final targetY = cam.nonRotatedSize.y * 0.22;
      final dy = sp.y - targetY;
      if (dy.abs() < 18) return;
      final newCenter = cam.pointToLatLng(
        math.Point<double>(
          cam.nonRotatedSize.x / 2,
          cam.nonRotatedSize.y / 2 + dy,
        ),
      );
      _mapController.move(newCenter, cam.zoom);
    } catch (_) {}
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
    if (_inlineTabbedSearchOpen) return true;
    return !_isMainMapOverviewActive ||
        _attachedBottomSheet != null ||
        _mainMapFocusedCity != null ||
        _searchController.text.trim().isNotEmpty ||
        _mapPreviewFacility != null ||
        _mapMarkerDetailFacility != null ||
        _misafirhaneFacilityPopupOpen;
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
      _mapMarkerDetailFacility = null;
      _misafirhaneFacilityPopupOpen = false;
      readyToExit = false;
      isSheetVisible = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !context.mounted) return;
      _fitFacilitiesCamera(summary.facilities);
      await Future<void>.delayed(const Duration(milliseconds: 140));
      if (!mounted || !context.mounted) return;
      await _openTabbedSearchResults(context, data, summary.facilities);
    });
  }

  void _maybeRestoreOverviewMarkers(double nextZoom) {
    if (_mainMapFocusedCity == null ||
        nextZoom >= _kOverviewCityZoomThreshold) {
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
      final focusedCityFacilities = _allFacilitiesForMap(
        _cachedRotaData,
      ).where((m) => _normalizeCityKey(m.il) == focusedKey).toList();
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

    if (_mapMarkerDetailFacility != null) {
      _dismissMapFacilitySelection();
      _lastExitBackAt = null;
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }

    // Liste görünümünde harita gizli: önizleme / popup adımı atlanır.
    if (_mapPreviewFacility != null && !_searchListShowing) {
      if (_previewClosing) return;
      unawaited(_closeMapPreviewAnimated());
      return;
    }

    if (_misafirhaneFacilityPopupOpen && !_searchListShowing) {
      _popupController.hideAllPopups();
      _lastExitBackAt = null;
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreCameraAfterPreviewClose();
      });
      return;
    }

    // Favori / kompakt liste: detay → liste → sheet kapat
    if (_attachedBottomSheet != null) {
      _lastExitBackAt = null;
      if (_compactFacilityDetailOpen && _closeCompactFacilityDetail != null) {
        _closeCompactFacilityDetail!();
        return;
      }
      _closeAttachedBottomSheetOnly();
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

  void _closeAttachedBottomSheetOnly() {
    _closeCompactFacilityDetail = null;
    _compactFacilityDetailOpen = false;
    final c = _attachedBottomSheet;
    if (c == null) return;
    _attachedBottomSheet = null;
    try {
      c.close();
    } catch (_) {}
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
    setState(() {
      _inlineTabbedSearchOpen = false;
      _facilityDetailVisible = false;
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
      _openMisafirhaneSheet(display, liveFavoriteList: true);
    });
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  /// Dashboard üstünde kalırken sonuç paneli çizilene kadar bekle.
  Future<void> _waitUntilSearchResultsVisible() async {
    if (_inlineTabbedSearchOpen) return;
    if (_markerOverride == null || _markerOverride!.isEmpty) return;
    final deadline = DateTime.now().add(const Duration(milliseconds: 1400));
    while (mounted &&
        !_inlineTabbedSearchOpen &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
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

  /// Mesafe satırı chip dokunuşu → sistem konum izin popup'ı.
  Future<void> _onSearchSheetRequestLocation() async {
    await _requestLocationWithSystemDialog(fromUserTap: true);
  }

  /// Sistem konum izin penceresini açar; verilirse GPS konumunu alır.
  Future<void> _requestLocationWithSystemDialog({
    required bool fromUserTap,
  }) async {
    if (!mounted) return;
    SimpleLocationService.clearSessionGpsSuppression();
    if (fromUserTap) {
      await SimpleLocationService.prepareForUserInitiatedPermissionDialog();
    }

    // setState / sheet animasyonu bitince iste — aksi halde Android popup çıkmayabilir.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final outcome = await SimpleLocationService.requestOsPermissionDialog();
    if (!mounted) return;

    switch (outcome) {
      case PermissionRequestOutcome.granted:
        await _applyLocationAfterPermissionGranted();
        await _refreshSearchSheetAfterLocation();
        return;
      case PermissionRequestOutcome.denied:
        await _syncLocationUiFromPermissionOnly();
        return;
      case PermissionRequestOutcome.deniedForever:
        await _syncLocationUiFromPermissionOnly();
        // Sistem popup bir daha çıkmaz; kullanıcı dokunuşunda ayarlar yolu.
        if (fromUserTap && mounted) {
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text(AppStrings.locationPermissionDialogTitle),
              content: const Text(
                AppStrings.locationPermissionDialogDeniedForeverBody,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    AppStrings.locationServicesOffDialogOpenSettings,
                  ),
                ),
              ],
            ),
          );
          if (go == true && mounted) {
            _pendingLocationCheckAfterSettings = true;
            await Geolocator.openAppSettings();
          }
        }
        return;
    }
  }

  Future<void> _applyLocationAfterPermissionGranted() async {
    SimpleLocationService.clearSessionGpsSuppression();

    // 1) Hızlı önizleme: lastKnown
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          isValidWgs84LatLng(last.latitude, last.longitude) &&
          mounted) {
        final ll = LatLng(last.latitude, last.longitude);
        _userLocationLatLng = ll;
        unawaited(UserLocationCache.save(ll));
        if (await Geolocator.isLocationServiceEnabled()) {
          _startLocationStream();
        }
        final granted = await SimpleLocationService.isLocationGranted();
        if (mounted) {
          _mapLocationState.update(ll, granted);
          setState(() {});
        }
      }
    } catch (_) {}

    // 2) Güncel GPS — GPS kapalı olsa bile dene (bazı cihazlarda sistem diyaloğu açılır).
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: _kRotalinkLocationSettingsLow,
      );
      if (!mounted) return;
      if (isValidWgs84LatLng(pos.latitude, pos.longitude)) {
        final ll = LatLng(pos.latitude, pos.longitude);
        _userLocationLatLng = ll;
        unawaited(UserLocationCache.save(ll));
        _startLocationStream();
        final granted = await SimpleLocationService.isLocationGranted();
        if (mounted) {
          _mapLocationState.update(ll, granted);
          setState(() {});
        }
      }
    } catch (_) {
      if (_userLocationLatLng == null) {
        _stopLocationStream();
        if (mounted && !await Geolocator.isLocationServiceEnabled()) {
          // GPS kapalı: kullanıcıya sor (otomatik ayar açma yok).
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text(AppStrings.locationServicesOffDialogTitle),
              content: const Text(AppStrings.locationServicesOffDialogBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    AppStrings.locationServicesOffDialogOpenSettings,
                  ),
                ),
              ],
            ),
          );
          if (go == true && mounted) {
            _pendingLocationCheckAfterSettings = true;
            await Geolocator.openLocationSettings();
          }
        } else if (mounted) {
          _toast(context, AppStrings.locationServicesOffSnack);
        }
      } else {
        if (await Geolocator.isLocationServiceEnabled()) {
          _startLocationStream();
        }
      }
    }
    await _syncLocationUiFromPermissionOnly();
  }

  Future<void> _ensureLocationPermissionAndLocationForLists({
    bool fromDistanceChip = false,
  }) async {
    // İzin + GPS + mevcut konum varsa sessizce yenile.
    if (await SimpleLocationService.isLocationGranted() &&
        await Geolocator.isLocationServiceEnabled() &&
        _userLocationLatLng != null) {
      await _applyLocationAfterPermissionGranted();
      await _refreshSearchSheetAfterLocation();
      return;
    }

    await _requestLocationWithSystemDialog(fromUserTap: fromDistanceChip);
  }

  /// İzin/konum alındıktan sonra arama panelini kapatmadan mesafeleri yenile.
  Future<void> _refreshSearchSheetAfterLocation() async {
    await _syncLocationUiFromPermissionOnly();
    if (!mounted) return;
    if (!await SimpleLocationService.isLocationGranted()) return;

    final user = _userLocationLatLng;
    final granted = true;

    if (_inlineTabbedSearchOpen) {
      final source = ref.read(searchPanelFacilitiesSourceProvider);
      if (source.isNotEmpty) {
        final sorted = sortMisafirhaneByDistance(source, user);
        ref.read(searchPanelFacilitiesSourceProvider.notifier).state =
            List<Misafirhane>.unmodifiable(sorted);
      }
      _mapLocationState.update(user, granted);
      if (mounted) setState(() {});
      return;
    }

    // Eski modal sheet yolu (inline panel yoksa).
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
      // Inline panel zaten açıksa kapatıp açma — yerinde yenile.
      await _refreshSearchSheetAfterLocation();
      return;
    }
    final ctrl = _attachedBottomSheet;
    if (ctrl == null) return;
    ctrl.close();
    await ctrl.closed;
    if (!mounted || !context.mounted) return;
    await _openTabbedSearchResults(
      context,
      data,
      facilities,
      highlightTarget: highlight,
    );
  }

  /// [forceHighlight]: arama sonucunda vurgulanacak tesis (ör. web tesis linki);
  /// [openHighlightDetail] ise detay kartı da açılır.
  Future<void> _performSearch(
    BuildContext context,
    RotaDataState data, {
    Misafirhane? forceHighlight,
    bool openHighlightDetail = false,
  }) async {
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
    if (words.isNotEmpty) {
      unawaited(RecentSearchStore.instance.add(_searchController.text));
    }
    if (words.isEmpty) {
      setState(() {
        readyToExit = false;
        isSheetVisible = true;
        _mainMapFocusedCity = null;
        _weatherSearchCity = null;
        _markerOverride = null;
        _searchSheetHighlight = null;
      });
      return;
    }

    await _prepareLocationForSearch();
    if (!mounted) return;

    final ilceOf = FacilityAddressRepository.instance.ilceOf;
    var ilceMatches = MainMapSearch.matchLocation(
      query: _searchController.text,
      kaynak: kaynak,
    ).where((l) => l.ilce != null).toList();
    if (ilceMatches.length > 1) {
      if (!context.mounted) return;
      final picked = await _pickAmbiguousIlce(context, ilceMatches, kaynak);
      if (picked == null || !mounted || !context.mounted) return;
      ilceMatches = [picked];
    }
    final presetIlce = ilceMatches.length == 1
        ? IlceSelection(
            il: ilceMatches.single.il,
            ilce: ilceMatches.single.ilce!,
          )
        : null;

    final filtered = presetIlce != null
        ? kaynak.where((m) => IlIlce.sameIl(m.il, presetIlce.il)).toList()
        : MainMapSearch.perform(
            query: _searchController.text,
            kaynak: kaynak,
            mapMisafirhaneler: data.misafirhaneler,
            ilceOf: ilceOf,
          );

    if (filtered.isEmpty) {
      if (!context.mounted) return;
      _toast(context, AppStrings.searchNoResults);
      setState(() {
        readyToExit = false;
        isSheetVisible = true;
        _weatherSearchCity = null;
        _markerOverride = const [];
        _mapPreviewFacility = null;
        _searchSheetHighlight = null;
      });
      return;
    }

    final displayList = filtered;

    final narrowForHighlight = presetIlce != null
        ? const <Misafirhane>[]
        : MainMapSearch.narrowFuzzyMatches(
            query: _searchController.text,
            kaynak: kaynak,
            ilceOf: ilceOf,
          );
    final highlightMatch = presetIlce != null
        ? null
        : MainMapSearch.findPrimaryMatchForScroll(
            query: _searchController.text,
            displayedFacilities: narrowForHighlight.isNotEmpty
                ? narrowForHighlight
                : displayList,
          );
    final wanted = forceHighlight ?? highlightMatch;
    Misafirhane? highlightTarget = wanted;
    if (wanted != null) {
      for (final m in displayList) {
        if (m.sameFavoriteIdentity(wanted)) {
          highlightTarget = m;
          break;
        }
      }
    }

    setState(() {
      readyToExit = false;
      isSheetVisible = true;
      _mainMapFocusedCity = null;
      _weatherSearchCity = _dominantCityOf(displayList, highlightTarget);
      _markerOverride = displayList;
      _mapPreviewFacility = null;
      _searchSheetHighlight = highlightTarget;
    });
    ref.read(facilityIlceFilterProvider.notifier).state = presetIlce;
    final ilceFocus = filterFacilitiesByIlce(displayList, presetIlce);
    final cameraList = ilceFocus.isNotEmpty ? ilceFocus : displayList;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !context.mounted) return;
      final hl = highlightTarget;
      if (hl != null && _validFacilityCoords(hl)) {
        _fitFacilitiesCamera(cameraList);
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (!mounted || !context.mounted) return;
        await _animateTowardsMisafirhane(hl);
      } else {
        _fitFacilitiesCamera(cameraList);
      }
      await Future<void>.delayed(const Duration(milliseconds: 140));
      if (!mounted || !context.mounted) return;
      await _openTabbedSearchResults(
        context,
        data,
        displayList,
        highlightTarget: hl,
      );
      if (openHighlightDetail && hl != null) {
        await _openFacilityDetailInPanel(hl);
      }
    });
  }

  /// Arama paneli kurulunca tesis detayını açar.
  Future<void> _openFacilityDetailInPanel(Misafirhane m) async {
    for (var i = 0; i < 60; i++) {
      final panel = _searchResultsPanelKey.currentState;
      if (panel != null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        _searchResultsPanelKey.currentState?.openFacilityDetail(m);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
  }

  // ─── Web linkleri (rotalink.tr / rotalink://open) ─────────────────────────

  bool _deepLinkBusy = false;

  void _onDeepLinkPending() {
    if (_deepLinkBusy || !mounted) return;
    final target = DeepLinkService.instance.pending.value;
    if (target == null) return;
    final needsData =
        target.kind == DeepLinkKind.city ||
        target.kind == DeepLinkKind.facility;
    final data = _cachedRotaData;
    if (needsData &&
        (data == null ||
            (data.aramaIcinTumTesisler.isEmpty &&
                data.misafirhaneler.isEmpty))) {
      return; // Veri gelince StreamBuilder tekrar dener.
    }
    DeepLinkService.instance.take();
    _deepLinkBusy = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _openDeepLinkTarget(
          target,
          data,
        ).whenComplete(() => _deepLinkBusy = false),
      );
    });
  }

  Future<void> _openDeepLinkTarget(
    DeepLinkTarget target,
    RotaDataState? data,
  ) async {
    if (!mounted || !context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    switch (target.kind) {
      case DeepLinkKind.home:
        return;
      case DeepLinkKind.holidays:
        await Navigator.of(context).pushNamed(RotalinkShellRoutes.holidays);
        return;
      case DeepLinkKind.city:
      case DeepLinkKind.facility:
        break;
    }
    if (data == null) return;
    final kaynak = MainMapSearch.tesisKaynagiArama(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    String? il;
    for (final m in kaynak) {
      if (rotalinkSlug(m.il) == target.citySlug) {
        il = m.il;
        break;
      }
    }
    if (il == null) return;
    Misafirhane? facility;
    final facilitySlug = target.facilitySlug;
    if (facilitySlug != null) {
      for (final m in kaynak) {
        if (rotalinkSlug(m.isim) == facilitySlug && IlIlce.sameIl(m.il, il)) {
          facility = m;
          break;
        }
      }
    }
    if (!mounted || !context.mounted) return;
    _searchController.text = il;
    await _performSearch(
      context,
      data,
      forceHighlight: facility,
      openHighlightDetail: facility != null,
    );
    if (!mounted || !context.mounted) return;
    await _runDeepLinkAction(target, facility);
  }

  /// Web'deki İletişim / Konum butonunun uygulama karşılığı.
  Future<void> _runDeepLinkAction(
    DeepLinkTarget target,
    Misafirhane? facility,
  ) async {
    if (target.action == DeepLinkAction.call) {
      if (facility != null && context.mounted) {
        await FacilityPhoneDialer.open(context, facility);
      }
      return;
    }
    if (target.action != DeepLinkAction.map || !context.mounted) return;
    final query = facility != null
        ? '${facility.il} ${facility.isim}'.trim()
        : (target.mapQuery ?? '');
    if (query.isEmpty && facility == null) return;
    final lat = facility?.latitude;
    final lng = facility?.longitude;
    await openInNativeMaps(
      context,
      query: query.isEmpty ? '${lat ?? ''},${lng ?? ''}' : query,
      latitude: lat,
      longitude: lng,
    );
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
    bool requestLocation = true,
  }) async {
    try {
      if (!mounted || !context.mounted) return;
      final granted = await SimpleLocationService.isLocationGranted();
      LatLng? userForSort;
      if (granted &&
          _userLocationLatLng != null &&
          isValidWgs84LatLng(
            _userLocationLatLng!.latitude,
            _userLocationLatLng!.longitude,
          )) {
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
          _facilityDetailVisible = false;
          _tabbedSheetRotaData = null;
          _tabbedSheetHighlight = null;
        });
        await Future<void>.delayed(Duration.zero);
        if (!mounted || !context.mounted) return;
      }

      if (!mounted || !context.mounted) return;
      ref.read(searchPanelFacilitiesSourceProvider.notifier).state =
          List<Misafirhane>.unmodifiable(sorted);
      setState(() {
        readyToExit = reopenNextBackExitsSearch;
        isSheetVisible = true;
        _inlineTabbedSearchOpen = true;
        _tabbedSheetRotaData = data;
        _tabbedSheetHighlight = resolvedHighlight;
        _tabbedSheetInitialTab = initialTabIndex;
        _tabbedSheetGeziYemekHighlight = geziYemekHighlight;
      });
      _syncSearchPanelOpen(true);
      // Nearby/manual selection has already resolved the user's permission choice.
      if (requestLocation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(() async {
            await SimpleLocationService.prepareForUserInitiatedPermissionDialog();
            await _ensureLocationPermissionAndLocationForLists();
          }());
        });
      }
    } catch (e, st) {
      debugPrint('Arama sonuç sheet: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: RotalinkSystemUi.forBrightness(Theme.of(context).brightness),
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        drawer: RotalinkAppDrawer(
          onOpenRoute: (route) => Navigator.of(context).pushNamed(route),
          onOpenWeather: () => unawaited(showWeatherBottomSheet(context)),
        ),
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
                    if (DeepLinkService.instance.pending.value != null) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _onDeepLinkPending(),
                      );
                    }
                  }
                  final rotaForUi = (data != null && data.errorMessage != null)
                      ? _cachedRotaData
                      : (data ?? _cachedRotaData);
                  final loading =
                      !snapshot.hasData &&
                      snapshot.connectionState == ConnectionState.waiting;
                  final inRoute =
                      _activeRouteStops != null &&
                      _activeRouteStops!.isNotEmpty;
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
                  final showFacilityMarkers =
                      !inRoute && baseDisplay.isNotEmpty;

                  /// Arama sekmeli sheet açıkken tam görünürken gizlenir; aşağı indirilince
                  /// yukarı ok FAB ile tekrar açılabilir.
                  final showExpandSearchPanelFab =
                      _inlineTabbedSearchOpen && !isSheetVisible;
                  final searchSheetFab =
                      _markerOverride != null &&
                      !inRoute &&
                      !_favoritesBrowseActive &&
                      ((!_inlineTabbedSearchOpen &&
                              _attachedBottomSheet == null) ||
                          showExpandSearchPanelFab);
                  final showListFab =
                      inRoute || _favoritesBrowseActive || searchSheetFab;

                  if (loading &&
                      _cachedRotaData == null &&
                      rawDisplay.isEmpty &&
                      !inRoute) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
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
                  final searchChromeActive = ref.watch(
                    isMapSearchChromeActiveProvider,
                  );
                  final hideMapOverlayButtons =
                      searchChromeActive && !showExpandSearchPanelFab;
                  final onboarding = RotalinkShellScope.maybeOf(
                    context,
                  )?.onboarding;

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
                                flags:
                                    InteractiveFlag.all &
                                    ~InteractiveFlag.rotate,
                              ),
                              onPositionChanged: (pos, hasGesture) {
                                final c = pos.center;
                                if (isValidWgs84LatLng(
                                  c.latitude,
                                  c.longitude,
                                )) {
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
                                if (DateTime.now().millisecondsSinceEpoch <
                                    _ignoreMapTapUntilMs) {
                                  return;
                                }
                                _popupController.hideAllPopups();
                                if (_mapPreviewFacility != null) {
                                  unawaited(_closeMapPreviewAnimated());
                                }
                                if (_mapMarkerDetailFacility != null) {
                                  _dismissMapFacilitySelection();
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
                                    markers: [
                                      _userLocationMarker(_userLocationLatLng!),
                                    ],
                                  ),
                              ] else ...[
                                MapOverviewCityMarkersLayer(
                                  visible: showOverviewCityMarkers,
                                  buildMarkers: (filter) =>
                                      _overviewCityMarkersFor(
                                        rotaForUi,
                                        filter,
                                      ),
                                ),
                                MapFacilityPopupMarkersLayer(
                                  baseFacilities: baseDisplay,
                                  highlight:
                                      _mapMarkerDetailFacility ??
                                      _searchSheetHighlight,
                                  visible: showFacilityMarkers,
                                  popupController: _popupController,
                                  onMarkerTap:
                                      (popupSpec, popupState, popupController) {
                                        if (popupSpec.marker
                                            is MisafirhaneMapMarker) {
                                          _selectFacilityOnMap(
                                            (popupSpec.marker
                                                    as MisafirhaneMapMarker)
                                                .misafirhane,
                                          );
                                          return;
                                        }
                                        if (popupState.selectedPopupSpecs
                                            .contains(popupSpec)) {
                                          popupController.hideAllPopups();
                                        } else {
                                          popupController
                                              .showPopupsOnlyForSpecs([
                                                popupSpec,
                                              ]);
                                        }
                                      },
                                ),
                                if (_userLocationLatLng != null &&
                                    isValidWgs84LatLng(
                                      _userLocationLatLng!.latitude,
                                      _userLocationLatLng!.longitude,
                                    ))
                                  MarkerLayer(
                                    markers: [
                                      _userLocationMarker(_userLocationLatLng!),
                                    ],
                                  ),
                                PopupLayer(
                                  popupDisplayOptions: PopupDisplayOptions(
                                    snap: PopupSnap.markerTop,
                                    builder: (ctx, marker) {
                                      if (marker is MisafirhaneMapMarker) {
                                        return ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 240,
                                          ),
                                          child: MapFacilityPreviewCard(
                                            misafirhane: marker.misafirhane,
                                          ),
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
                          _tabbedSheetRotaData != null)
                        Positioned.fill(
                          child: MisafirhaneSearchResultsPanel(
                            key: _searchResultsPanelKey,
                            listVisible: isSheetVisible,
                            topInset: _facilityDetailVisible
                                ? 0
                                : searchChromeTop +
                                      (_inlineTabbedSearchOpen
                                          ? MainMapSearchChrome
                                                .resultsBlockHeight
                                          : MainMapSearchChrome.blockHeight) +
                                      4,
                            onDetailChanged: (visible) {
                              if (!mounted) return;
                              setState(() => _facilityDetailVisible = visible);
                              widget.navBridge?.onDetailVisibilityChanged
                                  ?.call();
                            },
                            onViewModeChanged: _setSearchListVisible,
                            rotaData: _tabbedSheetRotaData!,
                            mapLocationState: _mapLocationState,
                            highlightTarget: _tabbedSheetHighlight,
                            initialTabIndex: _tabbedSheetInitialTab,
                            geziYemekHighlight: _tabbedSheetGeziYemekHighlight,
                            favoritesRepo: _favoritesRepo,
                            onFavoritesChanged: _reloadFavoritesCache,
                            onTesisSelect: (m) async {
                              _selectFacilityOnMap(m);
                            },
                            onRequestLocationPermission:
                                _onSearchSheetRequestLocation,
                            onClosePanel: _closeInlineTabbedSearchPanel,
                            onSelectIl: _searchIlFromPanel,
                          ),
                        ),
                      ValueListenableBuilder<int>(
                        valueListenable: _previewPositionTick,
                        builder: (__, a, b) {
                          // Liste görünümünde harita gizli: önizleme durumu korunur, çizilmez.
                          if (_mapPreviewFacility == null ||
                              _searchListShowing) {
                            return const SizedBox.shrink();
                          }
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final m = _mapPreviewFacility!;
                              const cardWMax = 200.0;
                              // ~2 satır + padding; marker ile boşluk
                              const estCardH = 52.0;
                              const markerHalf = 20.0;
                              const gapAboveMarker = 8.0;
                              final minTopBelowSearch =
                                  toolbarBottom +
                                  (_inlineTabbedSearchOpen
                                      ? MainMapSearchChrome.resultsBlockHeight
                                      : MainMapSearchChrome.blockHeight) +
                                  8 +
                                  (_inlineTabbedSearchOpen ? 64 : 0);
                              final cardW = math.min(
                                cardWMax,
                                constraints.maxWidth - 16,
                              );

                              double left;
                              double top;
                              if (_validFacilityCoords(m)) {
                                final pt = _mapController.camera
                                    .latLngToScreenPoint(
                                      latLngOrFallback(m.latitude, m.longitude),
                                    );
                                left = (pt.x - cardW / 2).clamp(
                                  8.0,
                                  constraints.maxWidth - cardW - 8,
                                );
                                top =
                                    pt.y -
                                    markerHalf -
                                    gapAboveMarker -
                                    estCardH;
                                top = top.clamp(
                                  minTopBelowSearch,
                                  math.max(
                                    minTopBelowSearch,
                                    constraints.maxHeight -
                                        estCardH -
                                        MediaQuery.paddingOf(context).bottom -
                                        16,
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
                                    offset: _previewClosing
                                        ? const Offset(0, 0.06)
                                        : Offset.zero,
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
                        // Ortak Bildir butonunun sabit alanını boş bırak.
                        bottom: widget.navBridge != null ? 64 : 8,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          opacity:
                              (hideMapOverlayButtons &&
                                  !showExpandSearchPanelFab)
                              ? 0
                              : 1,
                          child: IgnorePointer(
                            ignoring:
                                hideMapOverlayButtons &&
                                !showExpandSearchPanelFab,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (showExpandSearchPanelFab)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 10,
                                      right: 2,
                                    ),
                                    child: FloatingActionButton.extended(
                                      heroTag: 'fab_expand_search',
                                      backgroundColor: AppColors.primary,
                                      elevation: 8,
                                      onPressed: () =>
                                          _setSearchListVisible(true),
                                      tooltip: 'Sonuç listesine dön',
                                      icon: const Icon(
                                        Icons.view_list_rounded,
                                        color: AppColors.white,
                                      ),
                                      label: const Text(
                                        'Listeye dön',
                                        style: TextStyle(
                                          color: AppColors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (showListFab && !showExpandSearchPanelFab)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 10,
                                      right: 2,
                                    ),
                                    child: FloatingActionButton(
                                      heroTag: 'fab_list',
                                      backgroundColor: AppColors.primary,
                                      elevation: 12,
                                      onPressed: () async {
                                        final mapFacilities = ref.read(
                                          filteredFacilitiesProvider(
                                            baseDisplay,
                                          ),
                                        );
                                        if (inRoute) {
                                          await _openRouteSummarySheet(
                                            context,
                                            _activeRouteStops!,
                                            totalDistanceM:
                                                _routeSummaryDistanceM,
                                            totalDurationS:
                                                _routeSummaryDurationS,
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
                                            highlightTarget:
                                                _searchSheetHighlight,
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
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (!_detailPresentationVisible)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: RotalinkAppHeader(
                            overlayOnMap: true,
                            onMenu: () =>
                                _scaffoldKey.currentState?.openDrawer(),
                            onTitleTap: _goToInitialMapHome,
                            menuAnchorKey: onboarding?.targetKey(
                              OnboardingTarget.menu,
                            ),
                            trailing: KeyedSubtree(
                              key: onboarding?.targetKey(
                                OnboardingTarget.weather,
                              ),
                              child: MapWeatherChip(
                                compact: true,
                                liveGps: _userLocationLatLng,
                                locationGranted:
                                    _mapLocationState.locationPermissionGranted,
                                searchedCity: _weatherSearchCity,
                                focusedCity: _mainMapFocusedCity,
                                mapCenter: _center,
                                rotaData: rotaForUi,
                              ),
                            ),
                          ),
                        ),
                      if (!_detailPresentationVisible)
                        MainMapSearchChrome(
                          compactResults: _inlineTabbedSearchOpen,
                          anchorKey: onboarding?.targetKey(
                            OnboardingTarget.searchChrome,
                          ),
                          top: searchChromeTop,
                          searchBarSession: _searchBarSession,
                          controller: _searchController,
                          ilOptionsSorted: _getIlOptions(rotaForUi),
                          onSubmitted: rotaForUi != null
                              ? () => unawaited(
                                  _performSearch(context, rotaForUi),
                                )
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
                          onClearPressed: () {
                            if (!mounted) return;
                            final shell = RotalinkShellScope.find(context);
                            if (shell != null) {
                              shell.goHome();
                            } else {
                              _resetSearchToHome();
                            }
                          },
                          focusNode: _searchBarFocusNode,
                          onFocusChanged: _onSearchBarFocusChanged,
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _dialFacilityPhone(BuildContext context, Misafirhane facility) async {
    await FacilityPhoneDialer.open(context, facility);
  }

  Future<void> _shareFacility(Misafirhane m) async {
    final phone = m.telefonNumaralari.join(' / ');
    await Share.share(
      StoreLinks.shareMessage(m.isim, [
        if (phone.isNotEmpty) 'Telefon: $phone',
      ]),
    );
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
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _presentFacilityMapSheet(Misafirhane m) {
    widget.navBridge?.onDetailVisibilityChanged?.call();
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState == null) return;
    final ctrl = scaffoldState.showBottomSheet(
      (sheetCtx) {
        final sheetH = misafirhaneCompactDetailSheetHeight(sheetCtx);
        return SizedBox(
          height: sheetH,
          child: Material(
            color: AppColors.surfaceOf(sheetCtx),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            clipBehavior: Clip.antiAlias,
            child: StatefulBuilder(
              builder: (ctx, setModal) {
                return ListenableBuilder(
                  listenable: _mapLocationState,
                  builder: (context, _) {
                    return FacilityDetailCard(
                      misafirhane: m,
                      fromMap: true,
                      mapLocationState: _mapLocationState,
                      isFavorite: _favoritesCache.any(
                        (f) => f.sameFavoriteIdentity(m),
                      ),
                      onBack: () {
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      },
                      onCall: () =>
                          unawaited(_dialFacilityPhone(context, m)),
                      onShare: () => unawaited(_shareFacility(m)),
                      onFavorite: () async {
                        await _favoritesRepo.toggle(m);
                        await _reloadFavoritesCache();
                        if (ctx.mounted) setModal(() {});
                      },
                      onInspect: () =>
                          unawaited(openMapSearch(context, m.il, m.isim)),
                      onReview: () => unawaited(
                        pushOnShellNavigator<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => YorumScreen(
                              facilityId: ReviewRepository.sanitizeFacilityId(
                                m.stableFacilityId,
                              ),
                              facilityName: m.isim,
                            ),
                          ),
                        ),
                      ),
                      onShowOnMap: () {
                        unawaited(openMapSearch(context, m.il, m.isim));
                      },
                      onRequestLocation: () async {
                        await _ensureLocationPermissionAndLocationForLists(
                          fromDistanceChip: true,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        );
      },
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
      if (_mapMarkerDetailFacility != null &&
          _mapMarkerDetailFacility!.sameFavoriteIdentity(m)) {
        _mapMarkerDetailFacility = null;
        _popupController.hideAllPopups();
        setState(() {});
        widget.navBridge?.onDetailVisibilityChanged?.call();
      }
    });
  }

  void _openMisafirhaneSheet(
    List<Misafirhane> items, {
    bool liveFavoriteList = false,
  }) {
    _popupController.hideAllPopups();
    _dismissAttachedBottomSheet();
    final scaffoldState = _scaffoldKey.currentState;
    if (scaffoldState == null) return;
    Misafirhane? detailFacility;
    final listScrollController = ScrollController();
    double? savedListScrollOffset;
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
            final wasFav = _favoritesCache.any(
              (f) => f.sameFavoriteIdentity(m),
            );
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
                  content: Text(
                    wasFav ? 'Favorilerden çıkarıldı' : 'Favorilere eklendi',
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            }
            setModal(() {});
            if (liveFavoriteList) {
              _fitFacilitiesCamera(rows());
            }
          }

          Future<void> requestLocationFromCompactSheet() async {
            await _ensureLocationPermissionAndLocationForLists(
              fromDistanceChip: true,
            );
            if (!mounted || !await SimpleLocationService.isLocationGranted())
              return;
            if (!sheetCtx.mounted) return;
            Navigator.pop(sheetCtx);
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _openMisafirhaneSheet(items, liveFavoriteList: liveFavoriteList);
            });
          }

          final list = rows();
          final detail = detailFacility;
          final sheetH = detail != null
              ? misafirhaneCompactDetailSheetHeight(ctx)
              : misafirhaneCompactSheetHeight(ctx);

          void restoreCompactListScroll(Misafirhane? returnTo) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!listScrollController.hasClients) {
                await Future<void>.delayed(const Duration(milliseconds: 48));
              }
              if (!listScrollController.hasClients) return;
              final saved = savedListScrollOffset;
              if (saved != null) {
                listScrollController.jumpTo(
                  saved.clamp(
                    0.0,
                    listScrollController.position.maxScrollExtent,
                  ),
                );
                return;
              }
              if (returnTo == null) return;
              final idx = list.indexWhere(
                (f) => f.sameFavoriteIdentity(returnTo),
              );
              if (idx < 0) return;
              const kApproxItemH = 96.0;
              final target = (idx * kApproxItemH).clamp(
                0.0,
                listScrollController.position.maxScrollExtent,
              );
              await listScrollController.animateTo(
                target,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
              );
            });
          }

          void setCompactDetail(Misafirhane? m) {
            final previous = detailFacility;
            if (m != null && listScrollController.hasClients) {
              savedListScrollOffset = listScrollController.offset;
            }
            setModal(() {
              detailFacility = m;
              _compactFacilityDetailOpen = m != null;
              if (m == null) {
                _closeCompactFacilityDetail = null;
              } else {
                _closeCompactFacilityDetail = () => setCompactDetail(null);
              }
            });
            if (mounted) setState(() {});
            widget.navBridge?.onDetailVisibilityChanged?.call();
            if (m == null && previous != null) {
              restoreCompactListScroll(previous);
            }
          }

          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            height: sheetH,
            child: Material(
              color: AppColors.surfaceOf(context),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              clipBehavior: Clip.antiAlias,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: detail != null
                    ? KeyedSubtree(
                        key: ValueKey<String>(
                          'compact-detail-${detail.stableFacilityId}',
                        ),
                        child: ListenableBuilder(
                          listenable: _mapLocationState,
                          builder: (context, _) {
                            return FacilityDetailCard(
                              misafirhane: detail,
                              mapLocationState: _mapLocationState,
                              isFavorite: _favoritesCache.any(
                                (f) => f.sameFavoriteIdentity(detail),
                              ),
                              onBack: () => setCompactDetail(null),
                              onCall: () => unawaited(
                                _dialFacilityPhone(context, detail),
                              ),
                              onShare: () => unawaited(_shareFacility(detail)),
                              onFavorite: () =>
                                  unawaited(onHeartToggled(detail)),
                              onInspect: () => unawaited(
                                openMapSearch(context, detail.il, detail.isim),
                              ),
                              onReview: () => unawaited(
                                pushOnShellNavigator<void>(
                                  MaterialPageRoute<void>(
                                    builder: (_) => YorumScreen(
                                      facilityId:
                                          ReviewRepository.sanitizeFacilityId(
                                            detail.stableFacilityId,
                                          ),
                                      facilityName: detail.isim,
                                    ),
                                  ),
                                ),
                              ),
                              onShowOnMap: () {
                                unawaited(
                                  openMapSearch(
                                    context,
                                    detail.il,
                                    detail.isim,
                                  ),
                                );
                              },
                              onRequestLocation:
                                  requestLocationFromCompactSheet,
                            );
                          },
                        ),
                      )
                    : KeyedSubtree(
                        key: const ValueKey<String>('compact-list'),
                        child: ListView.separated(
                          controller: listScrollController,
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.paddingOf(ctx).bottom,
                          ),
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final m = list[i];
                            final isFav = _favoritesCache.any(
                              (f) => f.sameFavoriteIdentity(m),
                            );
                            return ListenableBuilder(
                              listenable: _mapLocationState,
                              builder: (context, _) {
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => setCompactDetail(m),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        10,
                                        4,
                                        10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      m.isim,
                                                      style: const TextStyle(
                                                        color: AppColors
                                                            .textPrimary,
                                                        fontSize: 14.5,
                                                        height: 1.2,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                      maxLines: 3,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 5),
                                                    Row(
                                                      children: [
                                                        if (m.tip
                                                            .trim()
                                                            .isNotEmpty) ...[
                                                          Flexible(
                                                            child: Text(
                                                              m.tip.trim(),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                color: AppColors
                                                                    .textPrimary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.52,
                                                                    ),
                                                                fontSize: 12,
                                                                height: 1.2,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                        ],
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.fromLTRB(
                                                                10,
                                                                6,
                                                                8,
                                                                6,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: AppColors
                                                                .primary
                                                                .withValues(
                                                                  alpha: 0.09,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  999,
                                                                ),
                                                            border: Border.all(
                                                              color: AppColors
                                                                  .primary
                                                                  .withValues(
                                                                    alpha: 0.14,
                                                                  ),
                                                            ),
                                                          ),
                                                          child: const Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Text(
                                                                'Detay',
                                                                style: TextStyle(
                                                                  color: AppColors
                                                                      .primary,
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  height: 1,
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                width: 2,
                                                              ),
                                                              Icon(
                                                                Icons
                                                                    .arrow_forward_rounded,
                                                                size: 14,
                                                                color: AppColors
                                                                    .primary,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              _compactSheetActionColumn(
                                                icon: Icons.call,
                                                color: const Color(0xFF2E7D32),
                                                label: 'Ara',
                                                onTap: () => unawaited(
                                                  _dialFacilityPhone(
                                                    context,
                                                    m,
                                                  ),
                                                ),
                                              ),
                                              _compactSheetActionColumn(
                                                icon: Icons.share,
                                                color: const Color(0xFF039BE5),
                                                label: 'Paylaş',
                                                onTap: () => unawaited(
                                                  _shareFacility(m),
                                                ),
                                              ),
                                              _compactSheetActionColumn(
                                                icon: isFav
                                                    ? Icons.favorite
                                                    : Icons.favorite_border,
                                                color: const Color(0xFFC2185B),
                                                label: 'Favori',
                                                onTap: () => unawaited(
                                                  onHeartToggled(m),
                                                ),
                                              ),
                                              _compactSheetActionColumn(
                                                icon: Icons.map_outlined,
                                                color: AppColors.primary,
                                                label: 'Harita',
                                                onTap: () => unawaited(
                                                  openMapSearch(
                                                    context,
                                                    m.il,
                                                    m.isim,
                                                  ),
                                                ),
                                              ),
                                              _compactSheetActionColumn(
                                                icon: Icons.chat_bubble_outline,
                                                color: const Color(0xFFE65100),
                                                label: 'Yorum',
                                                onTap: () => unawaited(
                                                  pushOnShellNavigator<void>(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) => YorumScreen(
                                                        facilityId:
                                                            ReviewRepository.sanitizeFacilityId(
                                                              m.stableFacilityId,
                                                            ),
                                                        facilityName: m.isim,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          DistancePermissionChip(
                                            userLocation:
                                                _mapLocationState.userLocation,
                                            locationPermissionGranted:
                                                _mapLocationState
                                                    .locationPermissionGranted,
                                            facilityPoint: LatLng(
                                              m.latitude,
                                              m.longitude,
                                            ),
                                            onRequestLocation:
                                                requestLocationFromCompactSheet,
                                            spacingAbove: 4,
                                            fullWidthSingleLine: true,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
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
      listScrollController.dispose();
      if (!mounted) return;
      if (_attachedBottomSheet != ctrl) return;
      _attachedBottomSheet = null;
      _closeCompactFacilityDetail = null;
      _compactFacilityDetailOpen = false;
      setState(() {});
      widget.navBridge?.onDetailVisibilityChanged?.call();
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
          key: ValueKey<String>(
            'route-lbl-$i-${mid.latitude}-${mid.longitude}',
          ),
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
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textStrongOf(context),
                  shadows: [Shadow(color: Colors.white, blurRadius: 4)],
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
    final outcome = await pushOrReplaceOnShellNavigator<RoutePlanOutcome>(
      MaterialPageRoute<RoutePlanOutcome>(
        settings: const RouteSettings(name: RotalinkShellRoutes.routePlan),
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

    final segments =
        precomputedSegments != null && precomputedSegments.isNotEmpty
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

    final straight = onlyValidLatLngs(
      OsrmRouteService.straightFallback(waypoints),
    );
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
    final labels = segments.isNotEmpty
        ? _routeSegmentLabelMarkers(segments)
        : const <Marker>[];

    final hasOsrmTotals =
        segments.isNotEmpty && totalDistanceM > 0 && totalDurationS > 0;
    setState(() {
      _routePolylines = effectivePolylines;
      _routeLabelMarkers = labels;
      _routeSummaryDistanceM = hasOsrmTotals ? totalDistanceM : null;
      _routeSummaryDurationS = hasOsrmTotals ? totalDurationS : null;
    });
    _fitRouteCamera(flat);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _openRouteSummarySheet(
          context,
          stops,
          totalDistanceM: hasOsrmTotals ? totalDistanceM : null,
          totalDurationS: hasOsrmTotals ? totalDurationS : null,
          navWaypoints: waypointsForRouteStops(data, stops),
        ),
      );
    });
  }

  Future<void> _promptSaveRouteFromMap(
    BuildContext context,
    List<RouteStop> stops,
  ) async {
    final nameCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(AppStrings.routePlanSaveTitle),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              hintText: AppStrings.routePlanSaveNameHint,
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaydet'),
            ),
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
                color: AppColors.surfaceOf(context),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  children: [
                    ListTile(
                      title: Text(
                        AppStrings.routePlanSummaryTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
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
                                color: AppColors.primary.withValues(
                                  alpha: 0.35,
                                ),
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
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.route_rounded,
                                        color: AppColors.white,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            AppStrings.routePlanTotalDistance,
                                            style: TextStyle(
                                              color: AppColors.white.withValues(
                                                alpha: 0.85,
                                              ),
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
                                    color: AppColors.white.withValues(
                                      alpha: 0.85,
                                    ),
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
                                    color: AppColors.white.withValues(
                                      alpha: 0.75,
                                    ),
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
                              child: Text(
                                AppStrings.routePlanNoSuggestions,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textMutedOf(context),
                                ),
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
                                      border: Border.all(
                                        color: const Color(
                                          0xFF1565C0,
                                        ).withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      leading: const CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Color(0xFFE3F2FD),
                                        child: Icon(
                                          Icons.hotel_rounded,
                                          color: Color(0xFF1565C0),
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        it.isim,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      subtitle: Text(
                                        AppStrings.routePlanKonak,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.primary.withValues(
                                            alpha: 0.8,
                                          ),
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
                            final label = yemek
                                ? AppStrings.routePlanYemek
                                : AppStrings.routePlanGezi;
                            final accent = yemek
                                ? const Color(0xFFE65100)
                                : const Color(0xFF2E7D32);
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
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.22),
                                      ),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 18,
                                        backgroundColor: accent.withValues(
                                          alpha: 0.12,
                                        ),
                                        child: Icon(
                                          yemek
                                              ? Icons.restaurant_rounded
                                              : Icons.park_rounded,
                                          color: accent,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        it.isim,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
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
                        title: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        children: children,
                      );
                    }),
                    if (navWaypoints != null && navWaypoints.length >= 2) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.navigation_rounded,
                          color: AppColors.primary,
                        ),
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
