/// GitHub — konaklama adres + ilçe (`tesisler_adres.json`).
abstract final class GithubTesisAdresConfig {
  static const fileName = 'tesisler_adres.json';

  static const rawUrl =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/tesisler_adres.json';

  static Uri get uri => Uri.parse(rawUrl);
}
