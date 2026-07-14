/// GitHub üzerindeki geçiş reklamı bekleme süresi (reklam_ayar.json).
abstract final class GithubAdConfig {
  static const fileName = 'reklam_ayar.json';

  static const rawUrl =
      'https://raw.githubusercontent.com/Serdarza/reklam_ayar/refs/heads/main/reklam_ayar.json';

  static Uri get uri => Uri.parse(rawUrl);
}
