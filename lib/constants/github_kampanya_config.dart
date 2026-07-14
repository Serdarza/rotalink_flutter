/// GitHub üzerindeki Keşfet kampanya verisi (kampanya.json).
abstract final class GithubKampanyaConfig {
  static const databaseFileName = 'kampanya.json';

  static const rawDatabaseUrl =
      'https://raw.githubusercontent.com/Serdarza/kampanya/refs/heads/main/kampanya.json';

  static Uri get databaseUri => Uri.parse(rawDatabaseUrl);
}
