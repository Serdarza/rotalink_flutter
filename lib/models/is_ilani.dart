/// Firebase Realtime Database `is_ilanlari` düğümündeki tek bir ilanı temsil eder.
class IsIlani {
  const IsIlani({
    required this.kurum,
    required this.pozisyon,
    required this.tarih,
    required this.link,
  });

  final String kurum;
  final String pozisyon;
  final String tarih;
  final String link;

  factory IsIlani.fromMap(Map<Object?, Object?> map) {
    String s(String key) => map[key]?.toString().trim() ?? '';
    return IsIlani(
      kurum: s('kurum'),
      pozisyon: s('pozisyon'),
      tarih: s('tarih'),
      link: s('link'),
    );
  }

  static IsIlani? tryParse(dynamic value) {
    if (value is! Map) return null;
    try {
      return IsIlani.fromMap(value as Map<Object?, Object?>);
    } catch (_) {
      return null;
    }
  }
}
