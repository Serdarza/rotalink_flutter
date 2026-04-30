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
    if (await Permission.locationWhenInUse.isGranted) return false;
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
      // 1. İzin zaten verilmiş mi?
      if (await Permission.locationWhenInUse.isGranted) {
        _declinedThisSession = false;
        return PermissionRequestOutcome.granted;
      }

      final status = await Permission.locationWhenInUse.status;

      // 2. Kalıcı red / kısıtlı: sistem penceresi artık açılmaz → Ayarlar'a yönlendir.
      if (status.isPermanentlyDenied || status.isRestricted) {
        await openAppSettings();
        return PermissionRequestOutcome.openedSettings;
      }

      // 3. Normal istek göster.
      final result = await Permission.locationWhenInUse.request();
      final granted =
          result.isGranted || await Permission.locationWhenInUse.isGranted;

      if (granted) {
        _declinedThisSession = false;
        return PermissionRequestOutcome.granted;
      }

      // 4. İstek sonrası kalıcı red oldu mu? (bazı cihazlarda ikinci redde geçer)
      final statusAfter = await Permission.locationWhenInUse.status;
      if (statusAfter.isPermanentlyDenied) {
        await openAppSettings();
        return PermissionRequestOutcome.openedSettings;
      }

      _declinedThisSession = true;
      return PermissionRequestOutcome.denied;
    } catch (_) {
      _declinedThisSession = true;
      return PermissionRequestOutcome.denied;
    }
  }

  // ─── Dahili akış ──────────────────────────────────────────────────────────

  static Future<bool> _requestFlow() async {
    try {
      // 1. İzin zaten var mı?
      if (await Permission.locationWhenInUse.isGranted) {
        _declinedThisSession = false;
        return true;
      }

      // 2. Bu oturumda daha önce reddedildi mi?
      if (_declinedThisSession) return false;

      final status = await Permission.locationWhenInUse.status;

      // 3. Kalıcı red veya kısıtlı: sistem penceresini gösterme, sessizce bloke et.
      if (status.isPermanentlyDenied || status.isRestricted) {
        _declinedThisSession = true;
        return false;
      }

      // 4. Sistem izin penceresini göster.
      final result = await Permission.locationWhenInUse.request();
      final granted =
          result.isGranted || await Permission.locationWhenInUse.isGranted;

      _declinedThisSession = !granted;
      return granted;
    } catch (_) {
      _declinedThisSession = true;
      return false;
    }
  }
}
