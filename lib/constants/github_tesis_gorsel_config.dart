/// GitHub — konaklama tesis görselleri (tesisler_gorseller.json).
///
/// Ana veritabanından ayrı; il+isim ile tesislere bağlanır.
abstract final class GithubTesisGorselConfig {
  static const fileName = 'tesisler_gorseller.json';

  static const rawUrl =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/tesisler_gorseller.json';

  static Uri get uri => Uri.parse(rawUrl);
}
