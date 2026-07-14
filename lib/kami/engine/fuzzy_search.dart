import '../../utils/search_normalize.dart';

/// Yazım hatası / Türkçe karakter duyarsız fuzzy yardımcılar.
abstract final class KamiFuzzySearch {
  /// Yaygın şehir yazım hataları (normalize edilmiş → canonical normalize key).
  static const Map<String, String> cityTypos = {
    'istanbl': 'istanbul',
    'istanbu': 'istanbul',
    'istnbul': 'istanbul',
    'ist': 'istanbul',
    'ankra': 'ankara',
    'ankaraa': 'ankara',
    'izmır': 'izmir',
    'izmer': 'izmir',
    'kaysri': 'kayseri',
    'kayser': 'kayseri',
    'kaysery': 'kayseri',
    'gazıantep': 'gaziantep',
    'antep': 'gaziantep',
    'bursa': 'bursa',
    'adana': 'adana',
    'mersın': 'mersin',
    'icel': 'mersin',
  };

  /// Tesis türü / kelime düzeltmeleri (boşluklu veya hatalı → canonical tip key).
  static const Map<String, String> tokenCorrections = {
    'ogretmenevi': 'ogretmenevi',
    'ogretmen evi': 'ogretmenevi',
    'ogretmenvi': 'ogretmenevi',
    'ogretmen': 'ogretmenevi',
    'ogretmanevi': 'ogretmenevi',
    'orduevi': 'orduevi',
    'ordu evi': 'orduevi',
    'orduev': 'orduevi',
    'ordueví': 'orduevi',
    'polisevi': 'polisevi',
    'polis evi': 'polisevi',
    'polısevi': 'polisevi',
    'policevi': 'polisevi',
    'misafirhane': 'misafirhane',
    'misafrhane': 'misafirhane',
    'misafirane': 'misafirhane',
    'misafırhane': 'misafirhane',
    'misafirhan': 'misafirhane',
    'kamutesisi': 'misafirhane',
    'kamu tesisi': 'misafirhane',
    'konaklama': 'misafirhane',
  };

  static String norm(String s) => normalizeForSearch(s);

  /// Metni tokenlara ayırır; yazım düzeltmesi uygular.
  static List<String> tokenize(String raw) {
    final cleaned = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"[’']"), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9çÇğĞıİöÖşŞüÜ\s]'), ' ');
    final parts = cleaned
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // "ordu evi", "polis evi", "öğretmen evi" birleştir
    final merged = <String>[];
    for (var i = 0; i < parts.length; i++) {
      if (i + 1 < parts.length) {
        final pair = '${parts[i]} ${parts[i + 1]}';
        final pairNorm = norm(pair);
        if (tokenCorrections.containsKey(pairNorm) ||
            pairNorm == 'orduevi' ||
            pairNorm == 'polisevi' ||
            pairNorm == 'ogretmenevi') {
          merged.add(norm(tokenCorrections[pairNorm] ?? pairNorm));
          i++;
          continue;
        }
      }
      final n = norm(parts[i]);
      merged.add(tokenCorrections[n] ?? n);
    }
    return merged;
  }

  /// Levenshtein mesafe.
  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      var cur0 = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final cur = [
          prev[j] + 1,
          cur0 + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
        prev[j - 1] = cur0;
        cur0 = cur;
      }
      prev[b.length] = cur0;
    }
    return prev[b.length];
  }

  /// 0..1 benzerlik (1 = aynı).
  static double similarity(String a, String b) {
    final na = norm(a);
    final nb = norm(b);
    if (na.isEmpty || nb.isEmpty) return 0;
    if (na == nb) return 1;
    if (na.contains(nb) || nb.contains(na)) {
      final shorter = na.length < nb.length ? na.length : nb.length;
      final longer = na.length > nb.length ? na.length : nb.length;
      return 0.75 + 0.25 * (shorter / longer);
    }
    final d = levenshtein(na, nb);
    final maxLen = na.length > nb.length ? na.length : nb.length;
    return (1 - d / maxLen).clamp(0.0, 1.0);
  }

  /// Şehir typo düzeltmesi; catalog key üzerinden.
  static String? correctCityToken(
    String token,
    Map<String, String> cityCatalog,
  ) {
    final n = norm(token);
    if (n.isEmpty) return null;
    if (cityCatalog.containsKey(n)) return cityCatalog[n];
    final typo = cityTypos[n];
    if (typo != null && cityCatalog.containsKey(typo)) {
      return cityCatalog[typo];
    }
    // Fuzzy şehir (kısa tokenlarda sıkı eşik)
    String? best;
    var bestScore = 0.0;
    final minScore = n.length <= 3 ? 0.92 : 0.82;
    for (final entry in cityCatalog.entries) {
      final score = similarity(n, entry.key);
      if (score > bestScore) {
        bestScore = score;
        best = entry.value;
      }
    }
    if (bestScore >= minScore) return best;
    return null;
  }

  /// Metinde tip anahtar kelimesi var mı?
  static bool containsFacilityKindKey(String normalizedHaystack, String kindKey) {
    return normalizedHaystack.contains(kindKey);
  }
}
