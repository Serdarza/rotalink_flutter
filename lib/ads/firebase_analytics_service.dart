import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firebase Analytics ile ilgili tüm işlemleri yöneten singleton servis sınıfı
/// Hem Android hem de iOS platformlarıyla %100 uyumlu
class FirebaseAnalyticsService {
  FirebaseAnalyticsService._();
  static final FirebaseAnalyticsService instance = FirebaseAnalyticsService._();

  bool get _ready => !kIsWeb && Firebase.apps.isNotEmpty;

  FirebaseAnalytics get analytics => FirebaseAnalytics.instance;

  /// Firebase Analytics'i başlatır ve temel ayarları yapar
  Future<void> initialize() async {
    if (!_ready) return;
    // Analytics otomatik etkinlik koleksiyonunu etkinleştir
    await analytics.setAnalyticsCollectionEnabled(true);
  }

  /// Uygulama açılış etkinliğini loglar (app_open)
  Future<void> logAppOpen() async {
    if (!_ready) return;
    await analytics.logAppOpen();
  }

  /// Özel etkinlik: Tesis inceleme
  /// [tesisAdi]: Tesisin adı
  /// [tesisTipi]: Tesisin tipi (örneğin: Camii, Şehir Hastanesi vb.)
  /// [il]: Tesisin bulunduğu il
  Future<void> logTesisInceleme({
    required String tesisAdi,
    required String tesisTipi,
    required String il,
  }) async {
    if (!_ready) return;
    await analytics.logEvent(
      name: 'tesis_inceleme',
      parameters: <String, Object>{
        'tesis_adi': tesisAdi,
        'tesis_tipi': tesisTipi,
        'il': il,
      },
    );
  }

  /// Özel etkinlik: Arama yapma
  /// [aramaTerimi]: Kullanıcının arama çubuğuna yazdığı terim
  /// [aramaTipi]: Arama türü (örneğin: il, tesis, adres vb.)
  Future<void> logArama({
    required String aramaTerimi,
    String? aramaTipi,
  }) async {
    if (!_ready) return;
    final parameters = <String, Object>{
      'arama_terimi': aramaTerimi,
    };
    if (aramaTipi != null) {
      parameters['arama_tipi'] = aramaTipi;
    }
    await analytics.logEvent(
      name: 'arama_yapildi',
      parameters: parameters,
    );
  }

  /// Kullanıcı ID'sini ayarlar (opsiyonel, eğer oturum yönetimi varsa kullanılır)
  Future<void> setUserId(String? userId) async {
    if (!_ready) return;
    await analytics.setUserId(id: userId);
  }

  /// Kullanıcı özelliklerini ayarlar
  Future<void> setUserProperty({
    required String name,
    required String value,
  }) async {
    if (!_ready) return;
    await analytics.setUserProperty(name: name, value: value);
  }

  /// Mevcut ekranı loglar (AnalyticsObserver tarafından kullanılır)
  Future<void> setCurrentScreen({
    required String screenName,
    String? screenClass,
  }) async {
    if (!_ready) return;
    await analytics.logScreenView(
      screenName: screenName,
      screenClass: screenClass ?? 'Flutter',
    );
  }
}

/// FirebaseAnalyticsService için Riverpod Provider'ı
final firebaseAnalyticsServiceProvider = Provider<FirebaseAnalyticsService>((ref) {
  return FirebaseAnalyticsService.instance;
});

/// FirebaseAnalytics nesnesi için direkt Provider
final firebaseAnalyticsProvider = Provider<FirebaseAnalytics>((ref) {
  final service = ref.watch(firebaseAnalyticsServiceProvider);
  return service.analytics;
});
