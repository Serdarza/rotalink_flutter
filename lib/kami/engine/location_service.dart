import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../data/user_location_cache.dart';
import '../../services/simple_location_service.dart';
import '../../utils/safe_map_coordinates.dart';

/// KAMİ konum okuma — mevcut izin akışını bozmaz; yalnızca okur / cache kullanır.
class KamiLocationService {
  const KamiLocationService();

  /// Kullanıcı sorusu (chip / gönder) — gerekirse izin ister, sonra GPS okur.
  Future<LatLng?> resolveForUserAction({LatLng? hint}) async {
    if (hint != null &&
        isValidWgs84LatLng(hint.latitude, hint.longitude)) {
      return hint;
    }

    if (await SimpleLocationService.isLocationGranted()) {
      return resolveUserLocation(hint: hint);
    }

    final cached = await UserLocationCache.load();
    if (cached != null &&
        isValidWgs84LatLng(cached.latitude, cached.longitude)) {
      return cached;
    }

    final granted = await SimpleLocationService.ensureLocationPermissionFromUserAction();
    if (!granted) return null;

    return resolveUserLocation(hint: hint);
  }

  /// İzin yoksa veya GPS alınamazsa `null`.
  Future<LatLng?> resolveUserLocation({LatLng? hint}) async {
    if (hint != null &&
        isValidWgs84LatLng(hint.latitude, hint.longitude)) {
      return hint;
    }

    final granted = await SimpleLocationService.isLocationGranted();
    if (!granted) {
      final cached = await UserLocationCache.load();
      if (cached != null &&
          isValidWgs84LatLng(cached.latitude, cached.longitude)) {
        return cached;
      }
      return null;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      if (isValidWgs84LatLng(ll.latitude, ll.longitude)) {
        await UserLocationCache.save(ll);
        return ll;
      }
    } catch (_) {
      final cached = await UserLocationCache.load();
      if (cached != null &&
          isValidWgs84LatLng(cached.latitude, cached.longitude)) {
        return cached;
      }
    }
    return null;
  }

  Future<bool> hasPermission() => SimpleLocationService.isLocationGranted();
}
