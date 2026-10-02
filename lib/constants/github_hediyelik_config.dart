/// GitHub — il bazlı yöresel hediyelik ürünler (`hediyelik.json`).
abstract final class GithubHediyelikConfig {
  static const fileName = 'hediyelik.json';

  static const rawUrl =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/hediyelik.json';

  static Uri get uri => Uri.parse(rawUrl);
}
