/// GitHub — hediye Pro kodlarının SHA-256 özetleri (`pro_kodlar.json`).
abstract final class GithubProCodeConfig {
  static const fileName = 'pro_kodlar.json';

  static final uri = Uri.parse(
    'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/pro_kodlar.json',
  );
}
