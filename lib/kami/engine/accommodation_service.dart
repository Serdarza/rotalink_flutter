import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import '../../models/misafirhane.dart';
import '../../utils/geo_helpers.dart';
import '../../utils/safe_map_coordinates.dart';
import 'city_resolver.dart';

/// Kamu misafirhaneleri — yalnızca RTDB tesis listesi.
class KamiAccommodationService {
  const KamiAccommodationService();

  /// İl tesisleri. [user] varsa konuma göre yakından uzağa sıralar.
  List<Misafirhane> byCity(
    RotaDataState data,
    String city, {
    int limit = 20,
    LatLng? user,
  }) {
    final src = data.aramaIcinTumTesisler.isNotEmpty
        ? data.aramaIcinTumTesisler
        : data.misafirhaneler;
    var list =
        src.where((m) => KamiCityResolver.sameCity(m.il, city)).toList();

    if (user != null) {
      final withCoords = list
          .where(
            (m) =>
                m.latitude != 0 &&
                m.longitude != 0 &&
                isValidWgs84LatLng(m.latitude, m.longitude),
          )
          .toList();
      final withoutCoords = list
          .where(
            (m) =>
                m.latitude == 0 ||
                m.longitude == 0 ||
                !isValidWgs84LatLng(m.latitude, m.longitude),
          )
          .toList();
      list = [
        ...sortMisafirhaneByDistance(withCoords, user),
        ...withoutCoords,
      ];
    }

    if (list.length <= limit) return list;
    return list.sublist(0, limit);
  }

  /// Kullanıcı konumuna [maxKm] km içindeki tesisler, yakından uzağa.
  List<Misafirhane> nearby(
    RotaDataState data,
    LatLng user, {
    int limit = 30,
    double maxKm = 50,
  }) {
    final src = data.aramaIcinTumTesisler.isNotEmpty
        ? data.aramaIcinTumTesisler
        : data.misafirhaneler;
    const distance = Distance();
    final maxM = maxKm * 1000;

    final within = <({Misafirhane m, double meters})>[];
    for (final m in src) {
      if (m.latitude == 0 || m.longitude == 0) continue;
      if (!isValidWgs84LatLng(m.latitude, m.longitude)) continue;
      final meters = distance.as(
        LengthUnit.Meter,
        user,
        LatLng(m.latitude, m.longitude),
      );
      if (!meters.isFinite || meters > maxM) continue;
      within.add((m: m, meters: meters));
    }

    within.sort((a, b) => a.meters.compareTo(b.meters));
    final sorted = [for (final e in within) e.m];
    if (sorted.length <= limit) return sorted;
    return sorted.sublist(0, limit);
  }
}
