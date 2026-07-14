import 'entity_extractor.dart';
import 'fuzzy_search.dart';
import 'kami_models.dart';

/// Niyet analizi — EntityExtractor çıktısından intent üretir.
abstract final class KamiIntentDetector {
  static DetectedIntent detect(
    String rawText, {
    required Map<String, String> cityCatalog,
  }) {
    final text = rawText.trim();
    if (text.isEmpty) {
      return const DetectedIntent(type: KamiIntentType.unknown, confidence: 0);
    }

    final entities = KamiEntityExtractor.extract(
      text,
      cityCatalog: cityCatalog,
    );

    DetectedIntent wrap(
      KamiIntentType type, {
      double confidence = 0.85,
      String? city,
      String? from,
      String? to,
    }) {
      return DetectedIntent(
        type: type,
        city: city ?? entities.primaryCity,
        fromCity: from ?? entities.fromCity,
        toCity: to ?? entities.toCity,
        confidence: confidence,
        rawText: text,
        entities: entities,
      );
    }

    final n = KamiFuzzySearch.norm(text);
    final hasCity = entities.primaryCity != null;
    final nearby = entities.nearby || entities.nearestOnly;

    // Yemek
    if (entities.wantsFood && !entities.wantsMunicipal) {
      return wrap(KamiIntentType.food, confidence: 0.92);
    }

    // Belediye
    if (entities.wantsMunicipal || entities.wantsBreakfast) {
      return wrap(KamiIntentType.nearbyMunicipal, confidence: 0.9);
    }

    // Rota
    if (entities.wantsRoute) {
      return wrap(
        KamiIntentType.route,
        confidence: entities.hasRouteCities ? 0.95 : 0.92,
        from: entities.fromCity,
        to: entities.toCity,
      );
    }

    // Gezi / tarih — şehir veya yakın
    if (entities.wantsTourism && !entities.wantsScenic) {
      return wrap(KamiIntentType.sightseeing, confidence: 0.93);
    }
    if (entities.wantsScenic && !entities.wantsMunicipal) {
      return wrap(KamiIntentType.sightseeing, confidence: 0.85);
    }

    // Hafta sonu
    if (n.contains('haftasonu') ||
        (n.contains('hafta') &&
            (n.contains('nereye') ||
                n.contains('oner') ||
                n.contains('tavsiye'))) ||
        n.contains('nerenegidebilirim')) {
      return wrap(KamiIntentType.weekendTrip, confidence: 0.9);
    }

    // Yakınımdaki — kategoriye göre
    if (nearby) {
      if (entities.facilityKind != null ||
          entities.wantsAccommodation ||
          n.contains('tesis')) {
        return wrap(KamiIntentType.nearbyFacilities, confidence: 0.94);
      }
      if (entities.hasNameQuery) {
        return wrap(KamiIntentType.facilitySearch, confidence: 0.88);
      }
      // Genel yakınımdaki → tüm kategoriler
      return wrap(KamiIntentType.nearbyExplore, confidence: 0.91);
    }

    // Tesis araması
    final hasFacilitySignal = entities.facilityKind != null ||
        entities.hasNameQuery ||
        (entities.wantsAccommodation && hasCity);

    if (hasFacilitySignal) {
      return wrap(KamiIntentType.facilitySearch, confidence: 0.93);
    }

    // İl + konu (tarih vb.) veya sadece il özeti
    if (hasCity) {
      if (entities.wantsHistory ||
          entities.hasNameQuery ||
          n.contains('tarih') ||
          n.contains('gezi') ||
          n.contains('yer')) {
        return wrap(KamiIntentType.sightseeing, confidence: 0.88);
      }
      return wrap(KamiIntentType.cityOverview, confidence: 0.82);
    }

    if (entities.hasNameQuery) {
      return wrap(KamiIntentType.facilitySearch, confidence: 0.7);
    }

    if (n.contains('yardim') ||
        n.contains('merhaba') ||
        n.contains('selam') ||
        n.contains('neyapabilirsin')) {
      return wrap(KamiIntentType.help, confidence: 0.7);
    }

    return DetectedIntent(
      type: KamiIntentType.unknown,
      confidence: 0.1,
      rawText: text,
      entities: entities,
    );
  }
}
