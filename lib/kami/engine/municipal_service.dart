import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import '../../models/sosyal_item.dart';
import '../../utils/safe_map_coordinates.dart';
import '../recommendation/city_neighbors.dart';
import '../recommendation/distance_service.dart';
import '../recommendation/province_centers.dart';
import 'city_resolver.dart';
import 'fuzzy_search.dart';

/// Belediye sosyal tesisleri — yalnızca RTDB `sosyal`.
class KamiMunicipalService {
  const KamiMunicipalService();

  static final Distance _distance = const Distance();

  List<SosyalItem> byCity(RotaDataState data, String city, {int limit = 12}) {
    final list = data.sosyal
        .where((s) => KamiCityResolver.sameCity(s.il, city))
        .toList();
    if (list.length <= limit) return list;
    return list.sublist(0, limit);
  }

  /// Bulunulan il + komşu illerdeki belediye tesisleri (hatalı koordinat filtresi).
  List<SosyalItem> forHomeRegion({
    required RotaDataState data,
    required LatLng user,
    required String homeCity,
    int limit = 15,
    double maxItemKm = 100,
  }) {
    final ring = <String>{homeCity, ...KamiCityNeighbors.neighborsOf(homeCity)};
    final candidates = <SosyalItem>[];
    for (final c in ring) {
      candidates.addAll(byCity(data, c, limit: 40));
    }

    final seen = <String>{};
    final filtered = <SosyalItem>[];
    for (final s in candidates) {
      final key =
          '${KamiCityResolver.normalize(s.il)}\x01${KamiFuzzySearch.norm(s.isim)}';
      if (!seen.add(key)) continue;
      if (!_plausibleNearUser(s, user, homeCity, maxItemKm)) continue;
      filtered.add(s);
    }

    filtered.sort((a, b) {
      final da = _itemDist(user, a);
      final db = _itemDist(user, b);
      return da.compareTo(db);
    });

    if (filtered.length <= limit) return filtered;
    return filtered.sublist(0, limit);
  }

  static bool _plausibleNearUser(
    SosyalItem s,
    LatLng user,
    String homeCity,
    double maxItemKm,
  ) {
    final inRing = KamiCityResolver.sameCity(s.il, homeCity) ||
        KamiCityNeighbors.isNeighbor(homeCity, s.il);
    if (!inRing) return false;

    final distKm = _itemDist(user, s) / 1000.0;
    if (!distKm.isFinite) return true;

    if (distKm <= maxItemKm) return true;

    final cityCenter = KamiProvinceCenters.centerFor(s.il);
    if (cityCenter == null) return false;
    final cityDist = KamiDistanceService.kmBetween(user, cityCenter);
    return cityDist <= maxItemKm + 40;
  }

  static double _itemDist(LatLng user, SosyalItem s) {
    final e = s.enlem;
    final b = s.boylam;
    if (e == null ||
        b == null ||
        e == 0 ||
        b == 0 ||
        !isValidWgs84LatLng(e, b)) {
      return double.infinity;
    }
    return _distance.as(LengthUnit.Meter, user, LatLng(e, b));
  }
}
