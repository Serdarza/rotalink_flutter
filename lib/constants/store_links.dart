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

  /// Kullanıcı öneri / fiyat bildirimi.
  static const supportEmail = 'rotalinkinfo@gmail.com';

  static bool get _isApple => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// Bu platformdaki mağaza sayfası (puanlama / tek link).
  static String get currentStore => _isApple ? appStore : playStore;

  static String get currentStoreName => _isApple ? 'App Store' : 'Play Store';

  /// Uygulama yokken paylaşım linkinin açtığı adres.
  static const home = 'https://rotalink.tr/';

  /// Çekmece menüsü — Uygulamayı Paylaş.
  static String drawerShareMessage() =>
      'Rotalink — kamu seyahat rehberi\n$home';

  /// Paylaşım metinlerinin altındaki tek bağlantı.
  static String shareDownloadFooter() => 'Rotalink\n$home';

  /// Başlık, isteğe bağlı satırlar ve alttaki site bağlantısı.
  static String shareMessage(String title, [List<String> lines = const []]) {
    final body = StringBuffer(title.trim());
    for (final line in lines) {
      final text = line.trim();
      if (text.isEmpty) continue;
      body
        ..write('\n')
        ..write(text);
    }
    body
      ..write('\n\n')
      ..write(shareDownloadFooter());
    return body.toString();
  }
}
