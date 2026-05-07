import 'package:latlong2/latlong.dart';

import '../models/misafirhane.dart';
import 'safe_map_coordinates.dart';

/// Konum izni yokken mesafe satırı — kullanıcı dokunarak izin isteyebilir.
const String kDistancePermissionNeededLabel = 'Size uzaklık: Konum izni vermeniz gereklidir';

/// Tesis koordinatı (Nominatim) henüz yok; kullanıcı konumu var, mesafe bekleniyor.
const String kDistanceFacilityPendingLabel = 'Size uzaklık: Yer bilgisi yükleniyor…';

/// İzin var ama konum alınamadı (GPS kapalı, zaman aşımı vb.) — dokunarak yeniden denenebilir.
const String kDistanceRetryLabel = 'Size uzaklık: Konum alınamadı, tekrar için dokun';

/// İzin eksikliği veya konum yenilemesi gereken her iki durum için tıklanabilir etiket mi?
bool isDistancePermissionNeededLabel(String? dist) => dist == kDistancePermissionNeededLabel;
bool isDistanceTapLabel(String? dist) =>
    dist == kDistancePermissionNeededLabel || dist == kDistanceRetryLabel;

/// İzin yok / kalıcı red veya kullanıcı konumu yoksa [kDistancePermissionNeededLabel]; aksi halde gerçek mesafe veya null.
String? resolveDistanceRowText({
  required LatLng? userLocation,
  required double facilityLat,
  required double facilityLon,
  required bool locationPermissionGranted,
}) {
  if (facilityLat == 0 && facilityLon == 0) return null;
  if (!isValidWgs84LatLng(facilityLat, facilityLon)) return null;
  final real = formatDistanceChipText(userLocation, facilityLat, facilityLon);
  if (real != null) return real;
  if (!locationPermissionGranted) {
    return kDistancePermissionNeededLabel;
  }
  // İzin verilmiş ama konum yok (GPS kapalı, zaman aşımı vb.) — chip kaybolmasın, dokunarak yeniden denenebilsin.
  return kDistanceRetryLabel;
}

/// Gezi / Yemek / Sosyal: koordinat henüz yok veya geocode bekleniyorken de izin satırı gösterilir.
String? resolveDistanceRowTextWithOptionalFacility({
  required LatLng? userLocation,
  required bool locationPermissionGranted,
  LatLng? facility,
}) {
  if (facility != null &&
      !(facility.latitude == 0 && facility.longitude == 0) &&
      isValidWgs84LatLng(facility.latitude, facility.longitude)) {
    return resolveDistanceRowText(
      userLocation: userLocation,
      facilityLat: facility.latitude,
      facilityLon: facility.longitude,
      locationPermissionGranted: locationPermissionGranted,
    );
  }
  if (!locationPermissionGranted) {
    return kDistancePermissionNeededLabel;
  }
  final userOk = userLocation != null &&
      isValidWgs84LatLng(userLocation.latitude, userLocation.longitude);
  // İzin var ama kullanıcı konumu yok — chip kaybolmasın, tıklanabilir kalabilsin.
  if (!userOk) return kDistanceRetryLabel;
  return kDistanceFacilityPendingLabel;
}

/// Kotlin [MisafirhaneAdapter] / [MisafirhaneBottomSheet] mesafe metni.
String? formatDistanceChipText(LatLng? user, double lat, double lon) {
  if (user == null) return null;
  if (lat == 0 && lon == 0) return null;
  if (!isValidWgs84LatLng(lat, lon)) return null;
  if (!isValidWgs84LatLng(user.latitude, user.longitude)) return null;
  const d = Distance();
  final m = d.as(LengthUnit.Meter, user, LatLng(lat, lon));
  if (!m.isFinite) return null;
  if (m < 1000) return 'Size uzaklık: ${m.round()} m';
  return 'Size uzaklık: ${(m / 1000).toStringAsFixed(1)} km';
}

/// Konum yok ama kullanıcıya mesafe alanı göstermek için (oturumda red / bilinmiyor).
String? formatDistanceChipTextWithPlaceholder(
  LatLng? user,
  double lat,
  double lon, {
  bool showUnknownPlaceholder = false,
}) {
  final t = formatDistanceChipText(user, lat, lon);
  if (t != null) return t;
  if (showUnknownPlaceholder && (lat != 0 || lon != 0)) {
    return kDistancePermissionNeededLabel;
  }
  return null;
}

List<Misafirhane> sortMisafirhaneByDistance(List<Misafirhane> list, LatLng? user) {
  if (user == null) return List<Misafirhane>.from(list);
  const d = Distance();
  final out = List<Misafirhane>.from(list);
  out.sort((a, b) {
    double distTo(Misafirhane x) {
      if (x.latitude == 0 && x.longitude == 0) return double.infinity;
      if (!isValidWgs84LatLng(x.latitude, x.longitude)) return double.infinity;
      final v = d.as(LengthUnit.Meter, user, LatLng(x.latitude, x.longitude));
      return v.isFinite ? v : double.infinity;
    }

    return distTo(a).compareTo(distTo(b));
  });
  return out;
}

double distanceMetersGezi(LatLng? user, double? enlem, double? boylam) {
  if (user == null || enlem == null || boylam == null) return double.infinity;
  if (!isValidWgs84LatLng(enlem, boylam)) return double.infinity;
  if (!isValidWgs84LatLng(user.latitude, user.longitude)) return double.infinity;
  const d = Distance();
  final m = d.as(LengthUnit.Meter, user, LatLng(enlem, boylam));
  return m.isFinite ? m : double.infinity;
}

/// OSRM [distance] metre → kısa metin (Kotlin rota etiketi ile uyumlu).
String formatRouteDistanceMeters(double m) {
  if (!m.isFinite || m <= 0) return '—';
  if (m < 1000) return '${m.round()} m';
  return '${(m / 1000).toStringAsFixed(1)} km';
}

/// OSRM [duration] saniye → sürüş süresi özeti.
String formatRouteDurationSeconds(double sec) {
  if (!sec.isFinite || sec <= 0) return '—';
  final h = (sec / 3600).floor();
  final min = ((sec % 3600) / 60).floor();
  if (h > 0) return '$h sa $min dk';
  if (min < 1) return '<1 dk';
  return '$min dk';
}
