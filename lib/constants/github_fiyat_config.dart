/// GitHub üzerindeki tesis fiyat dosyası (fiyatlar.json).
///
/// Ana veritabanından ayrıdır; fiyat güncellemesi sadece bu dosyayı değiştirir.
abstract final class GithubFiyatConfig {
  static const fileName = 'fiyatlar.json';

  /// Aynı repo: Serdarza/rotalink-data
  static const rawUrl =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/fiyatlar.json';

  static Uri get uri => Uri.parse(rawUrl);
}
