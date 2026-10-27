/// GitHub — Kış Keşfet yayın dosyası (`kis_kesfet/data/kis_kesfet.json`).
abstract final class GithubKisKesfetConfig {
  static const fileName = 'kis_kesfet.json';

  static const rawUrl =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/kis_kesfet/data/kis_kesfet.json';

  static Uri get uri => Uri.parse(rawUrl);
}
