import '../../utils/search_normalize.dart';
import 'fuzzy_search.dart';

/// Il adi eslestirme — TR 81 il + veritabanindaki dinamik iller.
abstract final class KamiCityResolver {
  /// Turkiye'nin 81 ili.
  static const List<String> provinces = <String>[
    'Adana', 'Adiyaman', 'Afyonkarahisar', 'Agri', 'Amasya', 'Ankara', 'Antalya',
    'Artvin', 'Aydin', 'Balikesir', 'Bilecik', 'Bingol', 'Bitlis', 'Bolu', 'Burdur',
    'Bursa', 'Canakkale', 'Cankiri', 'Corum', 'Denizli', 'Diyarbakir', 'Edirne',
    'Elazig', 'Erzincan', 'Erzurum', 'Eskisehir', 'Gaziantep', 'Giresun',
    'Gumushane', 'Hakkari', 'Hatay', 'Isparta', 'Mersin', 'Istanbul', 'Izmir',
    'Kars', 'Kastamonu', 'Kayseri', 'Kirklareli', 'Kirsehir', 'Kocaeli', 'Konya',
    'Kutahya', 'Malatya', 'Manisa', 'Kahramanmaras', 'Mardin', 'Mugla', 'Mus',
    'Nevsehir', 'Nigde', 'Ordu', 'Rize', 'Sakarya', 'Samsun', 'Siirt', 'Sinop',
    'Sivas', 'Tekirdag', 'Tokat', 'Trabzon', 'Tunceli', 'Sanliurfa', 'Usak', 'Van',
    'Yozgat', 'Zonguldak', 'Aksaray', 'Bayburt', 'Karaman', 'Kirikkale', 'Batman',
    'Sirnak', 'Bartin', 'Ardahan', 'Igdir', 'Yalova', 'Karabuk', 'Kilis', 'Osmaniye',
    'Duzce',
  ];

  static String normalize(String raw) => normalizeForSearch(raw);

  static Map<String, String> buildCatalog(Iterable<String> databaseCities) {
    final map = <String, String>{};
    void put(String display) {
      final n = normalize(display);
      if (n.isEmpty) return;
      map.putIfAbsent(n, () => display.trim());
    }

    for (final c in databaseCities) {
      put(c);
    }
    for (final p in provinces) {
      put(p);
    }
    map.putIfAbsent(normalize('Maras'), () => 'Kahramanmaras');
    map.putIfAbsent(normalize('Urfa'), () => 'Sanliurfa');
    map.putIfAbsent(normalize('Antep'), () => 'Gaziantep');
    map.putIfAbsent(normalize('Afyon'), () => 'Afyonkarahisar');
    map.putIfAbsent(normalize('Icel'), () => 'Mersin');
    return map;
  }

  static List<String> extractCities(String text, Map<String, String> catalog) {
    if (text.trim().isEmpty) return const [];

    final found = <String>[];
    final usedKeys = <String>{};

    void addDisplay(String display) {
      final key = normalize(display);
      if (key.isEmpty || !usedKeys.add(key)) return;
      found.add(display.trim());
    }

    // 1) Token bazlı eşleşme — kısa il adları (Van, Muş vb.) yanlış pozitif vermez.
    for (final token in KamiFuzzySearch.tokenize(text)) {
      final n = normalize(token);
      if (catalog.containsKey(n)) {
        addDisplay(catalog[n]!);
        continue;
      }
      final corrected = KamiFuzzySearch.correctCityToken(token, catalog);
      if (corrected != null) addDisplay(corrected);
    }

    // 2) Uzun il adları için tam metin taraması (en az 4 karakter).
    final norm = normalize(text);
    if (norm.isEmpty) return found;

    final keys = catalog.keys.where((k) => k.length >= 4).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final usedSpans = <(int, int)>[];

    for (final key in keys) {
      var start = 0;
      while (true) {
        final idx = norm.indexOf(key, start);
        if (idx < 0) break;
        final end = idx + key.length;
        final overlaps = usedSpans.any((s) => idx < s.$2 && end > s.$1);
        if (!overlaps) {
          usedSpans.add((idx, end));
          addDisplay(catalog[key]!);
        }
        start = end;
      }
    }
    return found;
  }

  static (String?, String?) extractRouteEndpoints(
    String text,
    Map<String, String> catalog,
  ) {
    final cities = extractCities(text, catalog);
    if (cities.length >= 2) {
      return (cities[0], cities[1]);
    }
    return (cities.isNotEmpty ? cities.first : null, null);
  }

  static String? canonicalCity(String? raw, Map<String, String> catalog) {
    if (raw == null || raw.trim().isEmpty) return null;
    final n = normalize(raw);
    return catalog[n];
  }

  static bool sameCity(String a, String b) => normalize(a) == normalize(b);
}