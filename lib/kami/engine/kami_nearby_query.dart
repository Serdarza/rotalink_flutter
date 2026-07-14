import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import '../../models/gezi_yemek_item.dart';
import '../../models/misafirhane.dart';
import '../../models/sosyal_item.dart';
import '../../utils/safe_map_coordinates.dart';
import 'city_resolver.dart';
import 'fuzzy_search.dart';
import 'kami_constants.dart';
import 'kami_models.dart';
import 'kami_neighbor_region.dart';

/// Konum + çıkış ili komşuluk bölgesinde veritabanı sorguları.
abstract final class KamiNearbyQuery {
  static final Distance _distance = const Distance();

  static double? distanceMeters(LatLng user, double? lat, double? lon) {
    if (lat == null || lon == null || lat == 0 || lon == 0) return null;
    if (!isValidWgs84LatLng(lat, lon)) return null;
    return _distance.as(LengthUnit.Meter, user, LatLng(lat, lon));
  }

  static bool _inRegion(String homeCity, String itemIl) {
    return KamiNeighborRegion.isInRegion(homeCity, itemIl);
  }

  static List<Misafirhane> facilities(
    RotaDataState data,
    LatLng user, {
    required String homeCity,
    int limit = KamiConstants.nearbyResultLimit,
  }) {
    final src = data.aramaIcinTumTesisler.isNotEmpty
        ? data.aramaIcinTumTesisler
        : data.misafirhaneler;
    final hits = <({Misafirhane item, double meters})>[];
    for (final m in src) {
      if (!_inRegion(homeCity, m.il)) continue;
      final meters = distanceMeters(user, m.latitude, m.longitude) ??
          (KamiCityResolver.sameCity(m.il, homeCity) ? 0.0 : double.infinity);
      if (!meters.isFinite) continue;
      hits.add((item: m, meters: meters));
    }
    hits.sort((a, b) => a.meters.compareTo(b.meters));
    final out = [for (final h in hits) h.item];
    if (out.length <= limit) return out;
    return out.sublist(0, limit);
  }

  static List<GeziYemekItem> gezi(
    RotaDataState data,
    LatLng user, {
    required String homeCity,
    int limit = KamiConstants.nearbyResultLimit,
  }) {
    final hits = <({GeziYemekItem item, double meters})>[];
    for (final g in data.gezi) {
      if (!_inRegion(homeCity, g.il)) continue;
      final meters = distanceMeters(user, g.enlem, g.boylam) ??
          (KamiCityResolver.sameCity(g.il, homeCity) ? 0.0 : double.infinity);
      if (!meters.isFinite) continue;
      hits.add((item: g, meters: meters));
    }
    hits.sort((a, b) => a.meters.compareTo(b.meters));
    final out = [for (final h in hits) h.item];
    if (out.length <= limit) return out;
    return out.sublist(0, limit);
  }

  static List<GeziYemekItem> yemek(
    RotaDataState data,
    LatLng user, {
    required String homeCity,
    int limit = KamiConstants.nearbyResultLimit,
  }) {
    final hits = <({GeziYemekItem item, double meters})>[];
    for (final y in data.yemek) {
      if (!_inRegion(homeCity, y.il)) continue;
      final meters = distanceMeters(user, y.enlem, y.boylam) ??
          (KamiCityResolver.sameCity(y.il, homeCity) ? 0.0 : double.infinity);
      if (!meters.isFinite) continue;
      hits.add((item: y, meters: meters));
    }
    hits.sort((a, b) => a.meters.compareTo(b.meters));
    final out = [for (final h in hits) h.item];
    if (out.length <= limit) return out;
    return out.sublist(0, limit);
  }

  static List<SosyalItem> sosyal(
    RotaDataState data,
    LatLng user, {
    required String homeCity,
    int limit = KamiConstants.nearbyResultLimit,
  }) {
    final hits = <({SosyalItem item, double meters})>[];
    for (final s in data.sosyal) {
      if (!_inRegion(homeCity, s.il)) continue;
      final meters = distanceMeters(user, s.enlem, s.boylam) ??
          (KamiCityResolver.sameCity(s.il, homeCity) ? 0.0 : double.infinity);
      if (!meters.isFinite) continue;
      hits.add((item: s, meters: meters));
    }
    hits.sort((a, b) => a.meters.compareTo(b.meters));
    final out = [for (final h in hits) h.item];
    if (out.length <= limit) return out;
    return out.sublist(0, limit);
  }

  /// Yakınımdaki — çıkış ili + komşu iller (sistem yönergesi kural 2–3).
  static KamiPayload exploreNearby({
    required RotaDataState data,
    required LatLng user,
    required String homeCity,
  }) {
    final facilityList = facilities(data, user, homeCity: homeCity);
    final geziList = gezi(data, user, homeCity: homeCity);
    final yemekList = yemek(data, user, homeCity: homeCity);
    final sosyalList = sosyal(data, user, homeCity: homeCity);

    final total = facilityList.length +
        geziList.length +
        yemekList.length +
        sosyalList.length;

    if (total == 0) {
      return KamiPayload(
        intent: KamiIntentType.nearbyExplore,
        title: '$homeCity çevresi — Yakındaki öneriler',
        emptyReason:
            '$homeCity ve komşu illerde kayıt bulunamadı. Farklı bir çıkış ili yazabilirsiniz.',
        userLocation: user,
        cities: [homeCity],
      );
    }

    final parts = <String>[];
    if (facilityList.isNotEmpty) parts.add('${facilityList.length} tesis');
    if (geziList.isNotEmpty) parts.add('${geziList.length} gezi');
    if (yemekList.isNotEmpty) parts.add('${yemekList.length} yemek');
    if (sosyalList.isNotEmpty) parts.add('${sosyalList.length} belediye');

    return KamiPayload(
      intent: KamiIntentType.nearbyExplore,
      title: '$homeCity çevresi — Yakındaki öneriler',
      subtitle: '${KamiNeighborRegion.regionalSubtitle(homeCity: homeCity, totalCount: total)} · ${parts.join(' · ')}',
      cities: [homeCity],
      facilities: facilityList,
      gezi: geziList,
      yemek: yemekList,
      sosyal: sosyalList,
      userLocation: user,
    );
  }

  /// İl + konu (tarih, doğa vb.) ile gezi filtreleme.
  static List<GeziYemekItem> filterGeziTopic(
    List<GeziYemekItem> items, {
    bool history = false,
    String? queryNorm,
  }) {
    if (items.isEmpty) return items;

    final keys = <String>{};
    if (history) {
      keys.addAll(const [
        'tarih',
        'tarihi',
        'muze',
        'müze',
        'anit',
        'anıt',
        'kale',
        'cami',
        'antik',
        'osmanli',
        'selcuk',
        'arkeoloji',
        'kultur',
        'kültür',
      ]);
    }
    if (queryNorm != null && queryNorm.trim().isNotEmpty) {
      for (final t in queryNorm.split(RegExp(r'\s+'))) {
        if (t.length >= 3) keys.add(t);
      }
    }
    if (keys.isEmpty) return items;

    final filtered = items.where((g) {
      final h = KamiFuzzySearch.norm('${g.isim} ${g.aciklama} ${g.adres}');
      for (final k in keys) {
        if (h.contains(k)) return true;
      }
      return false;
    }).toList();

    return filtered.isNotEmpty ? filtered : items;
  }
}
