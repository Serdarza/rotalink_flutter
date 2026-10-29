import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Play Console / App Store Connect ürün kimlikleri.
///
/// Her iki mağazada da **aynı** kimlikler tanımlanmalıdır:
/// - Play Console → Abonelikler → yeni abonelik → kimlik alanı
/// - App Store Connect → Abonelikler → ürün kimliği
///
/// Fiyat uygulamada tanımlı değildir; mağazadan okunur. Fiyat değişikliği
/// uygulama güncellemesi gerektirmez.
///
/// Play Console promo kodu ve App Store Connect abonelik teklif kodu aynı
/// kimlikleri kullanır. Kod mağazada kullanılır; uygulama satın alma akışında
/// normal abonelik olarak görür.
abstract final class ProProducts {
  static const String monthly = 'rotalink_pro_monthly';
  static const String yearly = 'rotalink_pro_yearly';

  static const Set<String> ids = {monthly, yearly};
  static const Set<String> premiumIds = {
    'rotalink_silver_monthly',
    'rotalink_gold_monthly',
    'rotalink_platinum_yearly',
  };

  static const String androidPackage = 'com.serdarza.rotalink';

  static const String _playSubscriptions =
      'https://play.google.com/store/account/subscriptions';
  static const String _appleSubscriptions =
      'https://apps.apple.com/account/subscriptions';

  static bool get _isApple => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// Mağaza adı — kullanıcı metinlerinde kullanılır.
  static String get storeName => _isApple ? 'App Store' : 'Google Play';

  /// Abonelik yönetim sayfası (iptal / plan değiştirme).
  static String manageUrl(String? productId) {
    if (_isApple) return _appleSubscriptions;
    if (productId == null || productId.isEmpty) {
      return _playSubscriptions;
    }
    return '$_playSubscriptions?sku=$productId&package=$androidPackage';
  }
}
