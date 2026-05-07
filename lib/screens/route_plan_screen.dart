import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/firebase_rota_repository.dart';
import '../data/saved_routes_repository.dart';
import '../l10n/app_strings.dart';
import '../models/route_plan_outcome.dart';
import '../route/route_enricher.dart';
import '../route/route_planning_notifier.dart';
import '../services/osrm_route_service.dart';
import '../theme/app_colors.dart';
import '../utils/geo_helpers.dart';
import '../utils/main_map_search.dart';
import '../utils/maps_launch.dart';
import '../utils/route_facility_lookup.dart';
import '../utils/safe_map_coordinates.dart';
import '../utils/search_normalize.dart';
import '../widgets/il_search_sheet.dart';
import '../widgets/route_plan_preview_sheet.dart';

/// Kotlin [MainActivity.showRoutePlanningFlow] — OSRM zenginleştirme ana haritada.
/// Durak state’i [RoutePlanningNotifier] üzerinden yönetilir.
class RoutePlanScreen extends StatelessWidget {
  RoutePlanScreen({
    super.key,
    required this.repository,
    SavedRoutesRepository? savedRoutesRepository,
  }) : savedRoutesRepository = savedRoutesRepository ?? SavedRoutesRepository();

  final FirebaseRotaRepository repository;
  final SavedRoutesRepository savedRoutesRepository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          RoutePlanningNotifier(savedRoutesRepository: savedRoutesRepository),
      child: _RoutePlanScaffold(repository: repository),
    );
  }
}

class _RoutePlanScaffold extends StatefulWidget {
  const _RoutePlanScaffold({required this.repository});

  final FirebaseRotaRepository repository;

  @override
  State<_RoutePlanScaffold> createState() => _RoutePlanScaffoldState();
}

class _RoutePlanScaffoldState extends State<_RoutePlanScaffold> {
  static const _cardRadius = 16.0;
  static final _cardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.07),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  final MapController _planMapController = MapController();
  RoutePlanningNotifier? _notifierBinding;
  Timer? _osrmDebounce;
  RotaDataState? _lastRotaData;

  List<LatLng> _planWaypoints = const [];
  List<LatLng> _planPolyline = const [];
  List<Marker> _planMarkers = const [];
  double? _planDistanceM;
  double? _planDurationS;
  bool _planOsrmLoading = false;
  bool _initialOsrmPrimed = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final n = context.read<RoutePlanningNotifier>();
    if (_notifierBinding == null) {
      _notifierBinding = n;
      n.addListener(_onPlannerNotifierChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final d = _lastRotaData;
        if (mounted && d != null && d.errorMessage == null) {
          _scheduleOsrmPreview(d);
        }
      });
    }
  }

  @override
  void dispose() {
    _osrmDebounce?.cancel();
    _notifierBinding?.removeListener(_onPlannerNotifierChanged);
    super.dispose();
  }

  void _onPlannerNotifierChanged() {
    final data = _lastRotaData;
    if (data != null) _scheduleOsrmPreview(data);
  }

  void _scheduleOsrmPreview(RotaDataState data) {
    _osrmDebounce?.cancel();
    _osrmDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_runOsrmPreview(data));
    });
  }

  Future<void> _runOsrmPreview(RotaDataState data) async {
    if (!mounted) return;
    final n = context.read<RoutePlanningNotifier>();
    final preview = n.previewStopsForMap(data);
    if (preview == null) {
      if (!mounted) return;
      setState(() {
        _planWaypoints = const [];
        _planPolyline = const [];
        _planMarkers = const [];
        _planDistanceM = null;
        _planDurationS = null;
        _planOsrmLoading = false;
      });
      try {
        _planMapController.move(kTurkeyMapFallbackCenter, kTurkeyMapFallbackZoom);
      } catch (_) {}
      return;
    }

    final w = waypointsForRouteStops(data, preview);
    if (w.length < 2) {
      if (!mounted) return;
      setState(() {
        _planWaypoints = w;
        _planPolyline = const [];
        _planMarkers = _numberedCityMarkers(w);
        _planDistanceM = null;
        _planDurationS = null;
        _planOsrmLoading = false;
      });
      _fitPlanMap(w);
      return;
    }

    if (!mounted) return;
    setState(() => _planOsrmLoading = true);

    final segments = await OsrmRouteService.fetchSegments(w);
    if (!mounted) return;

    var totalM = 0.0;
    var totalS = 0.0;
    final merged = <LatLng>[];
    for (final s in segments) {
      totalM += s.distanceM;
      totalS += s.durationS;
      for (final p in s.points) {
        if (!isValidWgs84LatLng(p.latitude, p.longitude)) continue;
        if (merged.isEmpty || !_sameLatLng(merged.last, p)) merged.add(p);
      }
    }
    final hasTotals = segments.isNotEmpty && totalM > 0 && totalS > 0;

    final polyline =
        merged.length >= 2 ? merged : OsrmRouteService.straightFallback(w);
    setState(() {
      _planWaypoints = w;
      _planPolyline = polyline;
      _planMarkers = _numberedCityMarkers(w);
      _planDistanceM = hasTotals ? totalM : null;
      _planDurationS = hasTotals ? totalS : null;
      _planOsrmLoading = false;
    });
    _fitPlanMap(polyline.length >= 2 ? polyline : w);
  }

  bool _sameLatLng(LatLng a, LatLng b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;

  List<Marker> _numberedCityMarkers(List<LatLng> w) {
    return [
      for (var i = 0; i < w.length; i++)
        Marker(
          point: latLngOrFallback(w[i].latitude, w[i].longitude),
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary,
            child: Text(
              '${i + 1}',
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
    ];
  }

  void _fitPlanMap(List<LatLng> pts) {
    final valid = onlyValidLatLngs(pts);
    if (valid.length < 2) {
      try {
        _planMapController.move(
          valid.isEmpty ? kTurkeyMapFallbackCenter : valid.first,
          valid.isEmpty ? kTurkeyMapFallbackZoom : clampZoom(8),
        );
      } catch (_) {
        try {
          _planMapController.move(kTurkeyMapFallbackCenter, kTurkeyMapFallbackZoom);
        } catch (_) {}
      }
      return;
    }
    try {
      _planMapController.fitCamera(
        CameraFit.coordinates(
          coordinates: valid,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        ),
      );
    } catch (_) {
      try {
        _planMapController.move(valid.first, clampZoom(8));
      } catch (_) {
        try {
          _planMapController.move(kTurkeyMapFallbackCenter, kTurkeyMapFallbackZoom);
        } catch (_) {}
      }
    }
  }

  Future<void> _shareDraftRoute(RoutePlanningNotifier n, RotaDataState data) async {
    final preview = n.previewStopsForMap(data);
    if (preview == null) {
      _snack(AppStrings.routePlanPreviewNeedTwoCities);
      return;
    }
    final chain = preview.map((s) => s.city).join(' → ');
    final buf = StringBuffer()
      ..writeln('Rotalink — rotam')
      ..writeln(chain);
    if (_planDistanceM != null && _planDurationS != null && _planDistanceM! > 0 && _planDurationS! > 0) {
      buf
        ..writeln()
        ..writeln('Mesafe: ${formatRouteDistanceMeters(_planDistanceM!)}')
        ..writeln('Süre: ${formatRouteDurationSeconds(_planDurationS!)}');
    }
    buf
      ..writeln()
      ..writeln('https://play.google.com/store/apps/details?id=com.serdarza.rotalink');
    await Share.share(buf.toString(), subject: 'Rotalink rotası');
  }

  Future<void> _calculate(RotaDataState data) async {
    final n = context.read<RoutePlanningNotifier>();
    final raw = n.collectStops(data, _snack);
    if (raw == null) return;
    n.setCalculating(true);
    try {
      final enriched = RouteEnricher.enrich(raw);
      final waypoints = waypointsForRouteStops(data, enriched);
      if (waypoints.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(AppStrings.routePlanInsufficientLocations),
            ),
          );
        }
        return;
      }
      final segments = await OsrmRouteService.fetchSegments(waypoints);
      if (!mounted) return;

      var totalDistanceM = 0.0;
      var totalDurationS = 0.0;
      for (final s in segments) {
        totalDistanceM += s.distanceM;
        totalDurationS += s.durationS;
      }
      final hasOsrmTotals =
          segments.isNotEmpty && totalDistanceM > 0 && totalDurationS > 0;

      n.setCalculating(false);

      final go = await showRoutePlanPreviewSheet(
        context: context,
        stops: enriched,
        distanceM: hasOsrmTotals ? totalDistanceM : null,
        durationS: hasOsrmTotals ? totalDurationS : null,
        navigationWaypoints: waypoints,
        navigationPlaceQueries: placeQueriesForRouteStops(data, enriched),
      );
      if (!mounted || go != true) return;

      Navigator.of(context).pop<RoutePlanOutcome>(
        RoutePlanOutcome(
          stops: enriched,
          segments: segments.isNotEmpty ? segments : null,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rota hesaplanamadı. Ağ bağlantınızı kontrol edin.'),
          ),
        );
      }
    } finally {
      if (mounted) context.read<RoutePlanningNotifier>().setCalculating(false);
    }
  }

  Future<void> _loadSaved(SavedRouteRecord record, RotaDataState data) async {
    final raw = record.stops.map((e) => e.toRouteStop()).toList();
    final enriched = RouteEnricher.enrich(raw);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop<RoutePlanOutcome>(RoutePlanOutcome(stops: enriched, segments: null));
  }

  /// Önce üstte gerçekten başka route varsa (dialog / modal sheet) onu kapatır.
  /// `maybePop` her zaman çağrılmaz: aksi halde bazı sürümlerde üst rota “işlendi” dönüp
  /// sayfa kapanmıyor (AppBar geri ve sistem geri çalışmıyor gibi görünüyor).
  Future<void> _onRoutePlanWillPop() async {
    if (!mounted) return;
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      if (await nav.maybePop()) {
        return;
      }
    }
    if (!mounted) return;
    final n = context.read<RoutePlanningNotifier>();
    if (_tryStepSuggestionsTabBack(n)) {
      return;
    }
    if (!mounted) return;
    nav.pop();
  }

  bool _tryStepSuggestionsTabBack(RoutePlanningNotifier n) {
    for (var i = n.intermediate.length - 1; i >= 0; i--) {
      final row = n.intermediate[i];
      if (row.city.text.trim().isEmpty) continue;
      final t = row.suggestionsTabIndex;
      if (t > 0) {
        n.setStopSuggestionsTab(i, t - 1);
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_onRoutePlanWillPop());
      },
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () async {
            await _onRoutePlanWillPop();
          },
        ),
        title: const Text(AppStrings.routePlanTitle),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 0,
        actions: [
          StreamBuilder<RotaDataState>(
            stream: widget.repository.watchRoot(),
            builder: (context, snap) {
              final data = snap.data;
              final n = context.watch<RoutePlanningNotifier>();
              return IconButton(
                icon: const Icon(Icons.bookmark_add_outlined),
                tooltip: AppStrings.routePlanSaveTitle,
                onPressed: data == null || n.calculating
                    ? null
                    : () async {
                        final raw = n.collectStops(data, _snack);
                        if (raw == null) return;
                        await n.promptSaveRoute(context, raw, _snack);
                      },
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, Color(0xFFE3F4F6)],
            stops: [0.0, 0.22],
          ),
        ),
        child: StreamBuilder<RotaDataState>(
          stream: widget.repository.watchRoot(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            final data = snapshot.data;
            if (data == null ||
                (!snapshot.hasData &&
                    snapshot.connectionState == ConnectionState.waiting)) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.white),
              );
            }
            if (data.errorMessage != null) {
              return Center(child: Text(data.errorMessage!));
            }

            _lastRotaData = data;
            if (!_initialOsrmPrimed) {
              _initialOsrmPrimed = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _scheduleOsrmPreview(data);
              });
            }

            return Consumer<RoutePlanningNotifier>(
              builder: (context, n, _) {
                return FutureBuilder<List<SavedRouteRecord>>(
                  future: n.savedFuture,
                  builder: (context, savedSnap) {
                    final saved = savedSnap.data ?? const [];
                    final cities = n.citySuggestions(data);
                    final ime = MediaQuery.viewInsetsOf(context).bottom;
                    final bottomInset = MediaQuery.paddingOf(context).bottom;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + ime),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (saved.isNotEmpty) ...[
                                  Text(
                                    AppStrings.routePlanSavedTitle,
                                    style: Theme.of(context).textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.white,
                                        ),
                                  ),
                                  const SizedBox(height: 10),
                                  ...saved.map((r) => _savedRouteCard(r, data, n)),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: () => n.resetNewRouteForm(),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.white,
                                    ),
                                    child: const Text(AppStrings.routePlanNew),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                _timelineStartCard(context, cities, n),
                                const SizedBox(height: 20),
                                Text(
                                  AppStrings.routePlanStopsTitle,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.white,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  AppStrings.routePlanCuratorHint,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: AppColors.white.withValues(alpha: 0.88),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ReorderableListView(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  onReorder: n.reorderStops,
                                  proxyDecorator: (child, index, animation) {
                                    return AnimatedBuilder(
                                      animation: animation,
                                      builder: (context, _) {
                                        final t = Curves.easeOut.transform(
                                          animation.value,
                                        );
                                        return Material(
                                          elevation: 10 * t,
                                          shadowColor: Colors.black26,
                                          borderRadius: BorderRadius.circular(18),
                                          clipBehavior: Clip.antiAlias,
                                          child: child,
                                        );
                                      },
                                    );
                                  },
                                  children: [
                                    for (var i = 0; i < n.intermediate.length; i++)
                                      _buildReorderableStop(context, cities, n, i, data),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: n.calculating ? null : n.addStop,
                                  icon: const Icon(Icons.add_circle_outline_rounded),
                                  label: const Text(AppStrings.routePlanAddStop),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.92,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  AppStrings.routePlanPreviewMapTitle,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.white,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: SizedBox(
                                    height: 220,
                                    child: FlutterMap(
                                      mapController: _planMapController,
                                      options: MapOptions(
                                        initialCenter: kTurkeyMapFallbackCenter,
                                        initialZoom: kTurkeyMapFallbackZoom,
                                      ),
                                      children: [
                                        TileLayer(
                                          urlTemplate:
                                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                          userAgentPackageName: 'com.serdarza.rotalink',
                                        ),
                                        if (_planPolyline.length >= 2)
                                          PolylineLayer(
                                            polylines: [
                                              Polyline<Object>(
                                                points: _planPolyline,
                                                strokeWidth: 4,
                                                color: AppColors.primary,
                                              ),
                                            ],
                                          ),
                                        MarkerLayer(markers: _planMarkers),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_planOsrmLoading)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: LinearProgressIndicator(
                                      minHeight: 3,
                                      color: AppColors.white,
                                      backgroundColor: Color(0x33FFFFFF),
                                    ),
                                  ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                        _stickyRouteSummaryBar(
                          context,
                          data,
                          n,
                          bottomInset: bottomInset,
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    ),
    );
  }

  Future<void> _pickMisafirhaneForStop(
    BuildContext context,
    RotaDataState data,
    RoutePlanningNotifier n,
    int stopIndex,
  ) async {
    final il = n.intermediate[stopIndex].city.text.trim();
    if (il.isEmpty) {
      _snack(AppStrings.routePlanPickNeedCity);
      return;
    }
    final kaynak = MainMapSearch.tesisKaynagiArama(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    var list = kaynak.where((m) => m.il.trim().toLowerCase() == il.toLowerCase()).toList()
      ..sort((a, b) => a.isim.compareTo(b.isim));
    if (list.isEmpty) {
      _snack(AppStrings.routePlanNoDataForIl);
      return;
    }
    final search = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: StatefulBuilder(
            builder: (ctx, setSt) {
              final q = normalizeForSearch(search.text);
              final filtered = q.isEmpty
                  ? list
                  : list
                      .where((m) => normalizeForSearch('${m.isim} ${m.adres}').contains(q))
                      .toList();
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.58,
                minChildSize: 0.38,
                maxChildSize: 0.94,
                builder: (_, scroll) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: TextField(
                          controller: search,
                          onChanged: (_) => setSt(() {}),
                          decoration: InputDecoration(
                            hintText: AppStrings.fabMisafirhaneList,
                            prefixIcon: const Icon(Icons.hotel_rounded, color: AppColors.primary),
                            filled: true,
                            fillColor: const Color(0xFFF5F9FA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  AppStrings.routePlanNoDataForIl,
                                  style: TextStyle(color: AppColors.campaignSummaryMuted),
                                ),
                              )
                            : ListView.builder(
                                controller: scroll,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: filtered.length,
                                itemBuilder: (_, idx) {
                                  final m = filtered[idx];
                                  return ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    title: Text(
                                      m.isim,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(m.adres, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    onTap: () {
                                      n.addStopKonak(stopIndex, m);
                                      Navigator.pop(ctx);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
    search.dispose();
  }

  Future<void> _pickGeziYemekForStop(
    BuildContext context,
    RotaDataState data,
    RoutePlanningNotifier n,
    int stopIndex, {
    required bool yemek,
  }) async {
    final il = n.intermediate[stopIndex].city.text.trim();
    if (il.isEmpty) {
      _snack(AppStrings.routePlanPickNeedCity);
      return;
    }
    final raw = yemek ? data.yemek : data.gezi;
    var list = raw.where((g) => g.il.trim().toLowerCase() == il.toLowerCase()).toList()
      ..sort((a, b) => a.isim.compareTo(b.isim));
    if (list.isEmpty) {
      _snack(AppStrings.routePlanNoDataForIl);
      return;
    }
    final search = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: StatefulBuilder(
            builder: (ctx, setSt) {
              final q = normalizeForSearch(search.text);
              final filtered = q.isEmpty
                  ? list
                  : list
                      .where((g) => normalizeForSearch('${g.isim} ${g.adres}').contains(q))
                      .toList();
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.58,
                minChildSize: 0.38,
                maxChildSize: 0.94,
                builder: (_, scroll) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: TextField(
                          controller: search,
                          onChanged: (_) => setSt(() {}),
                          decoration: InputDecoration(
                            hintText: yemek ? AppStrings.routePlanYemek : AppStrings.routePlanGezi,
                            prefixIcon: Icon(
                              yemek ? Icons.restaurant_rounded : Icons.park_rounded,
                              color: AppColors.primary,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF5F9FA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  AppStrings.routePlanNoDataForIl,
                                  style: TextStyle(color: AppColors.campaignSummaryMuted),
                                ),
                              )
                            : ListView.builder(
                                controller: scroll,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: filtered.length,
                                itemBuilder: (_, idx) {
                                  final g = filtered[idx];
                                  return ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    title: Text(
                                      g.isim,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      g.adres,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () {
                                      if (yemek) {
                                        n.addStopYemek(stopIndex, g);
                                      } else {
                                        n.addStopGezi(stopIndex, g);
                                      }
                                      Navigator.pop(ctx);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
    search.dispose();
  }

  Future<void> _pickGeziForStop(
    BuildContext context,
    RotaDataState data,
    RoutePlanningNotifier n,
    int stopIndex,
  ) =>
      _pickGeziYemekForStop(context, data, n, stopIndex, yemek: false);

  Future<void> _pickYemekForStop(
    BuildContext context,
    RotaDataState data,
    RoutePlanningNotifier n,
    int stopIndex,
  ) =>
      _pickGeziYemekForStop(context, data, n, stopIndex, yemek: true);

  Widget _savedRouteCard(
    SavedRouteRecord r,
    RotaDataState data,
    RoutePlanningNotifier n,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white.withValues(alpha: 0.95),
        elevation: 0,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(_cardRadius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_cardRadius),
            boxShadow: _cardShadow,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            title: Text(
              r.name,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              r.stops.map((s) => s.city).join(' → '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.campaignSummaryMuted,
                fontSize: 13,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.campaignSummaryMuted,
              ),
              tooltip: AppStrings.routePlanDelete,
              onPressed: () => n.deleteSaved(r.name),
            ),
            onTap: () => _loadSaved(r, data),
          ),
        ),
      ),
    );
  }

  Widget _timelineStartCard(
    BuildContext context,
    List<String> cities,
    RoutePlanningNotifier n,
  ) {
    return _surfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _timelineDot(
            icon: Icons.trip_origin_rounded,
            color: const Color(0xFF2E7D32),
            showLineBelow: n.intermediate.isNotEmpty,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.routePlanTimelineStart,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary.withValues(alpha: 0.85),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                _IlPickerField(
                  controller: n.startCity,
                  cities: cities,
                  labelText: AppStrings.routePlanStartCity,
                  hintText: AppStrings.routePlanStartHint,
                  showFieldLabel: false,
                  onCommitted: (_) => n.touchDraft(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stickyRouteSummaryBar(
    BuildContext context,
    RotaDataState data,
    RoutePlanningNotifier n, {
    required double bottomInset,
  }) {
    final distOk = _planDistanceM != null &&
        _planDurationS != null &&
        _planDistanceM! > 0 &&
        _planDurationS! > 0;
    final distLabel =
        distOk ? formatRouteDistanceMeters(_planDistanceM!) : '—';
    final durLabel =
        distOk ? formatRouteDurationSeconds(_planDurationS!) : '—';

    return Material(
      elevation: 12,
      color: AppColors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.route_rounded, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.routePlanStickySummary,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.campaignSummaryMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$distLabel · $durLabel',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    onPressed: n.calculating
                        ? null
                        : () => unawaited(_shareDraftRoute(n, data)),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text(AppStrings.routePlanShareRoute),
                  ),
                  OutlinedButton.icon(
                    onPressed: _planWaypoints.length < 2
                        ? null
                        : () {
                            final preview = n.previewStopsForMap(data);
                            if (preview == null) return;
                            final q = placeQueriesForRouteStops(data, preview);
                            if (q.length < 2) return;
                            openGoogleDirectionsPlaceQueries(context, q);
                          },
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: const Text(AppStrings.routePlanNavGoogle),
                  ),
                  OutlinedButton.icon(
                    onPressed: _planWaypoints.length < 2
                        ? null
                        : () {
                            final preview = n.previewStopsForMap(data);
                            if (preview == null) return;
                            final q = placeQueriesForRouteStops(data, preview);
                            if (q.length < 2) return;
                            openYandexDirectionsPlaceQueries(context, q);
                          },
                    icon: const Icon(Icons.alt_route_rounded, size: 18),
                    label: const Text(AppStrings.routePlanNavYandex),
                  ),
                  OutlinedButton.icon(
                    onPressed: _planWaypoints.length < 2
                        ? null
                        : () {
                            final preview = n.previewStopsForMap(data);
                            if (preview == null) return;
                            final q = placeQueriesForRouteStops(data, preview);
                            if (q.length < 2) return;
                            openAppleDirectionsPlaceQueries(context, q);
                          },
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text(AppStrings.routePlanNavApple),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: n.calculating ? null : () => _calculate(data),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: n.calculating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.white,
                          ),
                        )
                      : const Text(
                          AppStrings.routePlanShowOnMainMap,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
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

  Widget _buildReorderableStop(
    BuildContext context,
    List<String> cities,
    RoutePlanningNotifier n,
    int i,
    RotaDataState data,
  ) {
    final row = n.intermediate[i];
    final isLast = i == n.intermediate.length - 1;
    final animate = row.id == n.justAddedStopId;

    final card = _surfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _timelineDot(
            icon: isLast ? Icons.flag_rounded : Icons.pin_drop_rounded,
            color: isLast ? const Color(0xFFC62828) : AppColors.primary,
            showLineAbove: true,
            showLineBelow: !isLast,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isLast
                            ? '${AppStrings.routePlanTimelineEnd} · ${i + 1}'
                            : '${AppStrings.routePlanTimelineWaypoint} ${i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary.withValues(alpha: 0.85),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (n.intermediate.length > 1)
                      IconButton(
                        onPressed: () => n.removeStop(i),
                        icon: const Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 22,
                        ),
                        color: AppColors.campaignSummaryMuted,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _IlPickerField(
                  controller: row.city,
                  cities: cities,
                  labelText: AppStrings.routePlanStopCityHint,
                  hintText: AppStrings.routePlanStopCityHint,
                  showFieldLabel: false,
                  onCommitted: (v) => n.trimStopSelectionsForCity(i, v, data),
                ),
                const SizedBox(height: 10),
                _RouteStopDaysField(controller: row.days),
                const SizedBox(height: 14),
                _StopSuggestionsPanel(
                  notifier: n,
                  stopIndex: i,
                  row: row,
                  tabIndex: row.suggestionsTabIndex,
                  onAddMisafirhane: () => _pickMisafirhaneForStop(context, data, n, i),
                  onAddGezi: () => _pickGeziForStop(context, data, n, i),
                  onAddYemek: () => _pickYemekForStop(context, data, n, i),
                ),
              ],
            ),
          ),
          ReorderableDragStartListener(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(left: 4, top: 28),
              child: Icon(
                Icons.drag_handle_rounded,
                color: Colors.grey.shade500,
              ),
            ),
          ),
        ],
      ),
    );

    final wrapped = animate ? _EnterSlide(child: card) : card;
    return KeyedSubtree(key: ValueKey<String>(row.id), child: wrapped);
  }

  Widget _surfaceCard({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(_cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_cardRadius),
            boxShadow: _cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _timelineDot({
    required IconData icon,
    required Color color,
    bool showLineAbove = false,
    bool showLineBelow = false,
  }) {
    const lineW = 2.0;
    const gap = 6.0;
    return Column(
      children: [
        if (showLineAbove)
          Container(
            width: lineW,
            height: gap,
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 18),
        ),
        if (showLineBelow)
          Container(
            width: lineW,
            height: gap,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }

}

/// Durak için önerilen tesis / gezi / yemek — sekmeler; geri tuşu önceki sekmeye gider.
class _StopSuggestionsPanel extends StatefulWidget {
  const _StopSuggestionsPanel({
    required this.notifier,
    required this.stopIndex,
    required this.row,
    required this.tabIndex,
    required this.onAddMisafirhane,
    required this.onAddGezi,
    required this.onAddYemek,
  });

  final RoutePlanningNotifier notifier;
  final int stopIndex;
  final RouteStopDraft row;
  final int tabIndex;
  final VoidCallback onAddMisafirhane;
  final VoidCallback onAddGezi;
  final VoidCallback onAddYemek;

  @override
  State<_StopSuggestionsPanel> createState() => _StopSuggestionsPanelState();
}

class _StopSuggestionsPanelState extends State<_StopSuggestionsPanel>
    with SingleTickerProviderStateMixin {
  static const _cKonak = Color(0xFF1565C0);
  static const _cGezi = Color(0xFF2E7D32);
  static const _cYemek = Color(0xFFE65100);

  late TabController _tc;

  @override
  void initState() {
    super.initState();
    _tc = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.tabIndex.clamp(0, 2),
    );
    _tc.addListener(_onTabTick);
  }

  void _onTabTick() {
    if (_tc.indexIsChanging) return;
    widget.notifier.setStopSuggestionsTab(widget.stopIndex, _tc.index);
  }

  @override
  void didUpdateWidget(covariant _StopSuggestionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.tabIndex.clamp(0, 2);
    if (oldWidget.tabIndex != widget.tabIndex && _tc.index != next) {
      _tc.index = next;
    }
  }

  @override
  void dispose() {
    _tc.removeListener(_onTabTick);
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final il = row.city.text.trim();
    final disabled = il.isEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.routePlanSuggestionsTitle,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            if (!disabled) ...[
              const SizedBox(height: 4),
              Text(
                il,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary.withValues(alpha: 0.85),
                ),
              ),
            ],
            if (disabled)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: AppColors.campaignSummaryMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        AppStrings.routePlanPickNeedCity,
                        style: TextStyle(fontSize: 12, color: AppColors.campaignSummaryMuted),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              const SizedBox(height: 10),
              TabBar(
                controller: _tc,
                isScrollable: true,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.campaignSummaryMuted,
                indicatorColor: AppColors.primary,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(icon: const Icon(Icons.hotel_rounded, size: 18), text: AppStrings.routePlanKonak),
                  Tab(icon: const Icon(Icons.park_rounded, size: 18), text: AppStrings.routePlanGezi),
                  Tab(icon: const Icon(Icons.restaurant_rounded, size: 18), text: AppStrings.routePlanYemek),
                ],
              ),
              const SizedBox(height: 10),
              AnimatedBuilder(
                animation: _tc,
                builder: (context, _) {
                  switch (_tc.index) {
                    case 0:
                      return _suggestionBlock(
                        context,
                        header: const _PlanSectionTitle(
                          icon: Icons.hotel_rounded,
                          label: AppStrings.routePlanKonak,
                          color: _cKonak,
                        ),
                        onAdd: widget.onAddMisafirhane,
                        children: row.konakSecimler
                            .map(
                              (m) => _suggestionRow(
                                title: m.isim,
                                subtitle: m.adres,
                                onRemove: () => widget.notifier.removeStopKonak(widget.stopIndex, m),
                              ),
                            )
                            .toList(),
                      );
                    case 1:
                      return _suggestionBlock(
                        context,
                        header: const _PlanSectionTitle(
                          icon: Icons.park_rounded,
                          label: AppStrings.routePlanGezi,
                          color: _cGezi,
                        ),
                        onAdd: widget.onAddGezi,
                        children: row.geziSecimler
                            .map(
                              (g) => _suggestionRow(
                                title: g.isim,
                                subtitle: g.adres,
                                onRemove: () => widget.notifier.removeStopGezi(widget.stopIndex, g),
                              ),
                            )
                            .toList(),
                      );
                    default:
                      return _suggestionBlock(
                        context,
                        header: const _PlanSectionTitle(
                          icon: Icons.restaurant_rounded,
                          label: AppStrings.routePlanYemek,
                          color: _cYemek,
                        ),
                        onAdd: widget.onAddYemek,
                        children: row.yemekSecimler
                            .map(
                              (y) => _suggestionRow(
                                title: y.isim,
                                subtitle: y.adres,
                                onRemove: () => widget.notifier.removeStopYemek(widget.stopIndex, y),
                              ),
                            )
                            .toList(),
                      );
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _suggestionBlock(
    BuildContext context, {
    required _PlanSectionTitle header,
    required List<Widget> children,
    VoidCallback? onAdd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: header),
            TextButton(
              onPressed: onAdd,
              child: const Text(AppStrings.routePlanAdd),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (children.isEmpty)
          Text(
            AppStrings.routePlanNoSuggestions,
            style: TextStyle(fontSize: 12, color: AppColors.campaignSummaryMuted.withValues(alpha: 0.9)),
          )
        else
          ...children,
      ],
    );
  }

  Widget _suggestionRow({
    required String title,
    required String subtitle,
    required VoidCallback onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: AppColors.campaignSummaryMuted.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: onRemove,
                child: const Text(AppStrings.routePlanRemove),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanSectionTitle extends StatelessWidget {
  const _PlanSectionTitle({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _EnterSlide extends StatefulWidget {
  const _EnterSlide({required this.child});

  final Widget child;

  @override
  State<_EnterSlide> createState() => _EnterSlideState();
}

class _EnterSlideState extends State<_EnterSlide>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Gün sayısı alanı — [TextEditingController] ile; üst rota listesinin her tuşta
/// yeniden çizilmesini sınırlamak için form alanı ayrı widget.
class _RouteStopDaysField extends StatelessWidget {
  const _RouteStopDaysField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: AppStrings.routePlanDaysHint,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        filled: true,
        fillColor: AppColors.suggestionFieldBg.withValues(alpha: 0.6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}

class _IlPickerField extends StatefulWidget {
  const _IlPickerField({
    required this.controller,
    required this.cities,
    required this.labelText,
    required this.hintText,
    this.showFieldLabel = true,
    this.onCommitted,
  });

  final TextEditingController controller;
  final List<String> cities;
  final String labelText;
  final String hintText;
  final bool showFieldLabel;
  final ValueChanged<String>? onCommitted;

  @override
  State<_IlPickerField> createState() => _IlPickerFieldState();
}

class _IlPickerFieldState extends State<_IlPickerField> {
  Future<void> _openSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final v = await showIlSearchSheet(
      context,
      cities: widget.cities,
      title: widget.showFieldLabel
          ? widget.labelText
          : AppStrings.routePlanSelectIl,
      currentSelection: widget.controller.text.trim().isEmpty
          ? null
          : widget.controller.text.trim(),
    );
    if (v != null && mounted) {
      final prev = widget.controller.text.trim();
      widget.controller.text = v;
      if (v.trim() != prev) {
        widget.onCommitted?.call(v);
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text.trim();
    final has = value.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showFieldLabel) ...[
          Text(
            widget.labelText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary.withValues(alpha: 0.9),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Material(
          color: AppColors.suggestionFieldBg.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _openSheet,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.location_city_rounded,
                    size: 22,
                    color: has
                        ? AppColors.primary
                        : AppColors.campaignSummaryMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      has ? value : widget.hintText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: has ? FontWeight.w600 : FontWeight.w500,
                        color: has
                            ? AppColors.textPrimary
                            : AppColors.campaignSummaryMuted,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
