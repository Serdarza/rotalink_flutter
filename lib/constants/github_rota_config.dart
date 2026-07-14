/// GitHub üzerindeki rota veritabanı (master_database_updated.json).
abstract final class GithubRotaConfig {
  static const databaseFileName = 'master_database_updated.json';

  /// Serdarza/rotalink-data deposundaki ham JSON adresi.
  static const rawDatabaseUrl =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/master_database_updated.json';

  static Uri get databaseUri => Uri.parse(rawDatabaseUrl);
}
