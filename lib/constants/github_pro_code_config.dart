/// GitHub — hediye Pro kodlarının SHA-256 özetleri (`pro_kod/uretilen/pro_kodlar.json`).
abstract final class GithubProCodeConfig {
  static const fileName = 'pro_kodlar.json';

  static const _primary =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/pro_kod/uretilen/pro_kodlar.json';
  static const _fallback =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/main/pro_kod/uretilen/pro_kodlar.json';

  static Uri get uri => _fresh(Uri.parse(_primary));

  static Uri get fallbackUri => _fresh(Uri.parse(_fallback));

  /// GitHub ham CDN önbelleğini aşmak için her indirmede yeni sorgu.
  static Uri _fresh(Uri uri) => uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      't': DateTime.now().millisecondsSinceEpoch.toString(),
    },
  );
}
