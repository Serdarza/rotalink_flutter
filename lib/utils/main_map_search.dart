import '../models/misafirhane.dart';
import 'search_normalize.dart';

/// Kotlin [MainActivity.tesisKaynagiArama] + [performSearch] + [matchesMainSearchQueryFuzzy].
abstract final class MainMapSearch {
  static List<String> queryWords(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    return trimmed
        .split(RegExp(r'\s+'))
        .map(normalizeForSearch)
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// `aramaIcinTumTesisler.ifEmpty { allMisafirhaneList }` → Flutter [RotaDataState] alanları.
  static List<Misafirhane> tesisKaynagiArama({
    required List<Misafirhane> aramaIcinTumTesisler,
    required List<Misafirhane> misafirhaneler,
  }) {
    return aramaIcinTumTesisler.isNotEmpty ? aramaIcinTumTesisler : misafirhaneler;
  }

  static bool _matchesFuzzy(Misafirhane m, List<String> queryWords) {
    if (queryWords.isEmpty) return true;
    final ilNorm = normalizeForSearch(m.il);
    if (queryWords.every(ilNorm.contains)) return true;
    final combined = normalizeForSearch('${m.il}${m.isim}');
    return queryWords.every(combined.contains);
  }

  /// Kotlin [MainActivity] `tesisKaynagiArama().map { it.il }.distinct().sorted()`.
  static List<String> distinctSortedIller({
    required List<Misafirhane> aramaIcinTumTesisler,
    required List<Misafirhane> misafirhaneler,
  }) {
    final kaynak = tesisKaynagiArama(
      aramaIcinTumTesisler: aramaIcinTumTesisler,
      misafirhaneler: misafirhaneler,
    );
    final list = kaynak.map((e) => e.il.trim()).where((il) => il.isNotEmpty).toSet().toList();
    list.sort((a, b) => normalizeForSearch(a).compareTo(normalizeForSearch(b)));
    return list;
  }

  /// [AutoCompleteTextView] + [ArrayAdapter] ön ek filtresine yakın (küçük harf / aksan yok sayımı [normalizeForSearch] ile).
  /// Önce önek; eşleşme yoksa ve sorgu en az 2 harf ise içerir eşlemesi (ör. "kara" → Karaman).
  static Iterable<String> filterIlAutocomplete(List<String> sortedIller, String rawQuery) {
    final q = rawQuery.trim();
    if (q.isEmpty) return const Iterable<String>.empty();
    final n = normalizeForSearch(q);
    if (n.isEmpty) return const Iterable<String>.empty();
    final prefix = sortedIller.where((il) => normalizeForSearch(il).startsWith(n));
    if (prefix.isNotEmpty) return prefix;
    if (n.length < 2) return const Iterable<String>.empty();
    return sortedIller.where((il) => normalizeForSearch(il).contains(n));
  }

  /// Boş sorguda Kotlin `allMisafirhaneList` (haritadaki il temsilcileri) döner.
  static List<Misafirhane> perform({
    required String query,
    required List<Misafirhane> kaynak,
    required List<Misafirhane> mapMisafirhaneler,
  }) {
    final words = queryWords(query);
    final fullQueryNorm = words.join();
    if (words.isEmpty) {
      return List<Misafirhane>.from(mapMisafirhaneler);
    }

    final exactIlMatches = kaynak
        .map((e) => e.il)
        .toSet()
        .where((il) => normalizeForSearch(il) == fullQueryNorm)
        .toSet();

    final narrowHits = kaynak.where((m) => _matchesFuzzy(m, words)).toList();

    if (exactIlMatches.isNotEmpty) {
      return kaynak.where((m) => exactIlMatches.contains(m.il)).toList();
    }
    if (narrowHits.isEmpty) {
      return const [];
    }
    final primary = findPrimaryMatchForScroll(
      query: query,
      displayedFacilities: narrowHits,
    );
    final ilFocus = normalizeForSearch((primary ?? narrowHits.first).il.trim());
    return kaynak
        .where((m) => normalizeForSearch(m.il.trim()) == ilFocus)
        .toList();
  }

  /// [perform] il genişletmesinden önceki fuzzy dar liste (birincil vurgu / kaydırma hedefi).
  static List<Misafirhane> narrowFuzzyMatches({
    required String query,
    required List<Misafirhane> kaynak,
  }) {
    final words = queryWords(query);
    if (words.isEmpty) return const [];
    return kaynak.where((m) => _matchesFuzzy(m, words)).toList();
  }

  /// Tek bir misafirhane kartına kaydırma / sarı vurgu için hedef.
  /// Yalnızca il adıyla yapılan (tüm liste aynı il) aramalarda null döner.
  static Misafirhane? findPrimaryMatchForScroll({
    required String query,
    required List<Misafirhane> displayedFacilities,
  }) {
    final words = queryWords(query);
    if (words.isEmpty || displayedFacilities.isEmpty) return null;

    final normIls = displayedFacilities.map((e) => normalizeForSearch(e.il)).toSet();
    // Yalnızca il adı (tek kelime, tam eşleşme) → liste tüm il; tek tesis vurgusu yok
    if (normIls.length == 1 && words.length == 1 && words.single == normIls.single) {
      return null;
    }

    Misafirhane? best;
    var bestScore = -1;
    var bestNameHits = -1;
    for (final m in displayedFacilities) {
      final name = normalizeForSearch(m.isim);
      final ilN = normalizeForSearch(m.il);
      var score = 0;
      var nameHits = 0;
      for (final w in words) {
        if (w.isEmpty) continue;
        if (name.contains(w)) {
          score += w.length * 4;
          nameHits++;
        } else if (ilN.contains(w)) {
          score += w.length;
        }
      }
      if (words.isNotEmpty && name.startsWith(words.first)) {
        score += 8;
      }
      final better = score > bestScore || (score == bestScore && nameHits > bestNameHits);
      if (better) {
        bestScore = score;
        bestNameHits = nameHits;
        best = m;
      }
    }
    if (bestScore <= 0) {
      return displayedFacilities.length == 1 ? displayedFacilities.first : null;
    }
    return best;
  }
}
