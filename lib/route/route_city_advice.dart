import 'package:latlong2/latlong.dart';

import '../data/firebase_rota_repository.dart';
import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
import '../models/route_stop.dart';
import '../utils/main_map_search.dart';
import '../utils/route_facility_lookup.dart';
import '../utils/safe_map_coordinates.dart';

enum RouteCityRole {
  /// Hareket ili — öneri yok.
  departure,
  /// Yol üzeri mola / gezi / yemek.
  along,
  /// Varış — konaklama + gezi + yemek.
  arrival,
}

/// Bir il için tam katalog.
class CityRouteCatalog {
  const CityRouteCatalog({
    required this.city,
    required this.days,
    required this.role,
    required this.tesisler,
    required this.gezi,
    required this.yemek,
  });

  final String city;
  final int days;
  final RouteCityRole role;
  final List<Misafirhane> tesisler;
  final List<GeziYemekItem> gezi;
  final List<GeziYemekItem> yemek;
}

/// Kullanıcının o ilde seçtiği yerler.
class CityRoutePicks {
  CityRoutePicks({
    List<Misafirhane>? tesisler,
    List<GeziYemekItem>? gezi,
    List<GeziYemekItem>? yemek,
  })  : tesisler = List<Misafirhane>.from(tesisler ?? const []),
        gezi = List<GeziYemekItem>.from(gezi ?? const []),
        yemek = List<GeziYemekItem>.from(yemek ?? const []);

  final List<Misafirhane> tesisler;
  final List<GeziYemekItem> gezi;
  final List<GeziYemekItem> yemek;

  int get totalCount => tesisler.length + gezi.length + yemek.length;

  static bool sameTesis(Misafirhane a, Misafirhane b) =>
      a.isim.trim().toLowerCase() == b.isim.trim().toLowerCase() &&
      a.il.trim().toLowerCase() == b.il.trim().toLowerCase();

  static bool sameGezi(GeziYemekItem a, GeziYemekItem b) =>
      a.isim.trim().toLowerCase() == b.isim.trim().toLowerCase() &&
      a.il.trim().toLowerCase() == b.il.trim().toLowerCase();
}

class _CityAnchor {
  const _CityAnchor({
    required this.city,
    required this.point,
    required this.progress,
    required this.distM,
  });

  final String city;
  final LatLng point;
  final double progress;
  final double distM;
}

/// Rota mantığı: başlangıç önerisiz, yol üzeri mola, varışta konaklama.
abstract final class RouteCityAdviceBuilder {
  /// Yol koridoru (km) — ana güzergâhtaki illeri kaçırmamak için geniş.
  static const double corridorKm = 65;
  /// Başlangıç / varışa çok yakın illeri eleyelim.
  static const double excludeEndsKm = 40;

  static const int alongMolaDefault = 1;
  static const int alongGeziDefault = 1;
  static const int alongYemekDefault = 1;
  static const int arrivalKonakDefault = 1;
  static const int arrivalGeziDefault = 2;
  static const int arrivalYemekDefault = 1;

  /// [stops]: başlangıç + (opsiyonel ara) + varış.
  static List<CityRouteCatalog> buildPlan({
    required RotaDataState data,
    required List<RouteStop> stops,
    required List<LatLng> polyline,
  }) {
    if (stops.length < 2) return const [];

    final start = stops.first.city.trim();
    final end = stops.last.city.trim();
    final startKey = start.toLowerCase();
    final endKey = end.toLowerCase();
    final userMid = <String>[
      for (var i = 1; i < stops.length - 1; i++) stops[i].city.trim(),
    ].where((c) => c.isNotEmpty).toList();

    final alongOrdered = _discoverAlongCities(
      data: data,
      polyline: polyline,
      startKey: startKey,
      endKey: endKey,
      userMid: userMid,
    );

    final catalogs = <CityRouteCatalog>[];
    for (final city in alongOrdered) {
      catalogs.add(
        _catalogFor(
          data: data,
          city: city,
          days: 0,
          role: RouteCityRole.along,
        ),
      );
    }
    catalogs.add(
      _catalogFor(
        data: data,
        city: end,
        days: stops.last.days < 1 ? 1 : stops.last.days,
        role: RouteCityRole.arrival,
      ),
    );
    return catalogs;
  }

  static Map<String, CityRoutePicks> defaultPicks(List<CityRouteCatalog> catalogs) {
    final map = <String, CityRoutePicks>{};
    for (final c in catalogs) {
      if (c.role == RouteCityRole.departure) continue;
      if (c.role == RouteCityRole.along) {
        map[c.city.toLowerCase()] = CityRoutePicks(
          tesisler: c.tesisler.take(alongMolaDefault).toList(),
          gezi: c.gezi.take(alongGeziDefault).toList(),
          yemek: c.yemek.take(alongYemekDefault).toList(),
        );
      } else {
        map[c.city.toLowerCase()] = CityRoutePicks(
          tesisler: c.tesisler.take(arrivalKonakDefault).toList(),
          gezi: c.gezi.take(arrivalGeziDefault).toList(),
          yemek: c.yemek.take(arrivalYemekDefault).toList(),
        );
      }
    }
    return map;
  }

  /// Kayıtlı duraklardan tam katalog (yalnızca kayıtlı iller; yeniden keşif yok).
  static List<CityRouteCatalog> catalogsForSavedStops({
    required RotaDataState data,
    required List<RouteStop> stops,
  }) {
    if (stops.length < 2) return const [];
    final out = <CityRouteCatalog>[];
    for (var i = 1; i < stops.length; i++) {
      final stop = stops[i];
      final isLast = i == stops.length - 1;
      out.add(
        _catalogFor(
          data: data,
          city: stop.city,
          days: isLast ? (stop.days < 1 ? 1 : stop.days) : 0,
          role: isLast ? RouteCityRole.arrival : RouteCityRole.along,
        ),
      );
    }
    return out;
  }

  /// Kayıtlı [RouteStop.items] → seçim haritası.
  static Map<String, CityRoutePicks> picksFromStops(List<RouteStop> stops) {
    final map = <String, CityRoutePicks>{};
    for (final stop in stops) {
      final key = stop.city.trim().toLowerCase();
      if (key.isEmpty) continue;
      final tesisler = <Misafirhane>[];
      final gezi = <GeziYemekItem>[];
      final yemek = <GeziYemekItem>[];
      for (final o in stop.items) {
        if (o is Misafirhane) {
          tesisler.add(o);
        } else if (o is GeziYemekItem) {
          final tur = (o.tur ?? '').toLowerCase();
          if (tur.contains('yemek')) {
            yemek.add(o);
          } else {
            gezi.add(o);
          }
        }
      }
      map[key] = CityRoutePicks(tesisler: tesisler, gezi: gezi, yemek: yemek);
    }
    return map;
  }

  /// Haritaya aktarılacak duraklar: başlangıç + seçimli yol illeri + varış.
  static List<RouteStop> composeStops({
    required List<RouteStop> baseStops,
    required List<CityRouteCatalog> catalogs,
    required Map<String, CityRoutePicks> picks,
    Set<String> skippedCities = const {},
  }) {
    final start = baseStops.first;
    final end = baseStops.last;
    final skipped = {
      for (final s in skippedCities) s.trim().toLowerCase(),
    };
    final forcedMid = <String>{
      for (var i = 1; i < baseStops.length - 1; i++)
        baseStops[i].city.trim().toLowerCase(),
    }..removeWhere(skipped.contains);

    final out = <RouteStop>[RouteStop(city: start.city, days: 0, items: const [])];

    for (final catalog in catalogs) {
      if (catalog.role == RouteCityRole.arrival) continue;
      final key = catalog.city.toLowerCase();
      if (skipped.contains(key)) continue;
      final pick = picks[key] ?? CityRoutePicks();
      final forced = forcedMid.contains(key);
      if (!forced && pick.totalCount == 0) continue;
      out.add(
        RouteStop(
          city: catalog.city,
          days: 0,
          items: _itemsFromPick(pick, nights: 1),
        ),
      );
    }

    final endPick = picks[end.city.toLowerCase()] ?? CityRoutePicks();
    final nights = end.days < 1 ? 1 : end.days;
    out.add(
      RouteStop(
        city: end.city,
        days: nights,
        items: _itemsFromPick(endPick, nights: nights),
      ),
    );
    return _distinctByCity(out);
  }

  static List<Object> _itemsFromPick(CityRoutePicks pick, {required int nights}) {
    final items = <Object>[...pick.tesisler];
    for (var i = 0; i < pick.gezi.length; i++) {
      items.add(
        pick.gezi[i].forRouteSuggestion(turLabel: 'Gezi', day: (i % nights) + 1),
      );
    }
    for (var i = 0; i < pick.yemek.length; i++) {
      items.add(
        pick.yemek[i].forRouteSuggestion(turLabel: 'Yemek', day: (i % nights) + 1),
      );
    }
    return items;
  }

  static List<RouteStop> _distinctByCity(List<RouteStop> stops) {
    final seen = <String>{};
    final out = <RouteStop>[];
    for (final s in stops) {
      final k = s.city.trim().toLowerCase();
      if (!seen.add(k)) continue;
      out.add(s);
    }
    return out;
  }

  static CityRouteCatalog _catalogFor({
    required RotaDataState data,
    required String city,
    required int days,
    required RouteCityRole role,
  }) {
    final key = city.trim().toLowerCase();
    final kaynak = MainMapSearch.tesisKaynagiArama(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    final tesisler = kaynak
        .where((m) => m.il.trim().toLowerCase() == key)
        .toList()
      ..sort((a, b) => a.isim.compareTo(b.isim));
    final gezi = _uniqueByName(
      data.gezi.where(
        (g) => g.il.trim().toLowerCase() == key && g.isim.trim().isNotEmpty,
      ),
    )..sort((a, b) => a.isim.compareTo(b.isim));
    final yemek = _uniqueByName(
      data.yemek.where(
        (y) => y.il.trim().toLowerCase() == key && y.isim.trim().isNotEmpty,
      ),
    )..sort((a, b) => a.isim.compareTo(b.isim));

    return CityRouteCatalog(
      city: city.trim(),
      days: days,
      role: role,
      tesisler: tesisler,
      gezi: gezi,
      yemek: yemek,
    );
  }

  static List<String> _discoverAlongCities({
    required RotaDataState data,
    required List<LatLng> polyline,
    required String startKey,
    required String endKey,
    required List<String> userMid,
  }) {
    final samples = _samplePolyline(polyline, maxPoints: 180);
    if (samples.length < 2) {
      return [
        for (final c in userMid)
          if (c.toLowerCase() != startKey && c.toLowerCase() != endKey) c,
      ];
    }

    final startPt = firstMisafirhaneForIl(data, startKey);
    final endPt = firstMisafirhaneForIl(data, endKey);
    final startLl = startPt == null
        ? null
        : LatLng(startPt.latitude, startPt.longitude);
    final endLl =
        endPt == null ? null : LatLng(endPt.latitude, endPt.longitude);

    const distance = Distance();
    final cityKeys = <String>{};
    final kaynak = MainMapSearch.tesisKaynagiArama(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    for (final m in kaynak) {
      final il = m.il.trim();
      if (il.isEmpty) continue;
      cityKeys.add(il);
    }

    final hits = <_CityAnchor>[];
    for (final city in cityKeys) {
      final key = city.toLowerCase();
      if (key == startKey || key == endKey) continue;
      final m = firstMisafirhaneForIl(data, city);
      if (m == null) continue;
      final pt = LatLng(m.latitude, m.longitude);
      if (!isValidWgs84LatLng(pt.latitude, pt.longitude)) continue;

      if (startLl != null &&
          distance.as(LengthUnit.Kilometer, pt, startLl) < excludeEndsKm) {
        continue;
      }
      if (endLl != null &&
          distance.as(LengthUnit.Kilometer, pt, endLl) < excludeEndsKm) {
        continue;
      }

      final nearest = _nearestOnPolyline(pt, samples, distance);
      if (nearest.distKm > corridorKm) continue;
      hits.add(
        _CityAnchor(
          city: city,
          point: pt,
          progress: nearest.progress,
          distM: nearest.distKm * 1000,
        ),
      );
    }

    hits.sort((a, b) {
      final p = a.progress.compareTo(b.progress);
      if (p != 0) return p;
      return a.distM.compareTo(b.distM);
    });

    // Aynı ilerleme bandındaki yakın illerde daha yakındakini tut.
    final ordered = <_CityAnchor>[];
    for (final h in hits) {
      if (ordered.isEmpty) {
        ordered.add(h);
        continue;
      }
      final prev = ordered.last;
      if ((h.progress - prev.progress).abs() < 0.02 &&
          distance.as(LengthUnit.Kilometer, h.point, prev.point) < 28) {
        // Daha rotaya yakın olan kalsın.
        if (h.distM < prev.distM) {
          ordered[ordered.length - 1] = h;
        }
        continue;
      }
      ordered.add(h);
    }

    final orderedNames = ordered.map((e) => e.city).toList();

    for (final mid in userMid) {
      final k = mid.toLowerCase();
      if (k == startKey || k == endKey) continue;
      if (orderedNames.any((c) => c.toLowerCase() == k)) continue;
      final m = firstMisafirhaneForIl(data, mid);
      var insertAt = orderedNames.length;
      if (m != null && samples.isNotEmpty) {
        final pt = LatLng(m.latitude, m.longitude);
        final nearest = _nearestOnPolyline(pt, samples, distance);
        insertAt = 0;
        for (var i = 0; i < ordered.length; i++) {
          if (nearest.progress < ordered[i].progress) {
            insertAt = i;
            break;
          }
          insertAt = i + 1;
        }
      }
      orderedNames.insert(insertAt.clamp(0, orderedNames.length), mid);
    }

    return orderedNames;
  }

  static ({double distKm, double progress}) _nearestOnPolyline(
    LatLng point,
    List<LatLng> samples,
    Distance distance,
  ) {
    var bestD = double.infinity;
    var bestIdx = 0;
    for (var i = 0; i < samples.length; i++) {
      final d = distance.as(LengthUnit.Kilometer, point, samples[i]);
      if (d < bestD) {
        bestD = d;
        bestIdx = i;
      }
    }
    // Komşu segmentlere de bak (daha doğru koridor).
    for (var i = 0; i < samples.length - 1; i++) {
      final d = _distToSegmentKm(point, samples[i], samples[i + 1], distance);
      if (d < bestD) {
        bestD = d;
        bestIdx = i;
      }
    }
    final progress = samples.length <= 1
        ? 0.0
        : bestIdx / (samples.length - 1);
    return (distKm: bestD, progress: progress);
  }

  static double _distToSegmentKm(
    LatLng p,
    LatLng a,
    LatLng b,
    Distance distance,
  ) {
    final ab = distance.as(LengthUnit.Meter, a, b);
    if (ab < 1) return distance.as(LengthUnit.Kilometer, p, a);
    // Basit projeksiyon (küçük mesafelerde yeterli).
    final apx = p.longitude - a.longitude;
    final apy = p.latitude - a.latitude;
    final abx = b.longitude - a.longitude;
    final aby = b.latitude - a.latitude;
    final ab2 = abx * abx + aby * aby;
    if (ab2 <= 0) return distance.as(LengthUnit.Kilometer, p, a);
    var t = (apx * abx + apy * aby) / ab2;
    t = t.clamp(0.0, 1.0);
    final proj = LatLng(a.latitude + t * aby, a.longitude + t * abx);
    return distance.as(LengthUnit.Kilometer, p, proj);
  }

  static List<LatLng> _samplePolyline(List<LatLng> polyline, {required int maxPoints}) {
    final valid = onlyValidLatLngs(polyline);
    if (valid.length <= maxPoints) return valid;
    final out = <LatLng>[];
    final step = (valid.length - 1) / (maxPoints - 1);
    for (var i = 0; i < maxPoints; i++) {
      final idx = (i * step).round().clamp(0, valid.length - 1);
      out.add(valid[idx]);
    }
    return out;
  }

  static List<GeziYemekItem> _uniqueByName(Iterable<GeziYemekItem> items) {
    final seen = <String>{};
    final out = <GeziYemekItem>[];
    for (final g in items) {
      final k = g.isim.trim().toLowerCase();
      if (k.isEmpty || !seen.add(k)) continue;
      out.add(g);
    }
    return out;
  }
}
