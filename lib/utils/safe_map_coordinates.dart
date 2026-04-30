import 'package:latlong2/latlong.dart';

/// Geçersiz koordinat durumunda harita kamerası için güvenli yedek (Türkiye merkezi).
const LatLng kTurkeyMapFallbackCenter = LatLng(39.92, 32.85);

const double kTurkeyMapFallbackZoom = 5.05;

bool isValidWgs84LatLng(double lat, double lon) {
  if (!lat.isFinite || !lon.isFinite) return false;
  if (lat < -90.0 || lat > 90.0) return false;
  if (lon < -180.0 || lon > 180.0) return false;
  return true;
}

/// Geçersiz [lat]/[lon] için [fallback] döner (varsayılan Türkiye merkezi).
LatLng latLngOrFallback(
  double lat,
  double lon, {
  LatLng fallback = kTurkeyMapFallbackCenter,
}) {
  return isValidWgs84LatLng(lat, lon) ? LatLng(lat, lon) : fallback;
}

LatLng sanitizeLatLng(
  LatLng p, {
  LatLng fallback = kTurkeyMapFallbackCenter,
}) {
  return latLngOrFallback(p.latitude, p.longitude, fallback: fallback);
}

/// Polyline / fitBounds için yalnızca geçerli noktalar (NaN sonsuz düşmez).
List<LatLng> onlyValidLatLngs(Iterable<LatLng> input) {
  return input.where((p) => isValidWgs84LatLng(p.latitude, p.longitude)).toList();
}

double clampZoom(double zoom, {double min = 2.0, double max = 18.0}) {
  if (!zoom.isFinite) return kTurkeyMapFallbackZoom;
  return zoom.clamp(min, max);
}
