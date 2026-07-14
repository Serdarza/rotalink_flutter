import 'city_resolver.dart';
import 'fuzzy_search.dart';
import 'kami_entities.dart';

/// Metinden il / tür / isim / yakınlık vb. varlık çıkarma.
abstract final class KamiEntityExtractor {
  static KamiEntities extract(
    String rawText, {
    required Map<String, String> cityCatalog,
  }) {
    final text = rawText.trim();
    if (text.isEmpty) {
      return const KamiEntities();
    }

    final n = KamiFuzzySearch.norm(text);
    final tokens = KamiFuzzySearch.tokenize(text);

    // Şehirler (token + tam metin uzun il öncelikli)
    final citiesFromText = KamiCityResolver.extractCities(text, cityCatalog);
    final cities = <String>[];
    final usedCityKeys = <String>{};

    void addCity(String? display) {
      if (display == null || display.trim().isEmpty) return;
      final key = KamiCityResolver.normalize(display);
      if (usedCityKeys.add(key)) cities.add(display.trim());
    }

    for (final c in citiesFromText) {
      addCity(c);
    }
    for (final t in tokens) {
      addCity(KamiFuzzySearch.correctCityToken(t, cityCatalog));
    }

    // Rota uçları
    String? fromCity;
    String? toCity;
    // "Kayseri'de ne yemeliyim" gibi cümlelerde "de" + "ye" yanlış rota sinyali üretmesin.
    final hasExplicitRouteKeyword = _hasAny(n, const [
      'gidiyorum',
      'gidecegim',
      'rota',
      'yolculuk',
      'rotaolustur',
      'rota olustur',
    ]);
    final hasDirectionalRoute = cities.length >= 2 &&
        (n.contains('dan') || n.contains('den')) &&
        (n.contains('ye') || n.contains('ya'));
    final routeCue = hasExplicitRouteKeyword || hasDirectionalRoute;
    if (cities.length >= 2 && routeCue) {
      fromCity = cities[0];
      toCity = cities[1];
    } else {
      final ends = KamiCityResolver.extractRouteEndpoints(text, cityCatalog);
      if (ends.$1 != null && ends.$2 != null && routeCue) {
        fromCity = ends.$1;
        toCity = ends.$2;
        addCity(fromCity);
        addCity(toCity);
      }
    }

    // Tesis türü
    KamiFacilityKind? kind;
    if (_hasAny(n, const ['orduevi', 'orduev', 'ordu evi'])) {
      kind = KamiFacilityKind.orduevi;
    } else if (_hasAny(n, const ['ogretmenevi', 'ogretmen evi', 'ogretmenvi'])) {
      kind = KamiFacilityKind.ogretmenevi;
    } else if (_hasAny(n, const ['polisevi', 'polis evi', 'polısevi'])) {
      kind = KamiFacilityKind.polisevi;
    } else if (_hasAny(n, const [
      'misafirhane',
      'misafrhane',
      'misafirane',
      'kamutesis',
      'konaklama',
    ])) {
      kind = KamiFacilityKind.misafirhane;
    }

    final nearby = _hasAny(n, const [
      'yakinimda',
      'yakinda',
      'yakinimdan',
      'yakinimdaki',
      'yakınımdan',
      'civarda',
      'etrafimda',
      'cevremde',
    ]);
    final nearestOnly = _hasAny(n, const [
      'enyakin',
      'en yakin',
      'en yakın',
    ]);

    final wantsFood = _hasAny(n, const [
      'neyenir',
      'yemek',
      'yenir',
      'lezzet',
      'mutfak',
      'neyesem',
      'neyemeliyim',
      'yemeliyim',
      'yoresel',
    ]);
    final wantsHistory = _hasAny(n, const [
      'tarih',
      'tarihi',
      'tarihyer',
      'antik',
      'muze',
      'müze',
      'anit',
      'anıt',
      'kale',
      'arkeoloji',
      'osmanli',
      'selcuk',
      'kultur',
      'kültür',
    ]);
    final wantsTourism = (_hasAny(n, const [
          'gezilecek',
          'gezi',
          'gezmel',
          'geziler',
          'turistik',
          'gorulecek',
          'kesfedelim',
          'manzara',
          'yerler',
          'gezilecekyer',
          'gezilecekyerler',
        ]) ||
        wantsHistory ||
        (cities.isNotEmpty &&
            _hasAny(n, const ['yer', 'yerler', 'nereler', 'nerelere']))) &&
        !_hasAny(n, const ['belediye']);
    final wantsMunicipal = _hasAny(n, const [
      'belediye',
      'sosyaltesis',
      'sosyal tesis',
      'kahvalti',
      'kahvaltı',
    ]);
    final wantsBreakfast = _hasAny(n, const ['kahvalti', 'kahvaltı', 'breakfast']);
    final wantsScenic = _hasAny(n, const ['manzara', 'manzarali', 'manzaralı']);
    final wantsRoute = routeCue ||
        _hasAny(n, const ['rotaolustur', 'rota olustur']) ||
        (nearby && n.contains('rota'));
    final wantsFavorites = _hasAny(n, const ['favori', 'favoriler']);

    final wantsAccommodation = kind != null ||
        _hasAny(n, const [
          'kalabilirim',
          'neredekalabilirim',
          'konaklama',
          'yatacak',
          'tesisleri',
          'tesisler',
        ]);

    // İsim sorgusu: şehir + tür + stopword çıkarıldıktan sonra kalanlar
    final stopKeys = <String>{
      'de',
      'da',
      'te',
      'ta',
      'nin',
      'in',
      'un',
      'icin',
      'ne',
      'nerede',
      'nasil',
      'bana',
      'bir',
      'en',
      'yakin',
      'yakinimdaki',
      'listele',
      'goster',
      'bul',
      'getir',
      'olustur',
      'bugun',
      'yapabilirim',
      'yerler',
      'yer',
      ...?kind?.matchKeys,
      if (wantsFood) ...['yemek', 'yenir', 'neyenir', 'yoresel'],
      if (wantsTourism) ...[
        'gezi',
        'geziler',
        'gezilecek',
        'yerler',
        'yer',
        'tarih',
        'tarihi',
        'turistik',
      ],
      if (wantsMunicipal) ...['belediye', 'sosyal', 'tesis', 'tesisleri'],
      if (wantsRoute) ...['rota', 'gidiyorum', 'dan', 'den', 'ye', 'ya'],
      if (nearby) ...['yakinimda', 'yakinda', 'civarda', 'yakinimdaki', 'etrafimda'],
      if (nearestOnly) ...['enyakin'],
      if (wantsAccommodation || nearby) ...[
        'tesis',
        'tesisler',
        'tesisleri',
        'kamutesis',
        'konaklama',
      ],
    };

    final nameTokens = <String>[];
    for (final t in tokens) {
      final nt = KamiFuzzySearch.norm(t);
      if (nt.isEmpty) continue;
      if (KamiFuzzySearch.correctCityToken(t, cityCatalog) != null) continue;
      if (cityCatalog.containsKey(nt)) continue;
      if (KamiFuzzySearch.cityTypos.containsKey(nt)) continue;
      if (stopKeys.contains(nt)) continue;
      if (kind != null && kind.matchKeys.any((k) => nt == k || nt.contains(k))) {
        continue;
      }
      // "ordu" tek başına tip kalıntısı olabilir
      if (nt == 'ordu' || nt == 'polis' || nt == 'ogretmen') continue;
      nameTokens.add(t);
    }

    // İlçe: basit — ikinci yerleşim değilse isimde kalan uzun token (ileride genişletilebilir)
    String? district;
    // Name query: kalan tokenlar birleşik
    final nameQuery = nameTokens.join(' ').trim();

    return KamiEntities(
      cities: cities,
      fromCity: fromCity,
      toCity: toCity,
      district: district,
      facilityKind: kind,
      nameQuery: nameQuery,
      nearby: nearby,
      nearestOnly: nearestOnly || n.contains('enyakin'),
      wantsFood: wantsFood,
      wantsTourism: wantsTourism,
      wantsMunicipal: wantsMunicipal || wantsBreakfast,
      wantsAccommodation: wantsAccommodation,
      wantsRoute: wantsRoute,
      wantsBreakfast: wantsBreakfast,
      wantsScenic: wantsScenic,
      wantsFavorites: wantsFavorites,
      wantsHistory: wantsHistory,
      rawText: text,
    );
  }

  static bool _hasAny(String haystackNorm, List<String> needles) {
    for (final raw in needles) {
      final n = KamiFuzzySearch.norm(raw);
      if (n.isNotEmpty && haystackNorm.contains(n)) return true;
    }
    return false;
  }
}
