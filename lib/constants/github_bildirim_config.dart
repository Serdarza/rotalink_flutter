/// GitHub üzerindeki haftalık duyuru bildirimleri (bildirimler.json).
abstract final class GithubBildirimConfig {
  static const fileName = 'bildirimler.json';

  /// Aynı repo: Serdarza/rotalink-data
  static const rawUrl =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/bildirimler.json';

  static Uri get uri => Uri.parse(rawUrl);
}
