/// GitHub üzerindeki zorunlu güncelleme politikası (versiyon_güncellem.json).
abstract final class GithubAppVersionConfig {
  static const fileName = 'versiyon_güncellem.json';

  static const rawUrl =
      'https://raw.githubusercontent.com/Serdarza/versiyon/refs/heads/main/versiyon_g%C3%BCncellem.json';

  static Uri get uri => Uri.parse(rawUrl);
}
