import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Ana harita mesafe satırları için paylaşılan konum + izin durumu ([ChangeNotifier]).
/// [showBottomSheet] overlay’i üst widget [setState] ile her zaman güncellenmediğinden dinlenir.
class MapLocationState extends ChangeNotifier {
  LatLng? userLocation;
  bool locationPermissionGranted = false;

  void update(LatLng? user, bool granted) {
    final sameUser = userLocation?.latitude == user?.latitude &&
        userLocation?.longitude == user?.longitude;
    if (sameUser && locationPermissionGranted == granted) return;
    userLocation = user;
    locationPermissionGranted = granted;
    notifyListeners();
  }
}
