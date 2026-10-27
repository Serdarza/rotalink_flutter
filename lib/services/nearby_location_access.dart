import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'simple_location_service.dart';

/// One-shot location access: no listener, persistence or background tracking.
class NearbyLocationAccess {
  const NearbyLocationAccess();
  static Position? _recentPosition;
  static Future<Position>? _inFlight;
  static Future<PermissionRequestOutcome>? _permissionRequest;

  /// Only a recent, reasonably accurate fix can provide the initial list.
  /// Kept in memory; never written to an application database.
  static bool isRecent(Position? position, {DateTime? now}) {
    if (position == null || !hasValidCoordinates(position)) return false;
    final age = (now ?? DateTime.now()).difference(position.timestamp);
    return !age.isNegative &&
        age <= const Duration(minutes: 2) &&
        position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        position.accuracy <= 1000;
  }

  static bool hasValidCoordinates(Position position) =>
      position.latitude.isFinite &&
      position.longitude.isFinite &&
      position.latitude.abs() <= 90 &&
      position.longitude.abs() <= 180 &&
      position.latitude != 0 &&
      position.longitude != 0;

  Future<Position?> lastKnownPosition() async {
    if (isRecent(_recentPosition)) return _recentPosition;
    // The browser does not expose an OS last-known location.
    if (kIsWeb) return null;
    try {
      final position = await Geolocator.getLastKnownPosition().timeout(
        const Duration(milliseconds: 600),
      );
      if (!isRecent(position)) return null;
      return _recentPosition = position;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isEnabled() => Geolocator.isLocationServiceEnabled();
  Future<bool> isGranted() => SimpleLocationService.isLocationGranted();
  Future<PermissionRequestOutcome> requestPermission() => _permissionRequest ??=
      _requestPermission().whenComplete(() => _permissionRequest = null);

  Future<PermissionRequestOutcome> _requestPermission() async {
    if (!kIsWeb) return SimpleLocationService.requestFromUserTap();
    // The web plugin's requestPermission waits for an unbounded GPS request.
    // A bounded position request both requests permission and returns the fix.
    try {
      await _requestCurrentPosition();
      return PermissionRequestOutcome.granted;
    } on PermissionDeniedException {
      final permission = await Geolocator.checkPermission().timeout(
        const Duration(seconds: 3),
      );
      return permission == LocationPermission.deniedForever
          ? PermissionRequestOutcome.deniedForever
          : PermissionRequestOutcome.denied;
    }
  }

  Future<Position> currentPosition() {
    final recent = _recentPosition;
    if (kIsWeb &&
        isRecent(recent) &&
        DateTime.now().difference(recent!.timestamp) <
            const Duration(seconds: 2)) {
      return Future.value(recent);
    }
    return _requestCurrentPosition();
  }

  Future<Position> _requestCurrentPosition() => _inFlight ??=
      Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          )
          .timeout(const Duration(seconds: 8))
          .then((position) {
            if (hasValidCoordinates(position)) _recentPosition = position;
            return position;
          })
          .whenComplete(() => _inFlight = null);

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
