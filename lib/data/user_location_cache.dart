import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/safe_map_coordinates.dart';

/// Son başarılı GPS okuması — uygulama yeniden açıldığında [Geolocator] çağrılmadan mesafe satırları için.
class UserLocationCache {
  UserLocationCache._();

  static const _kLat = 'rotalink_cached_user_lat';
  static const _kLon = 'rotalink_cached_user_lon';

  static Future<void> save(LatLng ll) async {
    if (!isValidWgs84LatLng(ll.latitude, ll.longitude)) return;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kLat, ll.latitude);
    await p.setDouble(_kLon, ll.longitude);
  }

  static Future<LatLng?> load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final lat = p.getDouble(_kLat);
    final lon = p.getDouble(_kLon);
    if (lat == null || lon == null) return null;
    if (!isValidWgs84LatLng(lat, lon)) return null;
    return LatLng(lat, lon);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kLat);
    await p.remove(_kLon);
  }
}
