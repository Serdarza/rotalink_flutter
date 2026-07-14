import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../data/firebase_rota_repository.dart';
import '../data/saved_routes_repository.dart';
import '../l10n/app_strings.dart';
import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
import '../models/route_plan_outcome.dart';
import '../models/route_stop.dart';
import '../route/route_city_advice.dart';
import '../route/route_enricher.dart';
import '../services/osrm_route_service.dart';
import '../theme/app_colors.dart';
import '../utils/geo_helpers.dart';
import '../utils/route_facility_lookup.dart';
import '../utils/safe_map_coordinates.dart';
import '../utils/search_normalize.dart';
import '../widgets/route_plan_preview_sheet.dart';
import '../widgets/rotalink_tile_layer.dart';

/// Yol üzeri mola + varış konaklama tavsiyeleri.
class RoutePlanAdviceScreen extends StatefulWidget {
  RoutePlanAdviceScreen({
    super.key,
    required this.data,
    required this.stops,
    this.restoreSaved = false,
    SavedRoutesRepository? savedRoutesRepository,
  }) : savedRoutesRepository =
            savedRoutesRepository ?? SavedRoutesRepository();

  final RotaDataState data;
  final List<RouteStop> stops;

  /// true: kayıtlı rotayı aç — seçimler korunur, iller yeniden keşfedilmez.
  final bool restoreSaved;
  final SavedRoutesRepository savedRoutesRepository;

  @override
  State<RoutePlanAdviceScreen> createState() => _RoutePlanAdviceScreenState();
}

class _RoutePlanAdviceScreenState extends State<RoutePlanAdviceScreen> {
  List<CityRouteCatalog> _catalogs = const [];
  Map<String, CityRoutePicks> _picks = {};
  final Set<String> _skippedCities = {};
  final MapController _map = MapController();

  List<LatLng> _polyline = const [];
  List<Marker> _markers = const [];
  double? _distanceM;
  double? _durationS;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  CityRoutePicks _pickFor(String city) =>
      _picks.putIfAbsent(city.toLowerCase(), CityRoutePicks.new);

  Future<void> _bootstrap() async {
    final waypoints = waypointsForRouteStops(widget.data, widget.stops);
    if (waypoints.length < 2) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = AppStrings.routePlanInsufficientLocations;
        _markers = _numberedMarkers(waypoints);
      });
      return;
    }

    try {
      final segments = await OsrmRouteService.fetchSegments(waypoints);
      if (!mounted) return;
      var totalM = 0.0;
      var totalS = 0.0;
      final merged = <LatLng>[];
      for (final s in segments) {
        totalM += s.distanceM;
        totalS += s.durationS;
        for (final p in s.points) {
          if (!isValidWgs84LatLng(p.latitude, p.longitude)) continue;
          if (merged.isEmpty ||
              merged.last.latitude != p.latitude ||
              merged.last.longitude != p.longitude) {
            merged.add(p);
          }
        }
      }
      final polyline =
          merged.length >= 2 ? merged : OsrmRouteService.straightFallback(waypoints);

      final restored = _restoreCatalogsAndPicks(polyline);
      setState(() {
        _polyline = polyline;
        _markers = _numberedMarkers(waypoints);
        _distanceM = totalM > 0 ? totalM : null;
        _durationS = totalS > 0 ? totalS : null;
        _catalogs = restored.$1;
        _picks = restored.$2;
        _loading = false;
      });
      _fitMap(polyline.length >= 2 ? polyline : waypoints);
    } catch (_) {
      if (!mounted) return;
      final fallback = OsrmRouteService.straightFallback(waypoints);
      final restored = _restoreCatalogsAndPicks(fallback);
      setState(() {
        _polyline = fallback;
        _markers = _numberedMarkers(waypoints);
        _catalogs = restored.$1;
        _picks = restored.$2;
        _loading = false;
      });
      _fitMap(waypoints);
    }
  }

  /// Kayıtlı rota: seçimler korunur. Eski kayıtlar (items yok) → yeniden keşif + varsayılan öneriler.
  (List<CityRouteCatalog>, Map<String, CityRoutePicks>) _restoreCatalogsAndPicks(
    List<LatLng> polyline,
  ) {
    final hasSavedItems = widget.stops.any((s) => s.items.isNotEmpty);
    if (widget.restoreSaved && hasSavedItems) {
      final catalogs = RouteCityAdviceBuilder.catalogsForSavedStops(
        data: widget.data,
        stops: widget.stops,
      );
      return (catalogs, RouteCityAdviceBuilder.picksFromStops(widget.stops));
    }
    final catalogs = RouteCityAdviceBuilder.buildPlan(
      data: widget.data,
      stops: widget.stops,
      polyline: polyline,
    );
    return (catalogs, RouteCityAdviceBuilder.defaultPicks(catalogs));
  }

  List<Marker> _numberedMarkers(List<LatLng> points) {
    return [
      for (var i = 0; i < points.length; i++)
        Marker(
          point: latLngOrFallback(points[i].latitude, points[i].longitude),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: CircleAvatar(
            radius: 15,
            backgroundColor: i == 0
                ? const Color(0xFF2E7D32)
                : i == points.length - 1
                    ? const Color(0xFFC62828)
                    : AppColors.primary,
            child: Text(
              '${i + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
    ];
  }

  void _fitMap(List<LatLng> pts) {
    final valid = onlyValidLatLngs(pts);
    if (valid.length < 2) return;
    try {
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: valid,
          padding: const EdgeInsets.all(28),
        ),
      );
    } catch (_) {}
  }

  List<RouteStop> _stopsWithSelections() {
    return RouteCityAdviceBuilder.composeStops(
      baseStops: widget.stops,
      catalogs: _catalogs,
      picks: _picks,
      skippedCities: _skippedCities,
    );
  }

  void _skipAlongCity(CityRouteCatalog catalog) {
    if (catalog.role != RouteCityRole.along) return;
    final key = catalog.city.toLowerCase();
    setState(() {
      _skippedCities.add(key);
      _picks[key]?.tesisler.clear();
      _picks[key]?.gezi.clear();
      _picks[key]?.yemek.clear();
      _picks.remove(key);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${catalog.city} rotadan çıkarıldı'),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              _skippedCities.remove(key);
              _picks[key] = RouteCityAdviceBuilder.defaultPicks(
                [catalog],
              )[key] ??
                  CityRoutePicks();
            });
          },
        ),
      ),
    );
  }

  String _shareText() {
    final start = widget.stops.first.city;
    final end = widget.stops.last.city;
    final buf = StringBuffer()
      ..writeln('Rotalink — Rota tavsiyesi')
      ..writeln('$start → $end');
    if (_distanceM != null &&
        _durationS != null &&
        _distanceM! > 0 &&
        _durationS! > 0) {
      buf
        ..writeln()
        ..writeln('Mesafe: ${formatRouteDistanceMeters(_distanceM!)}')
        ..writeln('Süre: ${formatRouteDurationSeconds(_durationS!)}');
    }
    buf
      ..writeln()
      ..writeln('🚗 Hareket: $start (öneri yok — buradan yola çıkıyorsunuz)');

    final along = _catalogs.where((c) => c.role == RouteCityRole.along);
    if (along.isNotEmpty) {
      buf.writeln();
      buf.writeln('☕ Yol üzeri molalar');
      for (final catalog in along) {
        if (_skippedCities.contains(catalog.city.toLowerCase())) continue;
        final pick = _pickFor(catalog.city);
        buf.writeln('📍 ${catalog.city}');
        if (pick.tesisler.isNotEmpty) {
          buf.writeln('  Mola:');
          for (final m in pick.tesisler) {
            buf.writeln('  • ${m.isim}');
          }
        }
        if (pick.gezi.isNotEmpty) {
          buf.writeln('  Gezi:');
          for (final g in pick.gezi) {
            buf.writeln('  • ${g.isim}');
          }
        }
        if (pick.yemek.isNotEmpty) {
          buf.writeln('  Yemek:');
          for (final y in pick.yemek) {
            buf.writeln('  • ${y.isim}');
          }
        }
        if (pick.totalCount == 0) buf.writeln('  (seçim yok)');
      }
    }

    final arrival = _catalogs.where((c) => c.role == RouteCityRole.arrival);
    for (final catalog in arrival) {
      final pick = _pickFor(catalog.city);
      buf
        ..writeln()
        ..writeln('🏁 Varış: ${catalog.city} (${catalog.days} gün)');
      if (pick.tesisler.isNotEmpty) {
        buf.writeln('  Konaklama:');
        for (final m in pick.tesisler) {
          buf.writeln('  • ${m.isim}');
        }
      }
      if (pick.gezi.isNotEmpty) {
        buf.writeln('  Gezi:');
        for (final g in pick.gezi) {
          buf.writeln('  • ${g.isim}');
        }
      }
      if (pick.yemek.isNotEmpty) {
        buf.writeln('  Yemek:');
        for (final y in pick.yemek) {
          buf.writeln('  • ${y.isim}');
        }
      }
    }

    buf
      ..writeln()
      ..writeln('https://play.google.com/store/apps/details?id=com.serdarza.rotalink');
    return buf.toString().trim();
  }

  Future<void> _share() async {
    await Share.share(_shareText(), subject: 'Rotalink rota tavsiyesi');
  }

  Future<void> _save() async {
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
            autofocus: true,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.routePlanSaveEmptyName)),
        );
        return;
      }
      final stops = _stopsWithSelections();
      final lites = stops.map(RouteStopLite.fromRouteStop).toList();
      await widget.savedRoutesRepository.upsert(
        SavedRouteRecord(
          name: name,
          savedDateMillis: DateTime.now().millisecondsSinceEpoch,
          stops: lites,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.routePlanSaveSuccess)),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => nameCtrl.dispose());
    }
  }

  Future<void> _addTesis(CityRouteCatalog catalog) async {
    final pick = _pickFor(catalog.city);
    final label = catalog.role == RouteCityRole.along ? 'Mola / dinlenme' : 'Konaklama';
    final chosen = await _pickFromList<Misafirhane>(
      title: '${catalog.city} — $label',
      items: catalog.tesisler,
      selected: pick.tesisler,
      same: CityRoutePicks.sameTesis,
      titleOf: (m) => m.isim,
      subtitleOf: (m) => m.adres,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      if (!pick.tesisler.any((x) => CityRoutePicks.sameTesis(x, chosen))) {
        pick.tesisler.add(chosen);
      }
    });
  }

  Future<void> _addGezi(CityRouteCatalog catalog, {required bool yemek}) async {
    final pick = _pickFor(catalog.city);
    final list = yemek ? catalog.yemek : catalog.gezi;
    final selected = yemek ? pick.yemek : pick.gezi;
    final chosen = await _pickFromList<GeziYemekItem>(
      title: '${catalog.city} — ${yemek ? 'Yemek' : 'Gezi'}',
      items: list,
      selected: selected,
      same: CityRoutePicks.sameGezi,
      titleOf: (g) => g.isim,
      subtitleOf: (g) => g.adres,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      if (!selected.any((x) => CityRoutePicks.sameGezi(x, chosen))) {
        selected.add(chosen);
      }
    });
  }

  Future<T?> _pickFromList<T>({
    required String title,
    required List<T> items,
    required List<T> selected,
    required bool Function(T a, T b) same,
    required String Function(T) titleOf,
    required String Function(T) subtitleOf,
  }) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.routePlanNoDataForIl)),
      );
      return null;
    }
    final search = TextEditingController();
    try {
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
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
                    ? items
                    : items
                        .where(
                          (e) => normalizeForSearch(
                            '${titleOf(e)} ${subtitleOf(e)}',
                          ).contains(q),
                        )
                        .toList();
                return DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.62,
                  minChildSize: 0.4,
                  maxChildSize: 0.92,
                  builder: (_, scroll) {
                    return Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextField(
                            controller: search,
                            onChanged: (_) => setSt(() {}),
                            decoration: InputDecoration(
                              hintText: 'Ara…',
                              prefixIcon: const Icon(Icons.search_rounded),
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
                              ? const Center(child: Text('Sonuç yok'))
                              : ListView.builder(
                                  controller: scroll,
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) {
                                    final item = filtered[i];
                                    final already =
                                        selected.any((s) => same(s, item));
                                    return ListTile(
                                      enabled: !already,
                                      title: Text(
                                        titleOf(item),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: already
                                              ? AppColors.campaignSummaryMuted
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                      subtitle: subtitleOf(item).trim().isEmpty
                                          ? null
                                          : Text(
                                              subtitleOf(item),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                      trailing: already
                                          ? const Icon(
                                              Icons.check_circle_rounded,
                                              color: AppColors.primary,
                                            )
                                          : const Icon(Icons.add_circle_outline_rounded),
                                      onTap: already
                                          ? null
                                          : () => Navigator.pop(ctx, item),
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
    } finally {
      search.dispose();
    }
  }

  Future<void> _finish() async {
    if (_submitting || _loading) return;
    setState(() => _submitting = true);
    try {
      final raw = _stopsWithSelections();
      final enriched = RouteEnricher.enrich(raw);
      final waypoints = waypointsForRouteStops(widget.data, enriched);
      if (waypoints.length < 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.routePlanInsufficientLocations),
          ),
        );
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
      final hasOsrm =
          segments.isNotEmpty && totalDistanceM > 0 && totalDurationS > 0;

      final go = await showRoutePlanPreviewSheet(
        context: context,
        stops: enriched,
        distanceM: hasOsrm ? totalDistanceM : null,
        durationS: hasOsrm ? totalDurationS : null,
        navigationWaypoints: waypoints,
        navigationPlaceQueries: placeQueriesForRouteStops(widget.data, enriched),
      );
      if (!mounted || go != true) return;

      Navigator.of(context).pop<RoutePlanOutcome>(
        RoutePlanOutcome(
          stops: enriched,
          segments: segments.isNotEmpty ? segments : null,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rota hesaplanamadı. Ağ bağlantınızı kontrol edin.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.stops.first.city;
    final end = widget.stops.last.city;
    final dist = _distanceM != null && _distanceM! > 0
        ? formatRouteDistanceMeters(_distanceM!)
        : '—';
    final dur = _durationS != null && _durationS! > 0
        ? formatRouteDurationSeconds(_durationS!)
        : '—';
    final along = _catalogs
        .where(
          (c) =>
              c.role == RouteCityRole.along &&
              !_skippedCities.contains(c.city.toLowerCase()),
        )
        .toList();
    final arrival =
        _catalogs.where((c) => c.role == RouteCityRole.arrival).toList();
    final skippedCount = _skippedCities.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F8),
      appBar: AppBar(
        title: const Text('Rota tavsiyeleri'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: AppStrings.routePlanShareRoute,
            onPressed: _loading ? null : _share,
            icon: const Icon(Icons.share_rounded),
          ),
          IconButton(
            tooltip: AppStrings.routePlanSaveTitle,
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 14),
                  Text(
                    'Rota oluşturuluyor…',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Yol üzerindeki iller bulunuyor',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.campaignSummaryMuted,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      if (_loadError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(_loadError!, style: const TextStyle(color: Colors.red)),
                        ),
                      _HeaderCard(
                        start: start,
                        end: end,
                        distance: dist,
                        duration: dur,
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 156,
                          child: FlutterMap(
                            mapController: _map,
                            options: MapOptions(
                              initialCenter: kTurkeyMapFallbackCenter,
                              initialZoom: kTurkeyMapFallbackZoom,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.pinchZoom |
                                    InteractiveFlag.drag,
                              ),
                            ),
                            children: [
                              const RotalinkTileLayer(),
                              if (_polyline.length >= 2)
                                PolylineLayer(
                                  polylines: [
                                    Polyline<Object>(
                                      points: _polyline,
                                      strokeWidth: 4,
                                      color: AppColors.primary,
                                    ),
                                  ],
                                ),
                              MarkerLayer(markers: _markers),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const _SectionTitle(
                        title: 'Yol üzeri',
                        subtitle:
                            'Güzergâhtaki tüm iller. Pas geçmek istediğinizi Kaldır ile çıkarın.',
                      ),
                      if (skippedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '$skippedCount il pas geçildi',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.campaignSummaryMuted,
                            ),
                          ),
                        ),
                      if (along.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Gösterilecek yol üstü ili kalmadı. Varış önerilerine bakabilirsiniz.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.campaignSummaryMuted,
                              height: 1.35,
                            ),
                          ),
                        )
                      else
                        for (final catalog in along) ...[
                          _CityCard(
                            catalog: catalog,
                            picks: _pickFor(catalog.city),
                            onSkipCity: () => _skipAlongCity(catalog),
                            onRemoveTesis: (m) => setState(
                              () => _pickFor(catalog.city).tesisler.removeWhere(
                                    (x) => CityRoutePicks.sameTesis(x, m),
                                  ),
                            ),
                            onRemoveGezi: (g) => setState(
                              () => _pickFor(catalog.city).gezi.removeWhere(
                                    (x) => CityRoutePicks.sameGezi(x, g),
                                  ),
                            ),
                            onRemoveYemek: (y) => setState(
                              () => _pickFor(catalog.city).yemek.removeWhere(
                                    (x) => CityRoutePicks.sameGezi(x, y),
                                  ),
                            ),
                            onAddTesis: () => _addTesis(catalog),
                            onAddGezi: () => _addGezi(catalog, yemek: false),
                            onAddYemek: () => _addGezi(catalog, yemek: true),
                          ),
                          const SizedBox(height: 12),
                        ],
                      const SizedBox(height: 8),
                      const _SectionTitle(
                        title: 'Varış',
                        subtitle: 'Burada konaklar, gezer ve yemek yersiniz.',
                      ),
                      for (final catalog in arrival) ...[
                        _CityCard(
                          catalog: catalog,
                          picks: _pickFor(catalog.city),
                          onRemoveTesis: (m) => setState(
                            () => _pickFor(catalog.city).tesisler.removeWhere(
                                  (x) => CityRoutePicks.sameTesis(x, m),
                                ),
                          ),
                          onRemoveGezi: (g) => setState(
                            () => _pickFor(catalog.city).gezi.removeWhere(
                                  (x) => CityRoutePicks.sameGezi(x, g),
                                ),
                          ),
                          onRemoveYemek: (y) => setState(
                            () => _pickFor(catalog.city).yemek.removeWhere(
                                  (x) => CityRoutePicks.sameGezi(x, y),
                                ),
                          ),
                          onAddTesis: () => _addTesis(catalog),
                          onAddGezi: () => _addGezi(catalog, yemek: false),
                          onAddYemek: () => _addGezi(catalog, yemek: true),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting ? null : _finish,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
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
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: AppColors.campaignSummaryMuted.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.start,
    required this.end,
    required this.distance,
    required this.duration,
  });

  final String start;
  final String end;
  final String distance;
  final String duration;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$start → $end',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Başlangıçta öneri yok — buradan sadece yola çıkıyorsunuz.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.campaignSummaryMuted.withValues(alpha: 0.95),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.straighten_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(distance, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 14),
                const Icon(Icons.schedule_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(duration, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CityCard extends StatelessWidget {
  const _CityCard({
    required this.catalog,
    required this.picks,
    required this.onRemoveTesis,
    required this.onRemoveGezi,
    required this.onRemoveYemek,
    required this.onAddTesis,
    required this.onAddGezi,
    required this.onAddYemek,
    this.onSkipCity,
  });

  final CityRouteCatalog catalog;
  final CityRoutePicks picks;
  final ValueChanged<Misafirhane> onRemoveTesis;
  final ValueChanged<GeziYemekItem> onRemoveGezi;
  final ValueChanged<GeziYemekItem> onRemoveYemek;
  final VoidCallback onAddTesis;
  final VoidCallback onAddGezi;
  final VoidCallback onAddYemek;
  final VoidCallback? onSkipCity;

  @override
  Widget build(BuildContext context) {
    final along = catalog.role == RouteCityRole.along;
    final badge = along ? 'Yolda mola' : 'Varış · ${catalog.days} gün';
    final tesisLabel = along ? 'Mola / dinlenme' : 'Konaklama';
    final badgeColor = along ? const Color(0xFFEF6C00) : AppColors.primary;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    along ? Icons.local_cafe_rounded : Icons.flag_rounded,
                    color: badgeColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        catalog.city,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '$badge · ${picks.totalCount} seçili',
                        style: TextStyle(fontSize: 12, color: badgeColor),
                      ),
                    ],
                  ),
                ),
                if (onSkipCity != null)
                  TextButton(
                    onPressed: onSkipCity,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFC62828),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Kaldır'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _CategoryBlock(
              icon: along ? Icons.coffee_rounded : Icons.hotel_rounded,
              label: tesisLabel,
              color: along ? const Color(0xFFEF6C00) : const Color(0xFF1565C0),
              emptyLabel: along ? 'Mola eklenmedi' : 'Konaklama eklenmedi',
              onAdd: catalog.tesisler.isEmpty ? null : onAddTesis,
              children: [
                for (final m in picks.tesisler)
                  _PickTile(
                    title: m.isim,
                    subtitle: m.adres,
                    onRemove: () => onRemoveTesis(m),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _CategoryBlock(
              icon: Icons.park_rounded,
              label: 'Gezi',
              color: const Color(0xFF2E7D32),
              emptyLabel: 'Gezi eklenmedi',
              onAdd: catalog.gezi.isEmpty ? null : onAddGezi,
              children: [
                for (final g in picks.gezi)
                  _PickTile(
                    title: g.isim,
                    subtitle: g.adres,
                    onRemove: () => onRemoveGezi(g),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _CategoryBlock(
              icon: Icons.restaurant_rounded,
              label: 'Yemek',
              color: const Color(0xFFE65100),
              emptyLabel: 'Yemek eklenmedi',
              onAdd: catalog.yemek.isEmpty ? null : onAddYemek,
              children: [
                for (final y in picks.yemek)
                  _PickTile(
                    title: y.isim,
                    subtitle: y.adres,
                    onRemove: () => onRemoveYemek(y),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.icon,
    required this.label,
    required this.color,
    required this.emptyLabel,
    required this.children,
    this.onAdd,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String emptyLabel;
  final List<Widget> children;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            if (onAdd != null)
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ekle'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: color,
                ),
              ),
          ],
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              emptyLabel,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.campaignSummaryMuted,
              ),
            ),
          )
        else
          ...children,
      ],
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.title,
    required this.subtitle,
    required this.onRemove,
  });

  final String title;
  final String subtitle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: const Color(0xFFF6F8F9),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.campaignSummaryMuted,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppStrings.routePlanRemove,
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppColors.campaignSummaryMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
