import 'package:latlong2/latlong.dart';

import '../models/misafirhane.dart';
import '../data/firebase_rota_repository.dart' show RotaDataState;
import '../utils/main_map_search.dart';
import '../utils/safe_map_coordinates.dart';
import '../utils/search_normalize.dart';

/// Hava durumu sorgusu için konum kaynağı.
enum WeatherLocationSource {
  gps('Konumunuz'),
  cachedGps('Son konumunuz'),
  mapCity('Haritadaki il'),
  mapCenter('Harita merkezi'),
  defaultCity('Ankara');

  const WeatherLocationSource(this.label);
  final String label;
}

class WeatherLocationTarget {
  const WeatherLocationTarget({
    required this.latitude,
    required this.longitude,
    required this.source,
    this.displayName,
  });

  final double latitude;
  final double longitude;
  final WeatherLocationSource source;
  final String? displayName;

  LatLng get latLng => LatLng(latitude, longitude);
}

/// GPS yokken sırayla: önbellek → odak il → harita merkezi → Ankara.
abstract final class WeatherLocationResolver {
  static const _defaultAnkara = LatLng(39.9334, 32.8597);

  static WeatherLocationTarget resolve({
    LatLng? liveGps,
    LatLng? cachedGps,
    String? focusedCity,
    LatLng? mapCenter,
    RotaDataState? rotaData,
  }) {
    if (liveGps != null && isValidWgs84LatLng(liveGps.latitude, liveGps.longitude)) {
      return WeatherLocationTarget(
        latitude: liveGps.latitude,
        longitude: liveGps.longitude,
        source: WeatherLocationSource.gps,
      );
    }

    if (cachedGps != null && isValidWgs84LatLng(cachedGps.latitude, cachedGps.longitude)) {
      return WeatherLocationTarget(
        latitude: cachedGps.latitude,
        longitude: cachedGps.longitude,
        source: WeatherLocationSource.cachedGps,
      );
    }

    final city = focusedCity?.trim();
    if (city != null && city.isNotEmpty) {
      final cityLl = _coordsForCity(rotaData, city);
      if (cityLl != null) {
        return WeatherLocationTarget(
          latitude: cityLl.latitude,
          longitude: cityLl.longitude,
          source: WeatherLocationSource.mapCity,
          displayName: city,
        );
      }
    }

    if (mapCenter != null && isValidWgs84LatLng(mapCenter.latitude, mapCenter.longitude)) {
      return WeatherLocationTarget(
        latitude: mapCenter.latitude,
        longitude: mapCenter.longitude,
        source: WeatherLocationSource.mapCenter,
      );
    }

    return WeatherLocationTarget(
      latitude: _defaultAnkara.latitude,
      longitude: _defaultAnkara.longitude,
      source: WeatherLocationSource.defaultCity,
      displayName: 'Ankara',
    );
  }

  static LatLng? _coordsForCity(RotaDataState? data, String city) {
    if (data == null) return null;
    final key = normalizeForSearch(city);
    final facilities = MainMapSearch.tesisKaynagiArama(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    Misafirhane? best;
    for (final m in facilities) {
      if (normalizeForSearch(m.il) != key) continue;
      if (!isValidWgs84LatLng(m.latitude, m.longitude)) continue;
      if (best == null) {
        best = m;
        continue;
      }
      final bestBad = best.latitude == 0 || best.longitude == 0;
      final curGood = m.latitude != 0 && m.longitude != 0;
      if (bestBad && curGood) best = m;
    }
    if (best == null) return null;
    return LatLng(best.latitude, best.longitude);
  }
}
