import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Kullanıcı tarafından tetiklenen izin isteğinin sonucu.
enum PermissionRequestOutcome {
  /// İzin verildi — mesafe hesaplamasına geç.
  granted,

  /// Kullanıcı izni reddetti.
  denied,

  /// Kalıcı red — sistem popup bir daha çıkmaz; ayarlar gerekir.
  deniedForever,
}

/// Konum izni yönetimi — tamamen oturum bazlı, yalnızca [Geolocator] kullanır.
///
/// iOS'ta hem [permission_handler] hem [geolocator] kullanmak iki ayrı
/// CLLocationManager oluşturur ve izin diyaloğunun sessizce iptal edilmesine
/// yol açar. Tüm konum izni işlemlerini [Geolocator] ile yapmak bu çakışmayı önler.
class SimpleLocationService {
  SimpleLocationService._();

  static bool _declinedThisSession = false;
  static bool _gpsUnavailableThisSession = false;
  static Future<PermissionRequestOutcome>? _inFlightRequest;

  static bool get shouldSuppressPlayServicesLocationActivity =>
      _gpsUnavailableThisSession;

  static void markSessionPlayServicesLocationPromptDeclined() =>
      _gpsUnavailableThisSession = true;

  static void clearSessionGpsSuppression() =>
      _gpsUnavailableThisSession = false;

  static Future<bool> isLocationGranted() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  static Future<bool> isLocationPermissionDeclinedByUser() async {
    if (await isLocationGranted()) return false;
    return _declinedThisSession;
  }

  /// Oturum bloğunu sıfırlar; bir sonraki istek sistem penceresini yeniden deneyebilir.
  static Future<void> prepareForUserInitiatedPermissionDialog() async {
    _declinedThisSession = false;
    _inFlightRequest = null;
  }

  /// Sistem "Konuma izin ver?" penceresini gösterir.
  /// Arama / chip / otomatik tetik — hepsi bunu kullanır.
  static Future<PermissionRequestOutcome> requestOsPermissionDialog() {
    return _inFlightRequest ??= _requestOsPermissionDialogImpl()
        .whenComplete(() => _inFlightRequest = null);
  }

  /// Chip / kullanıcı dokunuşu — oturum reddini temizleyip yeniden dener.
  static Future<PermissionRequestOutcome> requestFromUserTap() async {
    await prepareForUserInitiatedPermissionDialog();
    return requestOsPermissionDialog();
  }

  /// Eski API uyumu.
  static Future<bool> ensureLocationPermissionFromUserAction() async {
    final o = await requestFromUserTap();
    return o == PermissionRequestOutcome.granted;
  }

  static Future<PermissionRequestOutcome> _requestOsPermissionDialogImpl() async {
    try {
      var perm = await Geolocator.checkPermission();
      debugPrint('Rotalink konum: checkPermission=$perm');

      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        _declinedThisSession = false;
        return PermissionRequestOutcome.granted;
      }

      // Sistem runtime izin penceresi.
      perm = await Geolocator.requestPermission();
      debugPrint('Rotalink konum: requestPermission=$perm');

      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        _declinedThisSession = false;
        return PermissionRequestOutcome.granted;
      }

      if (perm == LocationPermission.deniedForever) {
        _declinedThisSession = true;
        return PermissionRequestOutcome.deniedForever;
      }

      _declinedThisSession = true;
      return PermissionRequestOutcome.denied;
    } catch (e, st) {
      debugPrint('Rotalink konum izin hatası: $e\n$st');
      _declinedThisSession = true;
      return PermissionRequestOutcome.denied;
    }
  }
}
