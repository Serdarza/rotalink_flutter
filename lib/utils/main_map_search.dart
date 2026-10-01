import '../models/misafirhane.dart';
import 'il_ilce.dart';
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

  static String _noIlce(Misafirhane m) => m.ilce;

  static bool _matchesFuzzy(
    Misafirhane m,
    List<String> queryWords,
    String Function(Misafirhane m) ilceOf,
  ) {
    if (queryWords.isEmpty) return true;
    final ilNorm = normalizeForSearch(m.il);
    if (queryWords.every(ilNorm.contains)) return true;
    final combined = normalizeForSearch('${m.il}${ilceOf(m)}${m.isim}');
    return queryWords.every(combined.contains);
  }

  /// Sorgu il / "il ilçe" / ilçe adıysa konum eşleşmeleri ([IlIlce.matchQuery]).
  static List<IlIlceMatch> matchLocation({
    required String query,
    required List<Misafirhane> kaynak,
  }) =>
      IlIlce.matchQuery(query, kaynak.map((m) => m.il).toSet());

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

  /// Boş sorguda Kotlin `allMisafirhaneList` (haritadaki il temsilcileri) döner.
  static List<Misafirhane> perform({
    required String query,
    required List<Misafirhane> kaynak,
    required List<Misafirhane> mapMisafirhaneler,
    String Function(Misafirhane m) ilceOf = _noIlce,
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

    final narrowHits =
        kaynak.where((m) => _matchesFuzzy(m, words, ilceOf)).toList();

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
    String Function(Misafirhane m) ilceOf = _noIlce,
  }) {
    final words = queryWords(query);
    if (words.isEmpty) return const [];
    return kaynak.where((m) => _matchesFuzzy(m, words, ilceOf)).toList();
  }

  /// Tek bir misafirhane kartına kaydırma / sarı vurgu için hedef.
  /// Yalnızca il adıyla yapılan (tüm liste aynı il) aramalarda null döner.
  static Misafirhane? findPrimaryMatchForScroll({
    required String query,
    required List<Misafirhane> displayedFacilities,
  }) {
    final words = queryWords(query);
    if (words.isEmpty || displayedFacilities.isEmpty) return null;

    // Sorgu bir il adının kendisiyse ("Ankara", "Kahraman Maraş") yalnızca il listesi
    // açılır; adı il adıyla başlayan tesis ya da başka ilde adında il geçen tesis
    // hedeflenip listede kaydırılmaz.
    final fullQuery = words.join();
    if (displayedFacilities.any((m) => normalizeForSearch(m.il) == fullQuery)) {
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
