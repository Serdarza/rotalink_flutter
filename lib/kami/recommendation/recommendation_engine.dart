import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import '../engine/city_resolver.dart';
import 'city_neighbors.dart';
import 'distance_service.dart';
import 'province_centers.dart';
import 'trip_score_service.dart';

/// İl skorlama + filtre + top-N öneri motoru.
///
/// Öncelik: komşu iller → yakın halka → uzak halka.
/// İçerik skoru aynı mesafe bandında sıralama için kullanılır;
/// uzak ama zengin iller (Ankara/Hatay) yakındakilerin önüne geçmez.
abstract final class KamiRecommendationEngine {
  static const int defaultTopN = 5;

  /// Hafta sonu için makul sürüş üst sınırı.
  static const double defaultMaxKm = 200;

  /// 1. halka: çevre / kısa mesafe.
  static const double nearRingKm = 140;

  static List<KamiCityScore> recommend({
    required RotaDataState data,
    required LatLng user,
    Set<KamiTripFilter> filters = const {},
    int topN = defaultTopN,
    double maxKm = defaultMaxKm,
  }) {
    final centroids = KamiDistanceService.mergedCentroids(data);
    if (centroids.isEmpty) return const [];

    final home = KamiDistanceService.resolveHomeCity(user, data);
    final neighborNames = home == null
        ? <String>{}
        : KamiCityNeighbors.neighborsOf(home);

    // Halkaları doldurmak için biraz daha geniş tarayabiliriz; seçim yine mesafeyi önde tutar.
    final scanKm = maxKm < 250 ? 250.0 : maxKm;
    final nearby = KamiDistanceService.citiesWithin(
      user: user,
      centroids: centroids,
      excludeCity: home,
      maxKm: scanKm,
    );

    final scored = <KamiCityScore>[];
    for (final c in nearby) {
      final s = KamiTripScoreService.scoreCity(
        data: data,
        city: c.city,
        distanceKm: c.km,
      );
      if (s.geziCount + s.yemekCount + s.sosyalCount + s.facilityCount == 0) {
        continue;
      }
      scored.add(s);
    }

    var list = scored;
    if (filters.isNotEmpty) {
      list = list
          .where(
            (s) => filters.every(
              (f) => KamiTripScoreService.matchesFilter(s, f),
            ),
          )
          .toList();
    }
    if (list.isEmpty) return const [];

    final neighborSet = {
      for (final n in neighborNames) KamiCityResolver.normalize(n),
    };

    int tierOf(KamiCityScore s) {
      final isNeighbor =
          neighborSet.contains(KamiCityResolver.normalize(s.city));
      if (isNeighbor && s.distanceKm <= maxKm + 40) return 0;
      if (s.distanceKm <= nearRingKm) return 1;
      if (s.distanceKm <= maxKm) return 2;
      return 3;
    }

    list.sort((a, b) {
      final ta = tierOf(a);
      final tb = tierOf(b);
      if (ta != tb) return ta.compareTo(tb);
      // Aynı halkada önce yakın olan
      final byDist = a.distanceKm.compareTo(b.distanceKm);
      if (byDist != 0) return byDist;
      return b.score.compareTo(a.score);
    });

    // Soft max: üst sınırı aşanlar (tier 3) yalnızca liste yetmezse
    final preferred = list.where((s) => tierOf(s) <= 2).toList();
    final fallback = list.where((s) => tierOf(s) == 3).toList();
    final out = <KamiCityScore>[
      ...preferred,
      if (preferred.length < topN) ...fallback,
    ];

    if (out.length <= topN) return out;
    return out.sublist(0, topN);
  }

  /// Bulunulan ilin yalnızca kara sınırı komşuları (sistem yönergesi kural 2–3).
  static List<KamiCityScore> nearbyRouteDestinations({
    required RotaDataState data,
    required LatLng user,
    required String homeCity,
  }) {
    final centroids = KamiDistanceService.mergedCentroids(data);
    final neighbors = <KamiCityScore>[];

    for (final n in KamiCityNeighbors.neighborsOf(homeCity)) {
      final center = centroids[n] ??
          KamiProvinceCenters.centerFor(n) ??
          KamiDistanceService.centerForCity(n, data);
      if (center == null) continue;
      final km = KamiDistanceService.kmBetween(user, center);
      neighbors.add(
        KamiTripScoreService.scoreCity(
          data: data,
          city: n,
          distanceKm: km,
        ),
      );
    }

    neighbors.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return neighbors;
  }
}
