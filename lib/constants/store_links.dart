import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Mağaza indirme bağlantıları, yasal linkler ve paylaşım metinleri.
abstract final class StoreLinks {
  static const playStore =
      'https://play.google.com/store/apps/details?id=com.serdarza.rotalink';

  static const appStore =
      'https://apps.apple.com/us/app/rotalink-kamu-seyahat-rehberi/id6764678799';

  /// Gizlilik politikası (App Store 3.1.2 / abonelik ekranı).
  static const privacyPolicy = 'https://rotalink.tr/gizlilik-politikasi/';

  /// Apple standart EULA (abonelik şartları).
  static const termsOfUse =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  static bool get _isApple => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// Bu platformdaki mağaza sayfası (puanlama / tek link).
  static String get currentStore => _isApple ? appStore : playStore;

  static String get currentStoreName => _isApple ? 'App Store' : 'Play Store';

  /// Çekmece menüsü — Uygulamayı Paylaş.
  static String drawerShareMessage() =>
      'Rotalink uygulamasını bu linklerden indirebilirsiniz:\n\n'
      'Play Store:\n$playStore\n\n'
      'App Store:\n$appStore';

  /// Paylaşım metinlerinin altına eklenen indirme satırı (her iki mağaza).
  static String shareDownloadFooter() =>
      'Rotalink uygulamasını bu linklerden indirebilirsiniz:\n'
      'Play Store: $playStore\n'
      'App Store: $appStore';
}
