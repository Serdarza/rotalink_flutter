/// Mağaza indirme bağlantıları ve paylaşım metinleri.
abstract final class StoreLinks {
  static const playStore =
      'https://play.google.com/store/apps/details?id=com.serdarza.rotalink';

  static const appStore =
      'https://apps.apple.com/us/app/rotalink-kamu-seyahat-rehberi/id6764678799';

  /// Çekmece menüsü — Uygulamayı Paylaş.
  static String drawerShareMessage() =>
      'Rotalink uygulamasını bu linklerden indirebilirsiniz:\n\n'
      'Play Store:\n$playStore\n\n'
      'App Store:\n$appStore';
}
