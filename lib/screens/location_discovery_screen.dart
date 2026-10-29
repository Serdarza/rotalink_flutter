import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../billing/free_nearby_quota.dart';
import '../billing/premium_account_bridge.dart';
import '../billing/premium_auth_service.dart';
import '../billing/premium_presentation.dart';
import '../billing/pro_service.dart';
import '../constants/store_links.dart';
import '../data/facility_address_repository.dart';
import '../data/favorites_repository.dart';
import '../data/firebase_rota_repository.dart';
import '../services/simple_location_service.dart';
import '../kami/engine/city_resolver.dart';
import '../kami/recommendation/province_centers.dart';
import '../models/misafirhane.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../navigator_keys.dart';
import '../services/facility_route.dart';
import '../services/facility_route_access.dart';
import '../services/location_discovery_query.dart';
import '../services/map_search_history.dart';
import '../services/nearby_guesthouses.dart';
import '../services/nearby_search_access.dart';
import '../services/osrm_route_service.dart';
import '../services/nominatim_geocode_cache.dart';
import '../services/place_resolver.dart';
import '../services/place_suggestions.dart';
import '../theme/app_colors.dart';
import '../utils/facility_phone_dialer.dart';
import '../utils/il_ilce.dart';
import '../utils/maps_launch.dart';
import '../widgets/custom_search_bar.dart';
import '../widgets/facility_route_panel.dart';
import '../widgets/konum_facility_page.dart';
import '../widgets/map_pin_icon.dart';
import '../widgets/map_search_history_sheet.dart';
import '../widgets/province_count_icon.dart';

/// Türkiye haritasından nokta seçilip çevresindeki kamu misafirhaneleri listelenir.
///
/// Yer adı yazmak veya haritayı kaydırmak henüz hak düşürmez. Hak, sonuç bulunan
/// yeni bir bölge gösterildiğinde sunucuda düşer. Aynı bölgede mesafe ve tür
/// değiştirmek yeni hak açmaz. Sonuçsuz arama da hak düşürmez.
class LocationDiscoveryScreen extends StatefulWidget {
  const LocationDiscoveryScreen({super.key, required this.repository});

  final FirebaseRotaRepository repository;

  static bool Function()? tryConsumeBack;

  @override
  State<LocationDiscoveryScreen> createState() =>
      _LocationDiscoveryScreenState();
}

class _LocationDiscoveryScreenState extends State<LocationDiscoveryScreen> {
  static const _turkey = LatLng(39.0, 35.0);
  static const _driveLine = Color(0xFF0B57D0);
  static const _walkLine = Color(0xFFD32F2F);
  static const _markerCap = 120;

  final _map = Completer<GoogleMapController>();
  final _sheet = DraggableScrollableController();
  final _query = TextEditingController();
  final _placeFocus = FocusNode();
  Timer? _suggestTimer;
  int _suggestSerial = 0;

  LatLng _pin = _turkey;
  LatLng _cameraTarget = _turkey;
  LatLng? _markedPoint;
  LatLng? _searchedPoint;
  LatLng? _authorizedPoint;
  double _radius = 25;
  String _sort = 'En yakın';
  String _type = 'Tümü';
  String? _selectedId;
  String _placeName = 'Haritadan bir nokta seçin';
  bool _busy = false;
  bool _following = true;
  bool _cameraDrifted = false;
  bool _searched = false;
  String? _error;
  _NearbyGate? _gate;
  NearbyGuesthouse? _routeTarget;
  String _routeMode = 'drive';
  FacilityRoute? _driveRoute;
  FacilityRoute? _walkRoute;
  final Set<String> _loadingModes = {};
  bool _satellite = false;
  double _zoom = 5.4;
  bool _myLocationOn = false;
  bool _locating = false;
  String? _routeNote;
  int _routeSerial = 0;
  List<PlaceSuggestion> _history = const [];
  List<PlaceSuggestion> _localSuggestions = const [];
  List<PlaceSuggestion> _photonSuggestions = const [];
  bool _suggesting = false;
  bool _suggestionsDismissed = false;
  bool _ignoreQuery = false;
  var _lockedCount = 0;
  String? _gateTitle;
  String? _gateBody;
  String? _focusedProvince;
  var _holdProvinceFocus = false;
  final Map<int, BitmapDescriptor> _countIcons = {};
  final _favorites = FavoritesRepository();
  var _routeFavorite = false;
  var _bearing = 0.0;
  double _resting = 0.28;
  final _controlsKey = GlobalKey();
  final _routeCardKey = GlobalKey();
  var _controlsFitted = false;
  var _routeSheet = 0.46;
  var _bodyHeight = 0.0;
  var _fitAttempts = 0;
  var _namesOpen = false;
  String? _radiusNote;
  String? _quotaNote;
  Set<String>? _replayIds;
  var _replayCanRefresh = false;
  BitmapDescriptor? _pinStart;
  BitmapDescriptor? _originPin;
  String? _originCaption;
  BitmapDescriptor? _pinDestination;
  BitmapDescriptor? _pinFacility;
  BitmapDescriptor? _pinBrowse;
  BitmapDescriptor? _pinRevealed;

  @override
  void initState() {
    super.initState();
    _placeFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _query.addListener(_handleQuery);
    LocationDiscoveryScreen.tryConsumeBack = _tryConsumeBack;
    unawaited(_loadHistory());
    unawaited(_loadPins());
    unawaited(_refreshMarkerNames());
  }

  Future<void> _loadPins() async {
    final pins = await Future.wait([
      MapPinIcon.create(color: MapPinIcon.start),
      MapPinIcon.create(color: MapPinIcon.destination, label: 'Varış'),
      MapPinIcon.create(color: MapPinIcon.facility),
      MapPinIcon.create(color: MapPinIcon.browse),
      MapPinIcon.create(color: MapPinIcon.revealed),
    ]);
    if (!mounted) return;
    setState(() {
      _pinStart = pins[0];
      _pinDestination = pins[1];
      _pinFacility = pins[2];
      _pinBrowse = pins[3];
      _pinRevealed = pins[4];
    });
  }

  double _restingFor(double height) {
    const content = 156.0;
    if (height <= 0) return 0.24;
    return (content / height).clamp(0.2, 0.36);
  }

  void _fitControlsToBottom() {
    if (!mounted || _controlsFitted || _searched || _routeTarget != null) {
      return;
    }
    final box = _controlsKey.currentContext?.findRenderObject() as RenderBox?;
    final screen = context.size?.height;
    if (box == null || !box.hasSize || screen == null || screen <= 0) {
      if (_fitAttempts++ > 8) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitControlsToBottom();
      });
      return;
    }
    final fraction = ((box.size.height + 14) / screen).clamp(0.16, 0.46);
    _controlsFitted = true;
    _resting = fraction;
    if (mounted) setState(() {});
    if (_gate == null && _sheet.isAttached) unawaited(_openSheet(fraction));
  }

  void _fitRouteCard() {
    if (!mounted || _routeTarget == null) return;
    final box = _routeCardKey.currentContext?.findRenderObject() as RenderBox?;
    final screen = _bodyHeight;
    if (box == null || !box.hasSize || screen <= 0) return;
    final fraction = (box.size.height / screen).clamp(0.32, 0.56);
    if ((_routeSheet - fraction).abs() >= 0.012) {
      _routeSheet = fraction;
      _routeFrameKey = null;
      setState(() {});
      unawaited(_openSheet(fraction));
    }
    final route = _routeMode == 'walk' ? _walkRoute : _driveRoute;
    if (route != null) unawaited(_fitRoute(route));
  }

  String _ilIlce(Misafirhane facility) {
    final resolved = FacilityAddressRepository.instance.resolveFacility(
      facility,
    );
    final il = IlIlce.canonicalIl(resolved.il) ?? resolved.il.trim();
    var ilce = IlIlce.inferIlce(
      resolved.il,
      ilce: resolved.ilce,
      adres: resolved.adres,
    );
    if (ilce.isEmpty) {
      ilce = IlIlce.canonicalIlce(resolved.il, resolved.ilce);
    }
    if (ilce.isEmpty) {
      ilce = IlIlce.canonicalIlce(resolved.il, resolved.il);
    }
    if (il.isEmpty) return ilce;
    if (ilce.isEmpty) return il;
    return '$il/$ilce';
  }

  @override
  void dispose() {
    if (LocationDiscoveryScreen.tryConsumeBack == _tryConsumeBack) {
      LocationDiscoveryScreen.tryConsumeBack = null;
    }
    _suggestTimer?.cancel();
    _placeFocus.dispose();
    _query.removeListener(_handleQuery);
    _query.dispose();
    _sheet.dispose();
    super.dispose();
  }

  bool _tryConsumeBack() {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (_routeTarget != null) {
      _closeRoute();
      return true;
    }
    if (_gate != null) {
      setState(() {
        _gate = null;
        _gateTitle = null;
        _gateBody = null;
        _lockedCount = 0;
      });
      unawaited(_openSheet(_resting));
      return true;
    }
    if (_placeFocus.hasFocus) {
      _placeFocus.unfocus();
      return true;
    }
    if (_searched) {
      setState(() {
        _searched = false;
        _searchedPoint = null;
        _radiusNote = null;
        _error = null;
        _selectedId = null;
        _dropRouteFields();
      });
      unawaited(_openSheet(_resting));
      return true;
    }
    if (_focusedProvince != null) {
      setState(() => _focusedProvince = null);
      unawaited(_fitTurkey());
      return true;
    }
    return false;
  }

  Future<void> _fitTurkey() async {
    if (!_map.isCompleted) return;
    final controller = await _map.future;
    if (!mounted) return;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: const LatLng(34.85, 26.0),
            northeast: const LatLng(42.15, 44.8),
          ),
          24,
        ),
      );
    } catch (_) {
      await _moveCamera(const LatLng(39.1, 35.2), zoom: 5.5);
    }
  }

  bool _isAuthorized(LatLng point) {
    final authorized = _authorizedPoint;
    if (authorized == null) return false;
    return LocationDiscoveryQuery.sameCell(
      point.latitude,
      point.longitude,
      authorized.latitude,
      authorized.longitude,
    );
  }

  LatLng? _pendingTarget;
  double? _pendingZoom;

  Future<void> _moveCamera(LatLng point, {double? zoom}) async {
    final targetZoom = zoom ?? LocationDiscoveryQuery.zoomForRadius(_radius);
    _pendingTarget = point;
    _pendingZoom = targetZoom;
    if (!_map.isCompleted) return;
    try {
      final controller = await _map.future;
      if (!mounted) return;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(point, targetZoom),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Harita bu noktaya gidemedi. Tekrar deneyin.');
      }
    }
  }

  String _placeTitle(String name) {
    final head = name.split(',').first.trim();
    final title = head.isEmpty ? name.trim() : head;
    if (title.length <= 28) return title;
    return '${title.substring(0, 27).trim()}…';
  }

  void _aim(
    LatLng point, {
    required String name,
    double? zoom,
    bool clearResults = true,
  }) {
    setState(() {
      _pin = point;
      _markedPoint = point;
      _cameraTarget = point;
      _placeName = name;
      _following = false;
      _cameraDrifted = false;
      _error = null;
      if (clearResults) {
        _searched = false;
        _searchedPoint = null;
        _selectedId = null;
        _replayIds = null;
        _replayCanRefresh = false;
        _dropRouteFields();
      }
    });
    unawaited(_moveCamera(point, zoom: zoom ?? 16.6));
    unawaited(_paintOriginPin(name));
  }

  Future<void> _frameSearchCircle(LatLng center, double radiusKm) async {
    if (radiusKm >= 2000) {
      await _fitTurkey();
      return;
    }
    if (!_map.isCompleted) return;
    final controller = await _map.future;
    if (!mounted) return;
    final latRad = center.latitude * math.pi / 180;
    final cosLat = math.cos(latRad).abs().clamp(0.2, 1.0);
    final dLat = radiusKm / 110.574;
    final dLon = radiusKm / (111.320 * cosLat);
    final screen = _bodyHeight > 0
        ? _bodyHeight
        : MediaQuery.sizeOf(context).height;
    final width = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top + 96;
    final cover = _routeTarget != null
        ? _routeSheet
        : _searched
        ? math.max(_resting, 0.48)
        : _resting;
    final bottom = screen * cover;
    final viewW = math.max(140.0, width - 88);
    final viewH = math.max(140.0, screen - top - bottom - 16);
    final latSpan = dLat * 2.16;
    final lonSpan = dLon * 2.16;
    final latFraction =
        (_mercatorY(center.latitude - latSpan / 2) -
                _mercatorY(center.latitude + latSpan / 2))
            .abs()
            .clamp(0.000001, 1.0);
    final lonFraction = (lonSpan / 360).clamp(0.000001, 1.0);
    final latZoom = math.log(viewH / (256 * latFraction)) / math.ln2;
    final lonZoom = math.log(viewW / (256 * lonFraction)) / math.ln2;
    final zoom = math.min(latZoom, lonZoom).clamp(5.4, 16.0);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await controller.animateCamera(CameraUpdate.newLatLngZoom(center, zoom));
  }

  void _frameFound(LatLng point, double radius, {required bool holdCamera}) {
    if (holdCamera) return;
    unawaited(_frameSearchCircle(point, radius));
  }

  void _selectRadius(double radius) {
    final origin = _searchedPoint ?? _markedPoint ?? _pin;
    setState(() {
      _radius = radius;
      _replayIds = null;
      _replayCanRefresh = false;
      _radiusNote = null;
    });
    unawaited(_frameSearchCircle(origin, radius));
  }

  Future<void> _paintOriginPin(String name) async {
    final caption = _placeTitle(name);
    if (caption.isEmpty || caption == _originCaption) return;
    final pin = await MapPinIcon.create(
      color: MapPinIcon.start,
      label: caption,
    );
    if (!mounted || _placeTitle(_placeName) != caption) return;
    setState(() {
      _originCaption = caption;
      _originPin = pin;
    });
  }

  void _dropRouteFields() {
    _routeTarget = null;
    _driveRoute = null;
    _walkRoute = null;
    _loadingModes.clear();
    _routeNote = null;
    _routeSerial += 1;
    _routeFrameKey = null;
  }

  /// Yol, aramanın hak düşürdüğü noktadan çizilir. Tesis veya kamera yeni hak açmaz.
  LatLng? get _routeOrigin => _searchedPoint ?? _authorizedPoint ?? _markedPoint;

  void _openFacilityCard(Misafirhane facility) {
    unawaited(
      pushOnShellNavigator<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'konum-facility'),
          builder: (_) => KonumFacilityPage(facility: facility),
        ),
      ),
    );
  }

  Future<void> _openRoute(NearbyGuesthouse item) async {
    final start = _routeOrigin;
    if (start == null) {
      setState(() => _error = 'Önce haritada bir yer işaretleyin.');
      return;
    }
    final serial = ++_routeSerial;
    if (_sheet.isAttached && (_sheet.size < 0.28 || _sheet.size > 0.55)) {
      _sheet.jumpTo(0.46);
    }
    setState(() {
      _selectedId = item.facility.stableFacilityId;
      _routeTarget = item;
      _routeMode = 'drive';
      _driveRoute = null;
      _walkRoute = null;
      _routeNote = null;
      _loadingModes.clear();
      _cameraDrifted = false;
      _error = null;
    });
    unawaited(_openSheet(_routeSheet));
    unawaited(_syncRouteFavorite(item.facility));
    unawaited(_loadMode(item, start, 'drive', serial, fit: true));
    if (FacilityRouteFormat.walkingOffered(item.km)) {
      unawaited(_loadMode(item, start, 'walk', serial, fit: false));
    }
  }

  Future<void> _selectRouteMode(String mode) async {
    final item = _routeTarget;
    final start = _routeOrigin;
    if (item == null || start == null) return;
    if (mode == 'walk' && !FacilityRouteFormat.walkingOffered(item.km)) return;
    setState(() {
      _routeMode = mode;
      _routeNote = null;
    });
    final saved = mode == 'walk' ? _walkRoute : _driveRoute;
    if (saved != null) {
      await _fitRoute(saved);
      return;
    }
    await _loadMode(item, start, mode, _routeSerial, fit: true);
  }

  Future<void> _loadMode(
    NearbyGuesthouse item,
    LatLng start,
    String mode,
    int serial, {
    required bool fit,
  }) async {
    setState(() => _loadingModes.add(mode));
    try {
      final user = PremiumAuthService.instance.currentUser;
      final signedIn = user != null && !user.isAnonymous;
      late final FacilityRoute route;
      if (signedIn) {
        route = await FacilityRouteAccess.fetch(
          originLat: start.latitude,
          originLon: start.longitude,
          destLat: item.facility.latitude,
          destLon: item.facility.longitude,
          mode: mode,
        );
      } else if (await _freeRouteAllowed(start)) {
        route = await _publicRoute(
          start: start,
          destLat: item.facility.latitude,
          destLon: item.facility.longitude,
          mode: mode,
        );
      } else {
        throw StateError(
          'Yol çizimi, bu ayki ücretsiz yakın aramanızla açılır.',
        );
      }
      if (!mounted || serial != _routeSerial || _routeTarget == null) return;
      setState(() {
        if (mode == 'walk') {
          _walkRoute = route;
        } else {
          _driveRoute = route;
        }
        _loadingModes.remove(mode);
      });
      if (fit && mode == _routeMode) await _fitRoute(route);
    } catch (error) {
      if (!mounted || serial != _routeSerial) return;
      setState(() {
        _loadingModes.remove(mode);
        if (mode == _routeMode) {
          _routeNote = error.toString().replaceFirst('Bad state: ', '');
        }
      });
    }
  }

  Set<Polyline> _routeLine(
    String id,
    FacilityRoute route,
    Color color,
    int width,
    int zIndex,
  ) {
    final origin = _routeOrigin;
    final facility = _routeTarget?.facility;
    final draw = origin == null || facility == null
        ? FacilityRouteDraw(road: route.points)
        : FacilityRouteDraw.of(
            route,
            originLatitude: origin.latitude,
            originLongitude: origin.longitude,
            destinationLatitude: facility.latitude,
            destinationLongitude: facility.longitude,
          );
    Polyline line(
      String suffix,
      List<({double latitude, double longitude})> points,
    ) {
      return Polyline(
        polylineId: PolylineId(suffix.isEmpty ? id : '$id-$suffix'),
        points: [
          for (final point in points) LatLng(point.latitude, point.longitude),
        ],
        color: color,
        width: width,
        geodesic: false,
        zIndex: zIndex,
      );
    }

    if (draw.road.length < 2) return const {};
    return {line('', draw.road)};
  }

  String? _routeFrameKey;

  double _mercatorY(double latitude) {
    final sin = math.sin(latitude * math.pi / 180);
    final y = 0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi);
    return y.clamp(0.0, 1.0);
  }

  Future<void> _fitRoute(FacilityRoute route) async {
    if (!_map.isCompleted) return;
    final key =
        '${route.mode}|${_routeSheet.toStringAsFixed(3)}|${route.distanceMeters}|${route.points.length}';
    if (_routeFrameKey == key) return;
    _routeFrameKey = key;
    final controller = await _map.future;
    if (!mounted || _routeTarget == null) return;
    double? south, north, west, east;
    void include(double latitude, double longitude) {
      south = south == null || latitude < south! ? latitude : south;
      north = north == null || latitude > north! ? latitude : north;
      west = west == null || longitude < west! ? longitude : west;
      east = east == null || longitude > east! ? longitude : east;
    }

    for (final point in route.points) {
      include(point.latitude, point.longitude);
    }
    final start = _routeOrigin;
    final destination = _routeTarget?.facility;
    if (start != null) include(start.latitude, start.longitude);
    if (destination != null) {
      include(destination.latitude, destination.longitude);
    }
    final southBound = south;
    final northBound = north;
    final westBound = west;
    final eastBound = east;
    if (southBound == null ||
        northBound == null ||
        westBound == null ||
        eastBound == null) {
      return;
    }
    final center = LatLng(
      (southBound + northBound) / 2,
      (westBound + eastBound) / 2,
    );
    final latSpan = math.max(northBound - southBound, 0.0012);
    final lonSpan = math.max(eastBound - westBound, 0.0012);
    final screen = _bodyHeight > 0
        ? _bodyHeight
        : MediaQuery.sizeOf(context).height;
    final width = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top + 76;
    final bottom = screen * _routeSheet;
    final viewW = math.max(140.0, width - 72);
    final viewH = math.max(140.0, (screen - top - bottom) * 0.84);
    final latFraction =
        (_mercatorY(center.latitude - latSpan / 2) -
                _mercatorY(center.latitude + latSpan / 2))
            .abs()
            .clamp(0.000001, 1.0);
    final lonFraction = (lonSpan / 360).clamp(0.000001, 1.0);
    final latZoom = math.log(viewH / (256 * latFraction)) / math.ln2;
    final lonZoom = math.log(viewW / (256 * lonFraction)) / math.ln2;
    final zoom = math.min(latZoom, lonZoom).clamp(6.0, 16.5);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _routeTarget == null || _routeFrameKey != key) return;
    await controller.animateCamera(CameraUpdate.newLatLngZoom(center, zoom));
  }

  void _closeRoute() {
    setState(() {
      _dropRouteFields();
      // Rota kadrajı yeni bir arama değildir; hak yalnızca tesis listesi çıkınca düşer.
      _cameraDrifted = false;
    });
  }

  List<Misafirhane> _shownFacilities(List<NearbyGuesthouse> items) {
    return LocationDiscoveryQuery.present(
      items,
      type: _type,
      sort: _sort,
    ).map((item) => item.facility).toList();
  }

  void _keepReplay(Set<String>? ids, bool canRefresh) {
    _replayIds = ids;
    _replayCanRefresh = canRefresh;
  }

  static const _freeNearbyMonthKey = 'rotalink_free_nearby_month';
  static const _freeNearbyCellKey = 'rotalink_free_nearby_cell';
  static const _freeNearbyCellsKey = 'rotalink_free_nearby_cells';

  String _nearbyCell(LatLng point) =>
      '${(point.latitude * 100).round()}:${(point.longitude * 100).round()}';

  String _istanbulMonth() {
    final ist = DateTime.now().toUtc().add(const Duration(hours: 3));
    final month = ist.month.toString().padLeft(2, '0');
    return '${ist.year}-$month';
  }

  List<String> _cellsThisMonth(SharedPreferences prefs) {
    if (prefs.getString(_freeNearbyMonthKey) != _istanbulMonth()) return const [];
    final raw = prefs.getString(_freeNearbyCellsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return [
            for (final item in decoded)
              if (item is String && item.isNotEmpty) item,
          ];
        }
      } catch (_) {}
    }
    final single = prefs.getString(_freeNearbyCellKey);
    if (single != null && single.isNotEmpty) return [single];
    return const [];
  }

  /// Hesapsız yakın arama, admin panelindeki aylık hak kadar serbest.
  /// Aynı nokta yeniden hak yemez.
  Future<bool> _unsignedNearbyAllowed(LatLng point) async {
    await PremiumRightsCatalog.instance.refresh();
    final prefs = await SharedPreferences.getInstance();
    final cells = _cellsThisMonth(prefs);
    if (cells.contains(_nearbyCell(point))) return true;
    return cells.length < PremiumRightsCatalog.instance.freeNearby;
  }

  /// Yol çizgisi, bu ay ücretsiz aranan nokta için açılır.
  Future<bool> _freeRouteAllowed(LatLng point) async {
    final prefs = await SharedPreferences.getInstance();
    return _cellsThisMonth(prefs).contains(_nearbyCell(point));
  }

  Future<FacilityRoute> _publicRoute({
    required LatLng start,
    required double destLat,
    required double destLon,
    required String mode,
  }) async {
    final line = await OsrmRouteService.fetchDirect(
      originLat: start.latitude,
      originLon: start.longitude,
      destLat: destLat,
      destLon: destLon,
      mode: mode,
    );
    if (line == null) {
      throw StateError('Yol çizilemedi. Biraz sonra tekrar deneyin.');
    }
    return FacilityRoute(
      mode: mode,
      distanceMeters: line.distanceM.round(),
      durationSeconds: line.durationS.round(),
      points: [
        for (final point in line.points)
          (latitude: point.latitude, longitude: point.longitude),
      ],
    );
  }

  Future<void> _rememberUnsignedNearby(LatLng point) async {
    final prefs = await SharedPreferences.getInstance();
    final cell = _nearbyCell(point);
    final cells = _cellsThisMonth(prefs);
    final next = cells.contains(cell) ? cells : [...cells, cell];
    await prefs.setString(_freeNearbyMonthKey, _istanbulMonth());
    await prefs.setString(_freeNearbyCellKey, cell);
    await prefs.setString(_freeNearbyCellsKey, jsonEncode(next));
    FreeNearbyQuota.changed();
  }

  void _rememberCloudSearch(LatLng point, List<Misafirhane> facilities) {
    final saved = facilities
        .take(400)
        .map((facility) => (il: facility.il, isim: facility.isim))
        .toList();
    unawaited(
      LocalMapSearchHistory.remember(
        displayName: _placeTitle(_placeName),
        addressSummary: _placeName,
        radiusKm: _radius,
        facilityType: _type,
        latitude: point.latitude,
        longitude: point.longitude,
        facilities: saved,
      ),
    );
  }

  Future<void> _search(
    RotaDataState data, {
    bool forceClaim = false,
    bool holdCamera = false,
  }) async {
    final savedReplay = _replayIds;
    final savedRefresh = _replayCanRefresh;
    if (savedReplay != null) {
      setState(() {
        _replayIds = null;
        _replayCanRefresh = false;
      });
    }
    if (_routeTarget != null) setState(_dropRouteFields);
    var point = _pin;
    if (!_following && _cameraDrifted) {
      point = _cameraTarget;
      setState(() {
        _pin = point;
        _markedPoint = point;
        _placeName = 'Haritada seçilen nokta';
        _following = true;
        _cameraDrifted = false;
        _searched = false;
        _searchedPoint = null;
        _selectedId = null;
      });
      unawaited(_moveCamera(point));
    }

    final steps = <double>[5, 10, 25, 50];
    var radius = _radius;
    var inRadius = NearbyGuesthouses.find(
      data.aramaIcinTumTesisler,
      point.latitude,
      point.longitude,
      radiusKm: radius >= 2000 ? double.infinity : radius,
    );
    String? widenNote;
    if (inRadius.isEmpty && radius < 2000) {
      final start = steps.indexWhere((step) => (step - radius).abs() < 0.1);
      for (var i = (start < 0 ? 0 : start + 1); i < steps.length; i++) {
        final wider = NearbyGuesthouses.find(
          data.aramaIcinTumTesisler,
          point.latitude,
          point.longitude,
          radiusKm: steps[i],
        );
        if (wider.isEmpty) continue;
        widenNote =
            '${radius.toInt()} km içerisinde misafirhane bulunmamaktadır.';
        radius = steps[i];
        inRadius = wider;
        break;
      }
    }
    if (radius != _radius) {
      setState(() => _radius = radius);
    }
    final shown = _shownFacilities(inRadius);
    if (shown.isEmpty) {
      setState(() {
        _searched = true;
        _searchedPoint = point;
        _markedPoint = point;
        _following = false;
        _cameraDrifted = false;
        _gate = null;
        _radiusNote = null;
        _quotaNote = null;
        _error = 'Bu çevrede tesis yok. Mesafeyi büyütün.';
      });
      _rememberCloudSearch(point, const []);
      _frameFound(point, radius, holdCamera: holdCamera);
      return;
    }
    if (!forceClaim && _isAuthorized(point)) {
      setState(() {
        _searched = true;
        _searchedPoint = point;
        _markedPoint = point;
        _following = false;
        _cameraDrifted = false;
        _gate = null;
        _radiusNote = widenNote;
        _quotaNote = null;
        _error = null;
      });
      _rememberCloudSearch(point, shown);
      unawaited(_revealSheet());
      _frameFound(point, radius, holdCamera: holdCamera);
      return;
    }
    final user = PremiumAuthService.instance.currentUser;
    if (user == null || user.isAnonymous) {
      final allowed = await _unsignedNearbyAllowed(point);
      if (!mounted) return;
      if (!allowed) {
        setState(() {
          _keepReplay(savedReplay, savedRefresh);
          _gate = _NearbyGate.quota;
          _gateTitle = null;
          _gateBody = null;
          _lockedCount = inRadius.length;
          _error = null;
        });
        unawaited(_openSheet(_lockedCount > 0 ? 0.72 : 0.62));
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final month = _istanbulMonth();
      final cell = _nearbyCell(point);
      final cells = _cellsThisMonth(prefs);
      final spends = prefs.getString(_freeNearbyMonthKey) != month ||
          !cells.contains(cell);
      await _rememberUnsignedNearby(point);
      if (!mounted) return;
      setState(() {
        _searched = true;
        _searchedPoint = point;
        _markedPoint = point;
        _following = false;
        _cameraDrifted = false;
        _gate = null;
        _radiusNote = widenNote;
        _quotaNote = spends
            ? 'Ücretsiz yakın arama hakkınız bu aramayla kullanıldı.'
            : null;
        _error = null;
      });
      _rememberCloudSearch(point, shown);
      unawaited(_revealSheet());
      _frameFound(point, radius, holdCamera: holdCamera);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final access = await NearbySearchAccess.claim(
        point.latitude,
        point.longitude,
        _radius,
      );
      if (!mounted) return;
      if (!access.accepted) {
        setState(() {
          _keepReplay(savedReplay, savedRefresh);
          _gate = _NearbyGate.quota;
          _gateTitle = null;
          _gateBody = null;
          _lockedCount = inRadius.length;
          _error = null;
        });
        unawaited(_openSheet(_lockedCount > 0 ? 0.72 : 0.62));
        return;
      }
      if (access.empty) {
        setState(() {
          _searched = true;
          _searchedPoint = point;
          _markedPoint = point;
          _following = false;
          _gate = null;
          _quotaNote = null;
          _error = 'Bu çevrede sonuç bulunamadı. Mesafeyi büyütün.';
        });
        _rememberCloudSearch(point, const []);
        _frameFound(point, radius, holdCamera: holdCamera);
        return;
      }
      final remaining = access.remaining;
      FreeNearbyQuota.rememberServer(remaining);
      final quotaNote = access.charged
          ? remaining == null
                ? 'Bu arama 1 yakın arama hakkı kullandı.'
                : 'Bu arama 1 yakın arama hakkı kullandı. Kalan: $remaining.'
          : null;
      setState(() {
        _searched = true;
        _searchedPoint = point;
        _markedPoint = point;
        _authorizedPoint = point;
        _following = false;
        _cameraDrifted = false;
        _gate = null;
        _radiusNote = widenNote;
        _quotaNote = quotaNote;
        _error = null;
      });
      _rememberCloudSearch(point, shown);
      if (access.charged) {
        try {
          await ServerPremiumAccountBridge.instance.refresh();
        } catch (_) {}
        if (!mounted) return;
      }
      unawaited(_revealSheet());
      _frameFound(point, radius, holdCamera: holdCamera);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _keepReplay(savedReplay, savedRefresh);
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revealSheet() => _openSheet(0.48);

  Future<void> _openSheet(double size) async {
    if (!_sheet.isAttached) return;
    if ((_sheet.size - size).abs() < 0.02) return;
    await _sheet.animateTo(
      size,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goToMyLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final outcome = await SimpleLocationService.requestFromUserTap();
      if (!mounted) return;
      if (outcome != PermissionRequestOutcome.granted) {
        setState(() {
          _myLocationOn = false;
          _error =
              'Konum izni verilmedi. Haritayı kaydırarak nokta seçebilirsiniz.';
        });
        return;
      }
      final servicesOn =
          await SimpleLocationService.promptEnableLocationService();
      if (!mounted) return;
      if (!servicesOn) {
        setState(() {
          _myLocationOn = false;
          _error = 'Konum kapalı. Açılan pencereden konumu açın.';
        });
        return;
      }
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (_) {}
      if (!mounted) return;
      if (!_usable(position)) {
        setState(() {
          _myLocationOn = false;
          _error = 'Konum alınamadı. Haritadan nokta seçerek devam edin.';
        });
        return;
      }
      _showUser(position!);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool _usable(Position? position) {
    if (position == null) return false;
    final latitude = position.latitude;
    final longitude = position.longitude;
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        !(latitude == 0 && longitude == 0);
  }

  void _showUser(Position position) {
    final point = LatLng(position.latitude, position.longitude);
    setState(() {
      _myLocationOn = true;
      _pin = point;
      _cameraTarget = point;
      _following = true;
      _cameraDrifted = false;
      _error = null;
      _placeName = 'Bulunduğunuz konum';
    });
    unawaited(_moveCamera(point, zoom: 16));
  }

  Future<void> _loadHistory() async {
    final saved = await PlaceSearchHistory.load();
    if (!mounted) return;
    setState(() => _history = saved);
  }

  Future<void> _rememberPlace(String name, LatLng point) async {
    final saved = await PlaceSearchHistory.remember(
      PlaceSuggestion(
        title: _placeTitle(name),
        subtitle: 'Son arama',
        latitude: point.latitude,
        longitude: point.longitude,
        recent: true,
      ),
    );
    if (mounted) setState(() => _history = saved);
  }

  void _handleQuery() => _onQueryChanged(_query.text);

  void _onQueryChanged(String value) {
    if (_ignoreQuery) return;
    _suggestionsDismissed = false;
    _suggestTimer?.cancel();
    final query = value.trim();
    final facilities =
        widget.repository.currentState?.aramaIcinTumTesisler ??
        const <Misafirhane>[];
    setState(() {
      _error = null;
      _localSuggestions = _matchLocal(query, facilities);
      _photonSuggestions = const [];
      _suggesting = query.length >= 3;
    });
    if (query.length < 3) return;
    final serial = ++_suggestSerial;
    _suggestTimer = Timer(const Duration(milliseconds: 450), () async {
      final found = await _placeSuggestions(query);
      if (!mounted || serial != _suggestSerial) return;
      setState(() {
        _photonSuggestions = found;
        _suggesting = false;
      });
    });
  }

  Future<List<PlaceSuggestion>> _placeSuggestions(String query) async {
    final user = PremiumAuthService.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        final predictions = await NearbySearchAccess.suggest(query);
        if (predictions.isNotEmpty) {
          return [
            for (final item in predictions)
              PlaceSuggestion(
                title: item.title,
                subtitle: item.subtitle,
                latitude: item.latitude ?? 0,
                longitude: item.longitude ?? 0,
                placeId: item.placeId,
              ),
          ];
        }
      } catch (_) {}
    }
    try {
      final places = await NearbySearchAccess.publicSearch(query);
      if (places.isNotEmpty) {
        return [
          for (final item in places.take(5))
            PlaceSuggestion(
              title: item.name,
              subtitle: 'Harita',
              latitude: item.latitude,
              longitude: item.longitude,
            ),
        ];
      }
    } catch (_) {}
    return PhotonPlaceSearch.suggest(query);
  }

  List<PlaceSuggestion> _matchLocal(
    String query,
    List<Misafirhane> facilities,
  ) {
    final q = KamiCityResolver.normalize(query);
    if (q.length < 2) return const [];
    final tokens = q.split(' ').where((token) => token.isNotEmpty).toList();
    final found = <PlaceSuggestion>[];
    final kktc = KamiProvinceCenters.centerFor('Kıbrıs');
    final kktcQuery = KamiCityResolver.normalize(query);
    if (kktc != null &&
        kktcQuery.length >= 3 &&
        ('kibris'.contains(kktcQuery) ||
            'kktc'.contains(kktcQuery) ||
            'kuzey kibris'.contains(kktcQuery))) {
      found.add(
        PlaceSuggestion(
          title: 'Kıbrıs',
          subtitle: 'İl',
          latitude: kktc.latitude,
          longitude: kktc.longitude,
        ),
      );
    }
    for (final city in KamiProvinceCenters.byDisplayName.entries) {
      if (!KamiCityResolver.normalize(city.key).contains(q)) continue;
      found.add(
        PlaceSuggestion(
          title: city.key,
          subtitle: 'İl',
          latitude: city.value.latitude,
          longitude: city.value.longitude,
        ),
      );
      if (found.length == 3) break;
    }
    for (final place in PlaceResolver.local(query, facilities)) {
      if (found.any((item) => item.title == place.name)) continue;
      found.add(
        PlaceSuggestion(
          title: place.name,
          subtitle: place.name.contains(' / ') ? 'İlçe' : 'İl',
          latitude: place.latitude,
          longitude: place.longitude,
        ),
      );
    }
    var facilitiesAdded = 0;
    for (final facility in facilities) {
      if (facility.latitude == 0 || facility.longitude == 0) continue;
      final haystack = KamiCityResolver.normalize(
        '${facility.il} ${facility.ilce} ${facility.isim}',
      );
      if (!tokens.every(haystack.contains)) continue;
      found.add(
        PlaceSuggestion(
          title: facility.isim,
          subtitle: _ilIlce(facility),
          latitude: facility.latitude,
          longitude: facility.longitude,
        ),
      );
      facilitiesAdded += 1;
      if (facilitiesAdded == 4) break;
    }
    return found;
  }

  bool get _suggestionsOpen {
    if (_suggestionsDismissed || !_placeFocus.hasFocus) return false;
    if (_query.text.trim().length < 2) return false;
    return _history.isNotEmpty ||
        _localSuggestions.isNotEmpty ||
        _photonSuggestions.isNotEmpty ||
        _suggesting;
  }

  void _closeSuggestions() {
    _suggestTimer?.cancel();
    _suggestSerial += 1;
    _suggestionsDismissed = true;
    _placeFocus.unfocus();
    if (!mounted) return;
    setState(() {
      _localSuggestions = const [];
      _photonSuggestions = const [];
      _suggesting = false;
    });
  }

  Future<void> _chooseSuggestion(PlaceSuggestion item) async {
    var title = item.title;
    var point = LatLng(item.latitude, item.longitude);
    final placeId = item.placeId;
    if (placeId == null && item.latitude != 0 && item.longitude != 0) {
      title = item.title;
      point = LatLng(item.latitude, item.longitude);
    } else if (placeId != null) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final place = await NearbySearchAccess.place(placeId);
        if (!mounted) return;
        if (place == null) {
          setState(
            () => _error =
                'Konum bulunamadı. Haritadan nokta seçebilirsiniz.',
          );
          return;
        }
        title = place.name;
        point = LatLng(place.latitude, place.longitude);
      } catch (error) {
        if (!mounted) return;
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    _ignoreQuery = true;
    _query.text = title;
    _ignoreQuery = false;
    _closeSuggestions();
    _aim(
      point,
      name: _placeTitle(title),
      zoom: item.subtitle == 'İl'
          ? 11.6
          : item.subtitle == 'İlçe'
          ? 13.2
          : 16.6,
    );
    await _rememberPlace(title, point);
  }

  Future<void> _openSearchHistory() async {
    FocusScope.of(context).unfocus();
    await showMapSearchHistorySheet(
      context: context,
      onReplay: _replayHistory,
    );
  }

  Future<void> _replayHistory(MapHistoryEntry entry) async {
    final data =
        widget.repository.currentState ??
        await widget.repository.watchRoot().first;
    if (!mounted) return;
    final ids = {
      for (final facility in entry.facilities)
        '${facility.il}\u0001${facility.isim}',
    };
    final kept = [
      for (final facility in data.aramaIcinTumTesisler)
        if (ids.contains(facility.stableFacilityId)) facility,
    ];
    final latitude = entry.originLatitude;
    final longitude = entry.originLongitude;
    final origin = latitude == null || longitude == null
        ? null
        : LatLng(latitude, longitude);
    LatLng? frame = origin;
    if (frame == null && kept.isNotEmpty) {
      var lat = 0.0;
      var lon = 0.0;
      var count = 0;
      for (final facility in kept) {
        if (facility.latitude == 0 || facility.longitude == 0) continue;
        lat += facility.latitude;
        lon += facility.longitude;
        count += 1;
      }
      if (count > 0) frame = LatLng(lat / count, lon / count);
    }
    final type = LocationDiscoveryQuery.facilityTypes.contains(
          entry.facilityType,
        )
        ? entry.facilityType
        : 'Tümü';
    final radius = LocationDiscoveryQuery.radiiKm.contains(entry.radiusKm)
        ? entry.radiusKm
        : _radius;
    setState(() {
      _replayIds = ids;
      _replayCanRefresh = origin != null;
      _searched = true;
      _searchedPoint = origin ?? frame;
      _markedPoint = origin;
      if (origin != null) {
        _pin = origin;
        _cameraTarget = origin;
      }
      _placeName = entry.displayName;
      _radius = radius;
      _type = type;
      _following = false;
      _cameraDrifted = false;
      _gate = null;
      _radiusNote = null;
      _selectedId = null;
      _error = kept.isEmpty ? 'Kayıtlı tesisler artık listede yok.' : null;
      _dropRouteFields();
    });
    unawaited(_paintOriginPin(entry.displayName));
    if (origin != null) {
      unawaited(_frameSearchCircle(origin, radius));
    } else if (frame != null) {
      unawaited(_moveCamera(frame, zoom: 11));
    }
    unawaited(_revealSheet());
  }

  Future<void> _searchText() async {
    if (_busy) return;
    final raw = _query.text.trim();
    final q = KamiCityResolver.normalize(raw);
    final seenSuggestions = [
      ..._localSuggestions,
      ..._photonSuggestions,
    ];
    _closeSuggestions();
    if (q.length < 2) {
      setState(() => _error = 'Bir il, ilçe, adres veya tesis adı yazın.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _resolveSearchText(raw, q, seenSuggestions);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolveSearchText(
    String raw,
    String q,
    List<PlaceSuggestion> seenSuggestions,
  ) async {
    final signedIn = PremiumAuthService.instance.currentUser != null &&
        !PremiumAuthService.instance.currentUser!.isAnonymous;
    debugPrint('[Harita] arama "$raw" q="$q" signedIn=$signedIn');
    final entries = <({String name, LatLng point})>[];
    String? remoteError;
    void addPlaces(List<ResolvedPlace> places) {
      for (final place in places) {
        if (entries.length >= 8) return;
        entries.add((
          name: place.name,
          point: LatLng(place.latitude, place.longitude),
        ));
      }
    }

    final loaded = widget.repository.currentState?.aramaIcinTumTesisler;
    final travel = PlaceResolver.travelDestination(raw);
    final local = travel == null
        ? PlaceResolver.local(raw, loaded ?? const <Misafirhane>[])
        : const <ResolvedPlace>[];
    final specific = travel == null && local.isEmpty;
    if (travel != null) {
      addPlaces([travel]);
    } else if (!specific) {
      addPlaces(local);
    }
    debugPrint('[Harita] yerel eşleşme: ${entries.length} specific=$specific');
    if (entries.isEmpty && loaded != null) {
      var facilitiesAdded = 0;
      for (final facility in loaded) {
        if (facility.latitude == 0 || facility.longitude == 0) continue;
        if (!KamiCityResolver.normalize(
          '${facility.il} ${facility.ilce} ${facility.isim}',
        ).contains(q)) {
          continue;
        }
        entries.add((
          name: '${facility.isim} · ${_ilIlce(facility)}',
          point: LatLng(facility.latitude, facility.longitude),
        ));
        facilitiesAdded += 1;
        if (facilitiesAdded >= 8) break;
      }
      debugPrint('[Harita] tesis eşleşmesi: $facilitiesAdded');
    }
    if (entries.isEmpty && signedIn) {
      try {
        final predictions = await NearbySearchAccess.suggest(raw);
        if (!mounted) return;
        if (predictions.isNotEmpty) {
          final first = predictions.first;
          if (first.hasPoint) {
            remoteError = null;
            entries.add((
              name: first.title,
              point: LatLng(first.latitude!, first.longitude!),
            ));
          } else if (first.placeId != null) {
            final place = await NearbySearchAccess.place(first.placeId!);
            if (!mounted) return;
            if (place != null) {
              remoteError = null;
              entries.add((
                name: place.name,
                point: LatLng(place.latitude, place.longitude),
              ));
            }
          }
        }
        debugPrint('[Harita] places: ${entries.length} sonuç');
      } catch (error) {
        remoteError = error.toString().replaceFirst('Bad state: ', '');
        debugPrint('[Harita] places hatası: $remoteError');
      }
    }
    if (entries.isEmpty) {
      final hinted = _bestSeenSuggestion(seenSuggestions, raw, specific);
      if (hinted != null) {
        entries.add((
          name: hinted.subtitle.isEmpty || hinted.subtitle == 'İl' || hinted.subtitle == 'İlçe'
              ? hinted.title
              : '${hinted.title} · ${hinted.subtitle}',
          point: LatLng(hinted.latitude, hinted.longitude),
        ));
      }
    }
    if (entries.isEmpty && signedIn) {
      for (var attempt = 0; attempt < 2 && entries.isEmpty; attempt++) {
        try {
          final remote = await NearbySearchAccess.geocode(raw);
          debugPrint('[Harita] Google geocode: ${remote.length} sonuç');
          remoteError = null;
          if (remote.isNotEmpty) {
            final place = remote.first;
            entries.add((
              name: place.name,
              point: LatLng(place.latitude, place.longitude),
            ));
          }
        } catch (error) {
          remoteError = error.toString().replaceFirst('Bad state: ', '');
          debugPrint('[Harita] Google geocode hatası: $remoteError');
          if (attempt == 0 && remoteError.contains('Çok fazla')) break;
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
        }
        if (!mounted) return;
      }
    }
    if (entries.isEmpty) {
      try {
        final remote = await NearbySearchAccess.publicSearch(raw);
        debugPrint('[Harita] ortak arama: ${remote.length} sonuç');
        if (remote.isNotEmpty) {
          remoteError = null;
          final place = remote.first;
          entries.add((
            name: place.name,
            point: LatLng(place.latitude, place.longitude),
          ));
        }
      } catch (error) {
        remoteError ??= error.toString().replaceFirst('Bad state: ', '');
        debugPrint('[Harita] ortak arama hatası: $remoteError');
      }
      if (!mounted) return;
    }
    if (entries.isEmpty) {
      final ranked = await NominatimGeocodeCache.rankedPlace(raw);
      if (!mounted) return;
      debugPrint('[Harita] nominatim: ${ranked?.name}');
      if (ranked != null) {
        remoteError = null;
        entries.add((
          name: ranked.name,
          point: LatLng(ranked.latitude, ranked.longitude),
        ));
      }
    }
    if (entries.isEmpty) {
      final photon = await PhotonPlaceSearch.any(PlaceResolver.searchPhrase(raw));
      if (!mounted) return;
      debugPrint('[Harita] photon: ${photon?.title}');
      if (photon != null) {
        remoteError = null;
        entries.add((
          name: photon.subtitle.isEmpty
              ? photon.title
              : '${photon.title} · ${photon.subtitle}',
          point: LatLng(photon.latitude, photon.longitude),
        ));
      }
    }
    if (entries.isEmpty) {
      final places = await PlaceResolver.openMeteo(raw);
      if (!mounted) return;
      debugPrint('[Harita] open-meteo: ${places.length} aday');
      final matched = [
        for (final place in places)
          if (!specific || _placeScore(place.name, raw) > 0) place,
      ];
      final usable = matched.isNotEmpty ? matched : places;
      for (final place in usable) {
        entries.add((
          name: place.name,
          point: LatLng(place.latitude, place.longitude),
        ));
      }
    }
    if (entries.isEmpty) {
      final loose = await PhotonPlaceSearch.any(raw);
      if (!mounted) return;
      if (loose != null) {
        entries.add((
          name: loose.subtitle.isEmpty
              ? loose.title
              : '${loose.title} · ${loose.subtitle}',
          point: LatLng(loose.latitude, loose.longitude),
        ));
      }
    }
    if (entries.isEmpty) {
      debugPrint('[Harita] sonuç yok, hata: ${remoteError ?? 'konum bulunamadı'}');
      setState(
        () => _error =
            remoteError ?? 'Konum bulunamadı. Haritadan nokta seçebilirsiniz.',
      );
      return;
    }
    if (specific && entries.length > 1) {
      entries.sort(
        (a, b) => _placeScore(b.name, raw).compareTo(_placeScore(a.name, raw)),
      );
      final best = _placeScore(entries.first.name, raw);
      if (best > 0) {
        final tied = entries
            .where((entry) => _placeScore(entry.name, raw) == best)
            .toList();
        entries
          ..clear()
          ..addAll(tied);
      }
    }
    final exact = entries.where((entry) {
      final head = entry.name.split(' · ').first;
      return KamiCityResolver.normalize(entry.name) == q ||
          KamiCityResolver.normalize(head) == q;
    }).toList();
    final chosen = exact.length == 1
        ? exact.first
        : entries.length == 1
        ? entries.first
        : await showModalBottomSheet<({String name, LatLng point})>(
            context: context,
            useRootNavigator: true,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text('Eşleşen yerler'),
                    subtitle: Text('Haritayı bu noktaya götürür.'),
                  ),
                  for (final entry in entries)
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(
                        entry.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(sheetContext, entry),
                    ),
                ],
              ),
            ),
          );
    if (!mounted || chosen == null) return;
    FocusScope.of(context).unfocus();
    _aim(
      chosen.point,
      name: _placeTitle(chosen.name),
      zoom: specific ? 16.6 : _adminZoom(chosen.name),
    );
    await _rememberPlace(chosen.name, chosen.point);
    if (!mounted) return;
    var latest = widget.repository.currentState;
    if (latest == null) {
      try {
        latest = await widget.repository
            .watchRoot()
            .first
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    if (!mounted || latest == null) return;
    await _search(latest, holdCamera: specific);
  }

  PlaceSuggestion? _bestSeenSuggestion(
    List<PlaceSuggestion> items,
    String raw,
    bool specific,
  ) {
    PlaceSuggestion? best;
    var bestScore = 0;
    for (final item in items) {
      final score = _placeScore('${item.title} ${item.subtitle}', raw);
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    if (best != null) return best;
    if (specific || items.length != 1) return null;
    final only = items.first;
    return only.subtitle == 'İl' || only.subtitle == 'İlçe' ? only : null;
  }

  double _adminZoom(String name) => name.contains('/') ? 13.2 : 11.6;

  int _placeScore(String name, String query) {
    final folded = KamiCityResolver.normalize(name);
    var score = 0;
    for (final token in KamiCityResolver.normalize(query).split(' ')) {
      if (token.length < 3 || IlIlce.canonicalIl(token) != null) continue;
      if (folded.contains(token)) score += 3;
    }
    return score;
  }

  Iterable<Marker> _provinceMarkers(List<Misafirhane> facilities) {
    final groups = <String, int>{};
    for (final facility in facilities) {
      final city = IlIlce.canonicalIl(facility.il) ?? facility.il.trim();
      if (city.isEmpty) continue;
      groups[city] = (groups[city] ?? 0) + 1;
    }
    final missing = groups.values
        .where((count) => !_countIcons.containsKey(count))
        .toSet();
    if (missing.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadCountIcons(missing));
      });
    }
    final markers = <Marker>[];
    for (final entry in groups.entries) {
      final center = KamiProvinceCenters.centerFor(entry.key);
      final icon = _countIcons[entry.value];
      if (center == null || icon == null) continue;
      final point = LatLng(center.latitude, center.longitude);
      markers.add(
        Marker(
          markerId: MarkerId('province-${entry.key}'),
          position: point,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 2,
          onTap: () => unawaited(
            _openProvince(
              entry.key,
              facilities,
              point,
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Future<void> _openProvince(
    String city,
    List<Misafirhane> facilities,
    LatLng fallback,
  ) async {
    final inCity = [
      for (final facility in facilities)
        if ((IlIlce.canonicalIl(facility.il) ?? facility.il.trim()) == city &&
            facility.latitude != 0 &&
            facility.longitude != 0)
          LatLng(facility.latitude, facility.longitude),
    ];
    setState(() {
      _focusedProvince = city;
      _holdProvinceFocus = true;
    });
    try {
      if (!_map.isCompleted) {
        await _moveCamera(fallback, zoom: 9.4);
        return;
      }
      final controller = await _map.future;
      if (!mounted) return;
      if (inCity.length < 2) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            inCity.isEmpty ? fallback : inCity.first,
            11,
          ),
        );
        return;
      }
      var south = inCity.first.latitude;
      var north = south;
      var west = inCity.first.longitude;
      var east = west;
      for (final point in inCity) {
        south = math.min(south, point.latitude);
        north = math.max(north, point.latitude);
        west = math.min(west, point.longitude);
        east = math.max(east, point.longitude);
      }
      final span = math.max(north - south, east - west);
      final center = LatLng((south + north) / 2, (west + east) / 2);
      if (span < 0.04) {
        await controller.animateCamera(CameraUpdate.newLatLngZoom(center, 12));
        return;
      }
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(south, west),
            northeast: LatLng(north, east),
          ),
          64,
        ),
      );
      if (!mounted) return;
      final zoom = await controller.getZoomLevel();
      if (zoom < 8.4) {
        await controller.animateCamera(CameraUpdate.newLatLngZoom(center, 9.4));
      } else if (zoom > 12.5) {
        await controller.animateCamera(CameraUpdate.newLatLngZoom(center, 12));
      }
    } catch (_) {
      await _moveCamera(fallback, zoom: 9.4);
    } finally {
      if (mounted) setState(() => _holdProvinceFocus = false);
    }
  }

  Future<void> _loadCountIcons(Set<int> counts) async {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    var changed = false;
    for (final count in counts) {
      if (!mounted) return;
      if (_countIcons.containsKey(count)) continue;
      _countIcons[count] = await ProvinceCountIcon.create(
        count,
        pixelRatio: pixelRatio,
      );
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  Marker _browseMarker(Misafirhane facility) {
    final id = facility.stableFacilityId;
    return Marker(
      markerId: MarkerId(id),
      position: LatLng(facility.latitude, facility.longitude),
      icon: (_namesOpen ? _pinRevealed : _pinBrowse) ??
          BitmapDescriptor.defaultMarkerWithHue(
            _namesOpen
                ? BitmapDescriptor.hueAzure
                : BitmapDescriptor.hueOrange,
          ),
      infoWindow: _markerTitle(facility.isim),
      onTap: () => unawaited(_focusFacility(facility, MarkerId(id))),
    );
  }

  InfoWindow _markerTitle(String name) => _namesOpen
      ? InfoWindow(title: _placeTitle(name))
      : InfoWindow.noText;

  Future<void> _refreshMarkerNames() async {
    final open = await _readMarkerNames();
    if (!mounted || open == _namesOpen) return;
    setState(() => _namesOpen = open);
  }

  Future<bool> _readMarkerNames() async {
    if (ProService.instance.hasProAccess) return true;
    final user = PremiumAuthService.instance.currentUser;
    if (user != null &&
        !user.isAnonymous &&
        ServerPremiumAccountBridge.instance.account == null) {
      try {
        await ServerPremiumAccountBridge.instance.refresh();
      } catch (_) {}
    }
    final account = ServerPremiumAccountBridge.instance.account;
    if (account?.plan == null) return false;
    return account!.status == PremiumSubscriptionStatus.active ||
        account.status == PremiumSubscriptionStatus.renewalOff;
  }

  Future<void> _focusFacility(Misafirhane facility, MarkerId id) async {
    final open = await _readMarkerNames();
    if (!mounted) return;
    if (open != _namesOpen) setState(() => _namesOpen = open);
    await _moveCamera(
      LatLng(facility.latitude, facility.longitude),
      zoom: 16.6,
    );
    if (!open || !_map.isCompleted) return;
    final controller = await _map.future;
    if (!mounted) return;
    await controller.showMarkerInfoWindow(id);
  }

  Future<void> _openProAndResume() async {
    final bought = await Navigator.of(
      context,
    ).pushNamed(RotalinkShellRoutes.pro, arguments: true);
    if (bought != true || !mounted) return;
    setState(() {
      _gate = null;
      _gateTitle = null;
      _gateBody = null;
      _lockedCount = 0;
      _namesOpen = true;
    });
    final data = widget.repository.currentState;
    if (data != null) await _search(data, holdCamera: true);
  }

  bool _insideSearchCircle(NearbyGuesthouse item) {
    if (_radius >= 2000) return true;
    final center = _searchedPoint ?? _markedPoint ?? _pin;
    return NearbyGuesthouses.haversineKm(
          center.latitude,
          center.longitude,
          item.facility.latitude,
          item.facility.longitude,
        ) <=
        _radius;
  }

  List<NearbyGuesthouse> _visibleResults(List<Misafirhane> facilities) {
    final saved = _replayIds;
    if (saved != null) {
      final point = _searchedPoint;
      final found = <NearbyGuesthouse>[
        for (final facility in facilities)
          if (saved.contains(facility.stableFacilityId))
            NearbyGuesthouse(
              facility,
              point == null
                  ? 0
                  : NearbyGuesthouses.haversineKm(
                      point.latitude,
                      point.longitude,
                      facility.latitude,
                      facility.longitude,
                    ),
            ),
      ];
      return LocationDiscoveryQuery.present(found, type: _type, sort: _sort);
    }
    final point = _searchedPoint;
    if (!_searched || point == null) return const [];
    final found = NearbyGuesthouses.find(
      facilities,
      point.latitude,
      point.longitude,
      radiusKm: _radius >= 2000 ? double.infinity : _radius,
    );
    return LocationDiscoveryQuery.present(found, type: _type, sort: _sort);
  }

  Future<void> _syncRouteFavorite(Misafirhane facility) async {
    final saved = await _favorites.load();
    if (!mounted ||
        _routeTarget?.facility.stableFacilityId != facility.stableFacilityId) {
      return;
    }
    setState(
      () => _routeFavorite = saved.any(
        (item) => item.sameFavoriteIdentity(facility),
      ),
    );
  }

  Future<void> _toggleRouteFavorite(Misafirhane facility) async {
    final saved = await _favorites.toggle(facility);
    if (!mounted) return;
    setState(
      () => _routeFavorite = saved.any(
        (item) => item.sameFavoriteIdentity(facility),
      ),
    );
  }

  Future<void> _faceNorth() async {
    if (!_map.isCompleted) return;
    final controller = await _map.future;
    if (!mounted) return;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _cameraTarget, zoom: _zoom, bearing: 0, tilt: 0),
      ),
    );
  }

  Future<void> _directions(
    NearbyGuesthouse item, {
    String mode = 'drive',
  }) async {
    final start = _routeOrigin;
    if (start == null) {
      setState(() => _error = 'Önce haritada bir yer işaretleyin.');
      return;
    }
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': '${start.latitude},${start.longitude}',
      'destination': '${item.facility.latitude},${item.facility.longitude}',
      'travelmode': mode == 'walk' ? 'walking' : 'driving',
    });
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      /* Show the same actionable error below. */
    }
    if (mounted) {
      setState(() => _error = 'Google Haritalar yol tarifi açılamadı.');
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<RotaDataState>(
    stream: widget.repository.watchRoot(),
    builder: (context, snapshot) {
      final facilities = snapshot.data?.aramaIcinTumTesisler ?? const [];
      final results = _visibleResults(facilities);
      final mapResults = results.take(_markerCap).toList();
      final circleCenter = _searchedPoint ?? _markedPoint ?? _pin;
      final topInset = MediaQuery.paddingOf(context).top;
      final topPad = topInset + 76;
      return LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          _bodyHeight = height;
          if (!_controlsFitted) _resting = _restingFor(height);
          final resting = _resting;
          final sheetFraction = _routeTarget != null
              ? _routeSheet
              : _gate != null
              ? 0.56
              : _searched
              ? math.max(resting, 0.48)
              : resting;
          final bottomPad = height * sheetFraction;
          final pinY = (topPad + height - bottomPad) / 2;
          return Scaffold(
            backgroundColor: AppColors.canvasOf(context),
            body: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: _turkey,
                    zoom: 5.4,
                  ),
                  padding: EdgeInsets.only(top: topPad, bottom: bottomPad),
                  onMapCreated: (controller) {
                    if (!_map.isCompleted) _map.complete(controller);
                    final pending = _pendingTarget;
                    if (pending != null) {
                      unawaited(_moveCamera(pending, zoom: _pendingZoom));
                    } else {
                      unawaited(_fitTurkey());
                    }
                  },
                  onCameraMove: (position) {
                    _cameraTarget = position.target;
                    _bearing = position.bearing;
                    final zoom = position.zoom;
                    final crossed = (_zoom < 7.2) != (zoom < 7.2);
                    final leftProvince =
                        !_holdProvinceFocus &&
                        _focusedProvince != null &&
                        _zoom >= 6.8 &&
                        zoom < 6.8;
                    _zoom = zoom;
                    if (leftProvince) _focusedProvince = null;
                    if ((crossed || leftProvince) && mounted) {
                      setState(() {});
                    }
                    if (_following ||
                        _searchedPoint == null ||
                        _routeTarget != null) {
                      return;
                    }
                    final drifted =
                        NearbyGuesthouses.haversineKm(
                          _searchedPoint!.latitude,
                          _searchedPoint!.longitude,
                          position.target.latitude,
                          position.target.longitude,
                        ) >
                        1.2;
                    if (drifted != _cameraDrifted && mounted) {
                      setState(() => _cameraDrifted = drifted);
                    }
                  },
                  onCameraIdle: () {
                    if (!mounted || !_following) return;
                    final movedKm = NearbyGuesthouses.haversineKm(
                      _pin.latitude,
                      _pin.longitude,
                      _cameraTarget.latitude,
                      _cameraTarget.longitude,
                    );
                    if (movedKm < 0.02) return;
                    setState(() {
                      _pin = _cameraTarget;
                      if (movedKm > 0.8) {
                        _placeName = 'Haritada seçilen nokta';
                      }
                    });
                  },
                  onTap: (point) {
                    FocusScope.of(context).unfocus();
                    if (_following) {
                      _aim(point, name: 'Haritada seçilen nokta');
                    }
                  },
                  onLongPress: (point) {
                    FocusScope.of(context).unfocus();
                    _aim(point, name: 'Haritada seçilen nokta');
                  },
                  markers: {
                    if (_markedPoint != null &&
                        (_routeTarget != null || _searched || _zoom >= 7.2))
                      Marker(
                        markerId: const MarkerId('search-place'),
                        position: _markedPoint!,
                        icon:
                            _originPin ??
                            _pinStart ??
                            BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueRed,
                            ),
                        zIndexInt: 5,
                        infoWindow: InfoWindow(
                          title: _placeTitle(_placeName),
                          snippet: _routeTarget != null ? 'Başlangıç' : null,
                        ),
                      ),
                    if (_routeTarget != null)
                      Marker(
                        markerId: const MarkerId('route-destination'),
                        position: LatLng(
                          _routeTarget!.facility.latitude,
                          _routeTarget!.facility.longitude,
                        ),
                        icon:
                            _pinDestination ??
                            BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueGreen,
                            ),
                        zIndexInt: 6,
                        infoWindow: _namesOpen
                            ? InfoWindow(
                                title: _placeTitle(
                                  _routeTarget!.facility.isim,
                                ),
                                snippet: 'Varış',
                              )
                            : InfoWindow.noText,
                        onTap: () => unawaited(
                          _focusFacility(
                            _routeTarget!.facility,
                            const MarkerId('route-destination'),
                          ),
                        ),
                      ),
                    if (!_searched &&
                        _routeTarget == null &&
                        _zoom < 7.2 &&
                        _focusedProvince == null)
                      ..._provinceMarkers(facilities),
                    if (!_searched &&
                        _routeTarget == null &&
                        _focusedProvince != null)
                      for (final facility in facilities)
                        if ((IlIlce.canonicalIl(facility.il) ??
                                facility.il.trim()) ==
                            _focusedProvince)
                          _browseMarker(facility),
                    if (_searched && _routeTarget == null)
                      for (final item in mapResults)
                        if (_replayIds != null || _insideSearchCircle(item))
                          Marker(
                            markerId: MarkerId(
                              'found-${item.facility.stableFacilityId}',
                            ),
                            position: LatLng(
                              item.facility.latitude,
                              item.facility.longitude,
                            ),
                            icon:
                                _pinFacility ??
                                BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueBlue,
                                ),
                            zIndexInt: 3,
                            infoWindow: _markerTitle(item.facility.isim),
                            onTap: () => unawaited(
                              _focusFacility(
                                item.facility,
                                MarkerId(
                                  'found-${item.facility.stableFacilityId}',
                                ),
                              ),
                            ),
                          ),
                  },
                  circles: {
                    if (_radius < 2000 &&
                        (_replayIds == null
                            ? (_searched || _routeTarget == null)
                            : _replayCanRefresh))
                      Circle(
                        circleId: const CircleId('search-radius'),
                        center: circleCenter,
                        radius: _radius * 1000,
                        fillColor: AppColors.primary.withValues(alpha: 0.12),
                        strokeColor: AppColors.primary.withValues(alpha: 0.85),
                        strokeWidth: 2,
                      ),
                  },
                  mapType: _satellite ? MapType.hybrid : MapType.normal,
                  buildingsEnabled: true,
                  polylines: {
                    if (_routeMode == 'drive' && _driveRoute != null)
                      ..._routeLine(
                        'drive-route',
                        _driveRoute!,
                        _driveLine,
                        7,
                        3,
                      ),
                    if (_routeMode == 'walk' && _walkRoute != null)
                      ..._routeLine(
                        'walk-route',
                        _walkRoute!,
                        _walkLine,
                        7,
                        3,
                      ),
                  },
                  myLocationEnabled: _myLocationOn,
                  myLocationButtonEnabled: false,
                  compassEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
                if (_following && _myLocationOn)
                  Positioned(
                    left: constraints.maxWidth / 2 - 20,
                    top: pinY - 40,
                    child: const IgnorePointer(
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        color: AppColors.mapLocationPin,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  top: topInset + 20,
                  left: 12,
                  right: 12,
                  child: _searchCard(context),
                ),
                if (_suggestionsOpen)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: topInset + 88,
                    bottom:
                        math.max(
                          MediaQuery.viewInsetsOf(context).bottom,
                          bottomPad,
                        ) +
                        12,
                    child: Align(
                      alignment: Alignment.center,
                      child: _suggestionPanel(context),
                    ),
                  ),
                if (_error != null && !_suggestionsOpen)
                  Positioned(
                    top: topInset + 84,
                    left: 16,
                    right: 16,
                    child: _mapNote(context, _error!),
                  ),
                Positioned(
                  right: 12,
                  bottom: bottomPad + 16,
                  child: Column(
                    children: [
                      _mapButton(
                        tooltip: _satellite ? 'Harita' : 'Uydu',
                        icon: _satellite
                            ? Icons.map_outlined
                            : Icons.layers_outlined,
                        onPressed: () =>
                            setState(() => _satellite = !_satellite),
                      ),
                      _mapButton(
                        tooltip: 'Bulunduğum konuma git',
                        icon: Icons.my_location,
                        onPressed: _locating ? null : _goToMyLocation,
                        child: _locating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF008C95),
                                ),
                              )
                            : null,
                      ),
                      _mapButton(
                        tooltip: 'Kuzeye çevir',
                        icon: Icons.explore_outlined,
                        onPressed: () => unawaited(_faceNorth()),
                        child: Transform.rotate(
                          angle: -_bearing * math.pi / 180,
                          child: const Icon(
                            Icons.navigation_rounded,
                            color: Color(0xFF008C95),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_cameraDrifted &&
                    !_busy &&
                    _routeTarget == null &&
                    _gate == null &&
                    snapshot.hasData)
                  Positioned(
                    left: 16,
                    right: 72,
                    bottom: bottomPad + 14,
                    child: Center(
                      child: _areaChip(() => _search(snapshot.data!)),
                    ),
                  ),
                DraggableScrollableSheet(
                  controller: _sheet,
                  initialChildSize: _routeTarget != null
                      ? _routeSheet.clamp(0.28, 0.55)
                      : resting,
                  minChildSize: _routeTarget != null ? 0.22 : 0.16,
                  maxChildSize: _routeTarget != null ? 0.62 : 0.88,
                  snap: _routeTarget != null,
                  snapSizes: _routeTarget != null
                      ? const [0.22, 0.46, 0.58]
                      : null,
                  builder: (context, scroll) => _sheetBody(
                    context,
                    scroll,
                    snapshot,
                    facilities,
                    results,
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _mapButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    Widget? child,
  }) {
    final dark = AppColors.isDark(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: dark ? AppColors.surfaceOf(context) : Colors.white,
        elevation: 3,
        shadowColor: Colors.black26,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: child ?? Icon(icon, color: const Color(0xFF008C95)),
        ),
      ),
    );
  }

  Widget _searchCard(BuildContext context) {
    return CustomSearchBar(
      controller: _query,
      focusNode: _placeFocus,
      hintText: 'İl, ilçe, adres veya tesis',
      onSubmitted: _searchText,
      onHistoryPressed: _openSearchHistory,
      onClearPressed: _closeSuggestions,
      ignoreKeyboardInset: true,
      emphasized: true,
      compactHome: true,
    );
  }

  Widget _suggestionPanel(BuildContext context) {
    final places = <PlaceSuggestion>[
      ..._localSuggestions,
      ..._photonSuggestions.where((item) {
        final title = KamiCityResolver.normalize(item.title);
        return _localSuggestions.every(
          (local) => KamiCityResolver.normalize(local.title) != title,
        );
      }),
    ];
    return Material(
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      color: AppColors.surfaceOf(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            if (_history.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                child: Text(
                  'Son aramalar',
                  style: TextStyle(
                    color: AppColors.textMutedOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final item in _history)
                _suggestionTile(context, item, recent: true),
            ],
            if (places.isNotEmpty || _suggesting)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                child: Text(
                  'Öneriler',
                  style: TextStyle(
                    color: AppColors.textMutedOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            for (final item in places) _suggestionTile(context, item),
            if (_suggesting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionTile(
    BuildContext context,
    PlaceSuggestion item, {
    bool recent = false,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(
        recent ? Icons.history : Icons.place_outlined,
        color: AppColors.primary,
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        item.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => unawaited(_chooseSuggestion(item)),
    );
  }

  Widget _mapNote(BuildContext context, String text) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      color: AppColors.surfaceOf(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textStrongOf(context),
            fontSize: 13,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _areaChip(VoidCallback onPressed) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: AppColors.surfaceOf(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.travel_explore, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Bu bölgede ara',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetBody(
    BuildContext context,
    ScrollController scroll,
    AsyncSnapshot<RotaDataState> snapshot,
    List<Misafirhane> facilities,
    List<NearbyGuesthouse> results,
  ) {
    final target = _routeTarget;
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitRouteCard();
      });
      return Container(
        decoration: BoxDecoration(
          color: AppColors.isDark(context)
              ? const Color(0xFF102428)
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
        ),
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.zero,
          children: [
            Padding(
              key: _routeCardKey,
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderOf(context),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FacilityRoutePanel(
                    name: target.facility.isim,
                    detail: _ilIlce(target.facility),
                    birdKm: target.km,
                    mode: _routeMode,
                    drive: _driveRoute,
                    walk: _walkRoute,
                    driveBusy: _loadingModes.contains('drive'),
                    walkBusy: _loadingModes.contains('walk'),
                    note: _routeNote,
                    isFavorite: _routeFavorite,
                    onFavorite: () =>
                        unawaited(_toggleRouteFavorite(target.facility)),
                    onShare: () {
                      final phone = target.facility.telefonNumaralari.join(
                        ' / ',
                      );
                      unawaited(
                        Share.share(
                          StoreLinks.shareMessage(target.facility.isim, [
                            _ilIlce(target.facility),
                            if (phone.isNotEmpty) 'Telefon: $phone',
                          ]),
                        ),
                      );
                    },
                    onCall: target.facility.telefonNumaralari.isEmpty
                        ? null
                        : () => FacilityPhoneDialer.open(
                            context,
                            target.facility,
                          ),
              onMode: (mode) => unawaited(_selectRouteMode(mode)),
              onClose: _closeRoute,
              onOpenMaps: () => _directions(target, mode: _routeMode),
                    onAbout: () => _openFacilityCard(target.facility),
                    onPhotos: () => openMapSearch(
                      context,
                      target.facility.il,
                      target.facility.isim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (_gate != null) {
      return _sheetFrame(
        context,
        scroll,
        children: [
          _sheetHandle(context),
          if (_lockedCount > 0) ...[
            Text(
              'Bu çevrede $_lockedCount tesis var',
              style: TextStyle(
                color: AppColors.textStrongOf(context),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const _LockedPlaceTeaser(),
            const SizedBox(height: 8),
          ],
          _NearbyLimitCard(
            title: _gateTitle,
            body: _gateBody,
            onPremium: () => unawaited(_openProAndResume()),
            onStay: () {
              setState(() {
                _gate = null;
                _gateTitle = null;
                _gateBody = null;
                _lockedCount = 0;
              });
              unawaited(_openSheet(_resting));
            },
          ),
        ],
      );
    }
    final readyToSearch = facilities.isNotEmpty && snapshot.hasData;
    if (!_controlsFitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitControlsToBottom();
      });
    }
    return _sheetFrame(
      context,
      scroll,
      bottom: 6,
      children: [
        Column(
          key: _controlsKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHandle(context),
            const SizedBox(height: 8),
            _radiusChoices(context),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy || !readyToSearch
                  ? null
                  : () {
                      final typed = _query.text.trim();
                      if (typed.length >= 2) {
                        unawaited(_searchText());
                      } else {
                        unawaited(_search(snapshot.data!));
                      }
                    },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _cameraDrifted && !_following
                          ? 'Bu bölgede ara'
                          : LocationDiscoveryQuery.actionLabel(_radius),
                    ),
            ),
            if (snapshot.connectionState == ConnectionState.waiting &&
                facilities.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (snapshot.hasError || (snapshot.hasData && facilities.isEmpty))
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Tesis verisi yüklenemedi.'),
              ),
            const SizedBox(height: 8),
            _typeChoices(context),
          ],
        ),
        if (_searched) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  results.isEmpty
                      ? '$_placeName · tesis yok'
                      : '$_placeName · ${results.length} tesis',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textStrongOf(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (results.isNotEmpty)
                PopupMenuButton<String>(
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (context) => [
                    for (final sort in LocationDiscoveryQuery.sorts)
                      PopupMenuItem(value: sort, child: Text(sort)),
                  ],
                  child: Text(
                    _sort,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (_replayIds != null && _replayCanRefresh)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy || !readyToSearch
                    ? null
                    : () => _search(snapshot.data!, forceClaim: true),
                child: const Text('Sonuçları yenile'),
              ),
            ),
          if (_replayIds != null && !_replayCanRefresh)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Başlangıç noktasının saklama süresi doldu.',
                style: TextStyle(color: AppColors.textMutedOf(context)),
              ),
            ),
        ],
        if (_searched && _radiusNote != null) ...[
          const SizedBox(height: 8),
          Text(
            _radiusNote!,
            style: TextStyle(
              color: AppColors.textMutedOf(context),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
        if (_searched && _quotaNote != null) ...[
          const SizedBox(height: 8),
          Text(
            _quotaNote!,
            style: TextStyle(
              color: AppColors.textMutedOf(context),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
        if (_searched && results.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Bu filtrede tesis yok.',
              style: TextStyle(color: AppColors.textMutedOf(context)),
            ),
          ),
        for (final item in results) _resultCard(context, item),
      ],
    );
  }

  Widget _sheetFrame(
    BuildContext context,
    ScrollController scroll, {
    required List<Widget> children,
    double bottom = 12,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16)],
      ),
      child: ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          bottom + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: children,
      ),
    );
  }

  Widget _sheetHandle(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: AppColors.borderOf(context),
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );
  }

  Widget _radiusChoices(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: LocationDiscoveryQuery.radiiKm.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final radius = LocationDiscoveryQuery.radiiKm[index];
          return _filterChip(
            context,
            label: LocationDiscoveryQuery.radiusLabel(radius),
            selected: _radius == radius,
            onSelected: () => _selectRadius(radius),
          );
        },
      ),
    );
  }

  Widget _typeChoices(BuildContext context) {
    final types = LocationDiscoveryQuery.facilityTypes;
    return Row(
      children: [
        for (var i = 0; i < types.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _typeChip(
              context,
              label: types[i],
              selected: _type == types[i],
              onSelected: () {
                setState(() => _type = types[i]);
                unawaited(
                  _frameSearchCircle(
                    _searchedPoint ?? _markedPoint ?? _pin,
                    _radius,
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _typeChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final foreground = selected
        ? Colors.white
        : AppColors.textStrongOf(context);
    return Material(
      color: selected ? AppColors.primary : AppColors.fieldFillOf(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onSelected,
        child: Container(
          height: 32,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderOf(context),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.fieldFillOf(context),
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.borderOf(context),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textStrongOf(context),
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      onSelected: (_) => onSelected(),
    );
  }

  Widget _resultCard(BuildContext context, NearbyGuesthouse item) {
    final facility = item.facility;
    final selected = _selectedId == facility.stableFacilityId;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected
            ? AppColors.primarySoftOf(context)
            : AppColors.fieldFillOf(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => unawaited(_openRoute(item)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        facility.isim,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textStrongOf(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _ilIlce(facility),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textMutedOf(context),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  LocationDiscoveryQuery.kilometers(item.km),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMutedOf(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _NearbyGate { quota }

/// İsim yazmadan, kilitli bir liste hissi verir.
class _LockedPlaceTeaser extends StatelessWidget {
  const _LockedPlaceTeaser();

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Column(
        children: [
          for (final width in const [0.86, 0.62, 0.74])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3CA6A).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 16,
                      color: Color(0xFF8A5A10),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: width,
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF9AABB4), Color(0xFFE7EEF2)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NearbyLimitCard extends StatelessWidget {
  const _NearbyLimitCard({
    required this.onPremium,
    required this.onStay,
    this.title,
    this.body,
  });

  final VoidCallback onPremium;
  final VoidCallback onStay;
  final String? title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final headline = title ?? 'Keşfetmeye Devam Edin! 📍';
    final lines = body != null
        ? [body!]
        : const [
            'Bu ayki ücretsiz yakın arama hakkınızı kullandınız.',
            'Rotalink Pro ile daha fazla tesis keşfedin, size en yakın konaklama seçeneklerini kolayca bulun.',
          ];
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0C5C66),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x550A4E5C),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('👑', style: TextStyle(fontSize: 16)),
                SizedBox(width: 6),
                Text(
                  'ROTALINK PRO',
                  style: TextStyle(
                    color: Color(0xFFE6C15A),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              headline,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            for (final line in lines) ...[
              Text(
                line,
                style: const TextStyle(
                  color: Color(0xFFF4FBFC),
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: onPremium,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE8B84A),
                foregroundColor: const Color(0xFF1C1408),
                minimumSize: const Size.fromHeight(48),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text('Pro Avantajlarını Keşfet'),
            ),
            Center(
              child: TextButton(
                onPressed: onStay,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD7EEF1),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Haritada Kal'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
