import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

/// Kullanıcı tarafından tetiklenen izin isteğinin sonucu.
enum PermissionRequestOutcome {
  /// İzin verildi — mesafe hesaplamasına geç.
  granted,

  /// Kullanıcı bu oturumda izni reddetti — bir daha otomatik sorma.
  denied,

  /// İzin kalıcı reddedildi. Sistem ayarlar menüsü açıldı.
  /// Çağıran taraf [WidgetsBindingObserver] ile uygulamaya dönüşü izlemeli.
  openedSettings,
}

/// Konum izni yönetimi — tamamen oturum bazlı, yalnızca [Geolocator] kullanır.
///
/// iOS'ta hem [permission_handler] hem [geolocator] kullanmak iki ayrı
/// CLLocationManager oluşturur ve izin diyaloğunun sessizce iptal edilmesine
/// yol açar. Tüm konum izni işlemlerini [Geolocator] ile yapmak bu çakışmayı önler.
///
/// Kullanım:
///   - Anlık izin kontrolü:                           [isLocationGranted]
///   - Chip / konum butonu dokunuşu (tam zincir):     [requestFromUserTap]
///   - Otomatik tetikleme (arama vb.):                [ensureLocationPermissionFromUserAction]
///   - Oturum bloğu kontrolü:                         [isLocationPermissionDeclinedByUser]
class SimpleLocationService {
  SimpleLocationService._();

  // ─── Oturum bayrakları (bellek; uygulama kapanınca sıfırlanır) ────────────

  static bool _declinedThisSession = false;
  static bool _gpsUnavailableThisSession = false;
  static Future<bool>? _inFlightRequest;

  // ─── GPS erişimi ──────────────────────────────────────────────────────────

  static bool get shouldSuppressPlayServicesLocationActivity =>
      _gpsUnavailableThisSession;

  static void markSessionPlayServicesLocationPromptDeclined() =>
      _gpsUnavailableThisSession = true;

  // ─── Ana API ──────────────────────────────────────────────────────────────

  /// Konum izni verilmiş mi? [Geolocator.checkPermission] tabanlı.
  static Future<bool> isLocationGranted() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  /// İzin durumunu kontrol et. İzin zaten verilmişse her zaman `false` döner.
  static Future<bool> isLocationPermissionDeclinedByUser() async {
    if (await isLocationGranted()) return false;
    return _declinedThisSession;
  }

  /// Oturum bloğunu sıfırlar; bir sonraki [ensureLocationPermissionFromUserAction]
  /// çağrısı yeniden sistem penceresini gösterebilir.
  static Future<void> prepareForUserInitiatedPermissionDialog() async {
    _declinedThisSession = false;
    _inFlightRequest = null;
  }

  /// İzin iste. Oturum bloğuna uyar: kullanıcı bu oturumda zaten reddettiyse
  /// diyalog göstermeden `false` döner.
  static Future<bool> ensureLocationPermissionFromUserAction() {
    return _inFlightRequest ??=
        _requestFlow().whenComplete(() => _inFlightRequest = null);
  }

  // ─── Kullanıcı isteği (chip / konum butonu dokunuşu) ─────────────────────

  /// Tam izin zinciri:
  ///   1. Zaten verilmişse → [granted]
  ///   2. Kalıcı red → [Geolocator.openAppSettings] → [openedSettings]
  ///   3. İlk istek → OS diyaloğu → verilmezse iOS'ta Ayarlar, Android'de [denied]
  static Future<PermissionRequestOutcome> requestFromUserTap() {
    _declinedThisSession = false;
    _inFlightRequest = null;
    return _userTapFlow();
  }

  static Future<PermissionRequestOutcome> _userTapFlow() async {
    try {
      // 1. İzin zaten verilmiş mi?
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        _declinedThisSession = false;
        return PermissionRequestOutcome.granted;
      }

      // 2. Kalıcı red → Ayarlar'a yönlendir.
      if (perm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return PermissionRequestOutcome.openedSettings;
      }

      // 3. İlk istek veya normal red → OS diyaloğunu göster.
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        _declinedThisSession = false;
        return PermissionRequestOutcome.granted;
      }

      // 4. İstek sonrası hâlâ red:
      //    - Kalıcı red oldu → Ayarlar
      //    - iOS'ta her red sonrası Ayarlar (sistem diyalog bir daha çıkmaz)
      if (perm == LocationPermission.deniedForever || Platform.isIOS) {
        await Geolocator.openAppSettings();
        return PermissionRequestOutcome.openedSettings;
      }

      _declinedThisSession = true;
      return PermissionRequestOutcome.denied;
    } catch (_) {
      _declinedThisSession = true;
      return PermissionRequestOutcome.denied;
    }
  }

  // ─── Dahili akış (otomatik tetik) ─────────────────────────────────────────

  static Future<bool> _requestFlow() async {
    try {
      if (await isLocationGranted()) {
        _declinedThisSession = false;
        return true;
      }
      if (_declinedThisSession) return false;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.deniedForever) {
        _declinedThisSession = true;
        return false;
      }

      perm = await Geolocator.requestPermission();
      final granted = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      _declinedThisSession = !granted;
      return granted;
    } catch (_) {
      _declinedThisSession = true;
      return false;
    }
  }
}
