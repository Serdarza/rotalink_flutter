import 'package:latlong2/latlong.dart';

import '../data/firebase_rota_repository.dart';
import '../models/misafirhane.dart';
import '../models/route_stop.dart';
import 'safe_map_coordinates.dart';

/// Rota durak sırasına göre yalnızca [Misafirhane] öğeleri (konaklamalar).
List<Misafirhane> misafirhanelerInRouteOrder(List<RouteStop> stops) {
  final out = <Misafirhane>[];
  for (final s in stops) {
    for (final o in s.items) {
      if (o is Misafirhane) out.add(o);
    }
  }
  return out;
}

/// Kotlin [MainActivity] ile aynı: il için koordinatı olan ilk tesis.
Misafirhane? firstMisafirhaneForIl(RotaDataState data, String city) {
  final c = city.trim().toLowerCase();
  for (final m in data.aramaIcinTumTesisler) {
    if (m.il.trim().toLowerCase() == c &&
        m.latitude != 0 &&
        m.longitude != 0 &&
        isValidWgs84LatLng(m.latitude, m.longitude)) {
      return m;
    }
  }
  for (final m in data.misafirhaneler) {
    if (m.il.trim().toLowerCase() == c &&
        m.latitude != 0 &&
        m.longitude != 0 &&
        isValidWgs84LatLng(m.latitude, m.longitude)) {
      return m;
    }
  }
  return null;
}

List<LatLng> waypointsForRouteStops(RotaDataState data, List<RouteStop> stops) {
  final out = <LatLng>[];
  for (final s in stops) {
    final m = firstMisafirhaneForIl(data, s.city);
    if (m != null &&
        m.latitude != 0 &&
        m.longitude != 0 &&
        isValidWgs84LatLng(m.latitude, m.longitude)) {
      out.add(LatLng(m.latitude, m.longitude));
    }
  }
  return out;
}

/// Harita yönlendirmesi için [waypointsForRouteStops] ile aynı sıra ve filtre: il + misafirhane adı.
List<String> placeQueriesForRouteStops(RotaDataState data, List<RouteStop> stops) {
  final out = <String>[];
  for (final s in stops) {
    final m = firstMisafirhaneForIl(data, s.city);
    if (m != null && m.latitude != 0 && m.longitude != 0) {
      final il = m.il.trim();
      final isim = m.isim.trim();
      final q = il.isEmpty ? isim : (isim.isEmpty ? il : '$il $isim');
      if (q.isNotEmpty) out.add(q);
    }
  }
  return out;
}
