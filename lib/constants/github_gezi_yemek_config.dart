/// GitHub — gezi / yemek listeleri (görselli, ana DB'den ayrı).
abstract final class GithubGeziYemekConfig {
  static const gezilerFile = 'geziler.json';
  static const yemeklerFile = 'yemekler.json';

  static const gezilerRawUrl =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/geziler.json';
  static const yemeklerRawUrl =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/yemekler.json';

  static Uri get gezilerUri => Uri.parse(gezilerRawUrl);
  static Uri get yemeklerUri => Uri.parse(yemeklerRawUrl);
}
