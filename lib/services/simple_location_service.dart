import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Kullanıcı tarafından tetiklenen izin isteğinin sonucu.
enum PermissionRequestOutcome {
  /// İzin verildi — mesafe hesaplamasına geç.
  granted,

  /// Kullanıcı bu oturumda izni reddetti — bir daha otomatik sorma.
  denied,

  /// İzin kalıcı reddedildi (isPermanentlyDenied). Sistem ayarlar menüsü açıldı.
  /// Çağıran taraf [WidgetsBindingObserver] ile uygulamaya dönüşü izlemeli.
  openedSettings,
}

/// Konum izni yönetimi — tamamen oturum bazlı.
/// Tüm bayraklar bellek içindedir; uygulama kapanıp açılınca otomatik sıfırlanır.
///
/// Kullanım:
///   - Otomatik tetikleme (arama, panel açılışı vb.): [ensureLocationPermissionFromUserAction]
///   - Chip dokunuşu (kullanıcı isteği, tam zincir): [requestFromUserTap]
///   - Oturum bloğu kontrolü:                        [isLocationPermissionDeclinedByUser]
class SimpleLocationService {
  SimpleLocationService._();

  // ─── Oturum bayrakları (bellek; uygulama kapanınca sıfırlanır) ────────────

  /// Kullanıcı bu oturumda sistem izin penceresini kapattı veya reddetti.
  static bool _declinedThisSession = false;

  /// GPS / Play Services "Konum doğruluğu" penceresinde bu oturumda "Hayır" dedi.
  static bool _gpsUnavailableThisSession = false;

  // ─── Uçuştaki istek (eşzamanlı çoklu çağrıyı önler) ─────────────────────
  static Future<bool>? _inFlightRequest;

  // ─── GPS erişimi ──────────────────────────────────────────────────────────

  static bool get shouldSuppressPlayServicesLocationActivity =>
      _gpsUnavailableThisSession;

  static void markSessionPlayServicesLocationPromptDeclined() =>
      _gpsUnavailableThisSession = true;

  // ─── Ana API ──────────────────────────────────────────────────────────────

  /// İzin durumunu kontrol et. İzin zaten verilmişse her zaman `false` döner.
  static Future<bool> isLocationPermissionDeclinedByUser() async {
    final geo = await Geolocator.checkPermission();
    if (geo == LocationPermission.whileInUse || geo == LocationPermission.always) {
      return false;
    }
    return _declinedThisSession;
  }

  /// Kullanıcı "Size uzaklık: Konum izni vermeniz gereklidir" metnine dokunduğunda çağrılır.
  /// Oturum bloğunu sıfırlar; bir sonraki [ensureLocationPermissionFromUserAction] çağrısı
  /// yeniden sistem penceresini gösterebilir.
  static Future<void> prepareForUserInitiatedPermissionDialog() async {
    _declinedThisSession = false;
    _inFlightRequest = null; // devam eden isteği iptal et
  }

  /// İzin iste. Oturum bloğuna uyar: kullanıcı bu oturumda zaten reddettiyse
  /// diyalog göstermeden `false` döner.
  static Future<bool> ensureLocationPermissionFromUserAction() {
    return _inFlightRequest ??=
        _requestFlow().whenComplete(() => _inFlightRequest = null);
  }

  // ─── Kullanıcı isteği (chip dokunuşu) ────────────────────────────────────

  /// "Size uzaklık: Konum izni vermeniz gereklidir" metnine dokunulduğunda çağrılır.
  ///
  /// Tam zincir:
  ///   1. İzin zaten varsa → [PermissionRequestOutcome.granted]
  ///   2. Kalıcı red → [openAppSettings] → [PermissionRequestOutcome.openedSettings]
  ///   3. Normal red → istek → verilmezse tekrar kalıcı red kontrolü → ayarlar veya [denied]
  static Future<PermissionRequestOutcome> requestFromUserTap() {
    _declinedThisSession = false;
    _inFlightRequest = null;
    return _userTapFlow();
  }

  static Future<PermissionRequestOutcome> _userTapFlow() async {
    try {
      // 1. İzin zaten verilmiş mi? (Geolocator — iOS CLLocationManager ile doğrudan)
      var geo = await Geolocator.checkPermission();
      if (geo == LocationPermission.whileInUse || geo == LocationPermission.always) {
        _declinedThisSession = false;
        return PermissionRequestOutcome.granted;
      }

      // 2. iOS'ta 'denied' = kalıcı red (kullanıcı daha önce reddetti → Ayarlar).
      if (geo == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return PermissionRequestOutcome.openedSettings;
      }

      // 3. İlk istek (notDetermined → denied): sistem diyaloğunu göster.
      geo = await Geolocator.requestPermission();
      if (geo == LocationPermission.whileInUse || geo == LocationPermission.always) {
        _declinedThisSession = false;
        return PermissionRequestOutcome.granted;
      }

      // 4. İstek sonrası kalıcı red (ikinci redde iOS deniedForever döner) → Ayarlar.
      if (geo == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return PermissionRequestOutcome.openedSettings;
      }

      _declinedThisSession = true;
      return PermissionRequestOutcome.denied;
    } catch (_) {
      // Exception durumunda Ayarlar fallback.
      try {
        await Geolocator.openAppSettings();
      } catch (_) {}
      return PermissionRequestOutcome.openedSettings;
    }
  }

  // ─── Dahili akış ──────────────────────────────────────────────────────────

  static Future<bool> _requestFlow() async {
    try {
      // 1. İzin zaten var mı?
      var geo = await Geolocator.checkPermission();
      if (geo == LocationPermission.whileInUse || geo == LocationPermission.always) {
        _declinedThisSession = false;
        return true;
      }

      // 2. Bu oturumda daha önce reddedildi mi?
      if (_declinedThisSession) return false;

      // 3. Kalıcı red: sessizce bloke et (chip dokunuşu değil → ayarlar açmaya gerek yok).
      if (geo == LocationPermission.deniedForever) {
        _declinedThisSession = true;
        return false;
      }

      // 4. Sistem izin penceresini göster.
      geo = await Geolocator.requestPermission();
      final granted =
          geo == LocationPermission.whileInUse || geo == LocationPermission.always;
      _declinedThisSession = !granted;
      return granted;
    } catch (_) {
      _declinedThisSession = true;
      return false;
    }
  }
}
