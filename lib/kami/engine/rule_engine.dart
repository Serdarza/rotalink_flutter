import 'package:latlong2/latlong.dart';

import '../../models/sosyal_item.dart';
import '../recommendation/distance_service.dart';
import '../recommendation/kami_recommendation_service.dart';
import '../recommendation/trip_score_service.dart';
import 'accommodation_service.dart';
import 'food_service.dart';
import 'fuzzy_search.dart';
import 'kami_constants.dart';
import 'kami_database_query.dart';
import 'kami_departure_city.dart';
import 'kami_nearby_query.dart';
import 'kami_neighbor_region.dart';
import 'kami_entities.dart';
import 'kami_models.dart';
import 'location_service.dart';
import 'municipal_service.dart';
import 'route_service.dart';
import 'search_engine.dart';
import 'tourism_service.dart';

/// Niyet → doğru servis(ler) — sadece uygulama verisi.
class KamiRuleEngine {
  KamiRuleEngine({
    KamiLocationService? location,
    KamiRouteService? route,
    KamiFoodService? food,
    KamiAccommodationService? accommodation,
    KamiTourismService? tourism,
    KamiMunicipalService? municipal,
    KamiRecommendationService? recommendations,
  })  : location = location ?? const KamiLocationService(),
        route = route ?? KamiRouteService(),
        food = food ?? const KamiFoodService(),
        accommodation = accommodation ?? const KamiAccommodationService(),
        tourism = tourism ?? const KamiTourismService(),
        municipal = municipal ?? const KamiMunicipalService(),
        recommendations = recommendations ?? const KamiRecommendationService();

  final KamiLocationService location;
  final KamiRouteService route;
  final KamiFoodService food;
  final KamiAccommodationService accommodation;
  final KamiTourismService tourism;
  final KamiMunicipalService municipal;
  final KamiRecommendationService recommendations;

  Future<KamiPayload> execute({
    required DetectedIntent intent,
    required KamiQueryContext context,
  }) async {
    switch (intent.type) {
      case KamiIntentType.food:
        return _food(intent, context);
      case KamiIntentType.accommodation:
        return _accommodation(intent, context);
      case KamiIntentType.cityOverview:
        return _cityOverview(intent, context);
      case KamiIntentType.sightseeing:
        return _sightseeing(intent, context);
      case KamiIntentType.nearbyMunicipal:
        return _nearbyMunicipal(intent, context);
      case KamiIntentType.nearbyFacilities:
        return _nearbyFacilities(intent, context);
      case KamiIntentType.nearbyExplore:
        return _nearbyExplore(intent, context);
      case KamiIntentType.facilitySearch:
        return _facilitySearch(intent, context);
      case KamiIntentType.route:
        return _route(intent, context);
      case KamiIntentType.weekendTrip:
        return _weekend(intent, context);
      case KamiIntentType.help:
        return KamiPayload(
          intent: KamiIntentType.help,
          title: 'KAMİ ne yapabilir?',
          subtitle: intent.city != null
              ? '${intent.city} için yemek, gezi, konaklama veya belediye tesisi sorabilirsiniz. Tüm cevaplar Rotalink veritabanından gelir.'
              : 'Örnek: "İstanbul orduevi", "Kayseri\'de ne yenir?", "Ankara gezilecek yerler", "Yakınımdaki öğretmenevleri".',
          cities: intent.city != null ? [intent.city!] : const [],
        );
      case KamiIntentType.databaseSearch:
        return _databaseSearch(intent, context);
      case KamiIntentType.unknown:
        return _unknownWithDatabaseFallback(intent, context);
    }
  }

  Future<KamiPayload> _cityOverview(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    final user = await location.resolveUserLocation(hint: context.userLocation);
    final city = intent.city ?? intent.entities?.primaryCity;
    if (city == null) {
      return const KamiPayload(
        intent: KamiIntentType.cityOverview,
        needsClarification: true,
        clarificationHint: 'Hangi il için bilgi istiyorsunuz? Örn: "Kayseri"',
      );
    }
    return KamiDatabaseQuery.cityOverview(
      data: context.data,
      city: city,
      user: user,
    );
  }

  Future<KamiPayload> _databaseSearch(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    final user = await location.resolveUserLocation(hint: context.userLocation);
    final result = KamiDatabaseQuery.searchAllCollections(
      data: context.data,
      rawQuery: intent.rawText,
      user: user,
      city: intent.city ?? intent.entities?.primaryCity,
    );
    return result ??
        const KamiPayload(
          intent: KamiIntentType.databaseSearch,
          emptyReason: 'Veritabanında eşleşen kayıt bulunamadı.',
        );
  }

  Future<KamiPayload> _unknownWithDatabaseFallback(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    final user = await location.resolveUserLocation(hint: context.userLocation);
    final e = intent.entities;

    // Bilinmeyen → önce şehir + gezi/tarih, sonra genel DB araması
    if (e != null && e.primaryCity != null && (e.wantsHistory || e.wantsTourism)) {
      final tourResult = await _sightseeing(
        DetectedIntent(
          type: KamiIntentType.sightseeing,
          city: e.primaryCity,
          confidence: 0.7,
          rawText: intent.rawText,
          entities: e,
        ),
        context,
      );
      if (!tourResult.isEmpty) return tourResult;
    }

    // İsim veya serbest metin → önce tesis araması
    if (e != null && e.hasNameQuery) {
      final facilityResult = await _facilitySearch(
        DetectedIntent(
          type: KamiIntentType.facilitySearch,
          city: e.primaryCity,
          confidence: 0.65,
          rawText: intent.rawText,
          entities: e,
        ),
        context,
      );
      if (!facilityResult.isEmpty) return facilityResult;
    }

    // Tüm koleksiyonlarda metin araması
    final dbResult = KamiDatabaseQuery.searchAllCollections(
      data: context.data,
      rawQuery: intent.rawText,
      user: user,
      city: e?.primaryCity,
    );
    if (dbResult != null && !dbResult.isEmpty) return dbResult;

    return const KamiPayload(
      intent: KamiIntentType.unknown,
      needsClarification: true,
      clarificationHint:
          'Sizi anlayamadım. Rotalink veritabanından aramak için örn: '
          '"İstanbul orduevi", "Kayseri\'de ne yenir?", "Ankara gezilecek yerler", '
          '"Yakınımdaki polisevleri".',
    );
  }

  Future<KamiPayload> _facilitySearch(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    final e = intent.entities ?? const KamiEntities();
    final user = await location.resolveUserLocation(hint: context.userLocation);
    final city = intent.city ?? e.primaryCity;
    final kind = e.facilityKind;

    // İl + konaklama isteği, tür/isim yok → tüm kamu tesisleri
    if (city != null &&
        kind == null &&
        !e.hasNameQuery &&
        (e.wantsAccommodation || e.nearby || e.nearestOnly)) {
      final items = accommodation.byCity(context.data, city, user: user);
      if (items.isEmpty) {
        return KamiPayload(
          intent: KamiIntentType.facilitySearch,
          title: '$city — Kamu tesisleri',
          cities: [city],
          emptyReason: '$city için uygun tesis bulunamadı.',
        );
      }
      return KamiPayload(
        intent: KamiIntentType.facilitySearch,
        title: '$city — Kamu tesisleri',
        subtitle: user != null
            ? '${items.length} tesis · size olan mesafeye göre'
            : '${items.length} tesis',
        cities: [city],
        facilities: items,
        userLocation: user,
      );
    }

    if ((e.nearby || e.nearestOnly) && city == null) {
      final resolved = await _resolveRegionalDeparture(
        intent,
        context,
        KamiIntentType.facilitySearch,
        requestLocationPermission: true,
      );
      if (resolved.clarify != null) return resolved.clarify!;
    }

    final departureCity = city ??
        (e.nearby || e.nearestOnly
            ? KamiDepartureCityResolver.resolve(
                cityFromIntent: intent.city ?? e.primaryCity,
                cityFromGps: user != null
                    ? KamiDepartureCityResolver.fromLocation(
                        user,
                        context.data,
                      )
                    : null,
              )
            : null);

    if ((e.nearby || e.nearestOnly) && user == null && departureCity == null) {
      return KamiDepartureCityResolver.clarificationPayload(
        KamiIntentType.facilitySearch,
      );
    }

    final results = KamiSearchEngine.searchFacilities(
      data: context.data,
      entities: KamiEntities(
        cities: departureCity != null ? [departureCity] : e.cities,
        fromCity: e.fromCity,
        toCity: e.toCity,
        district: e.district,
        facilityKind: kind,
        nameQuery: e.nameQuery,
        nearby: e.nearby,
        nearestOnly: e.nearestOnly,
        wantsAccommodation: e.wantsAccommodation,
        rawText: e.rawText,
      ),
      user: user,
      limit: e.nearestOnly ? 1 : 25,
    );

    if (results.isEmpty) {
      final tip = kind?.label ?? 'tesis';
      final where = city != null ? '$city için ' : '';
      return KamiPayload(
        intent: KamiIntentType.facilitySearch,
        title: city != null ? '$city — $tip' : tip,
        cities: city != null ? [city] : const [],
        emptyReason: '${where}uygun $tip kaydı bulunamadı.',
      );
    }

    final title = _facilitySearchTitle(
      city: city,
      kind: kind,
      nameQuery: e.nameQuery,
      nearestOnly: e.nearestOnly,
      nearby: e.nearby,
      count: results.length,
    );

    return KamiPayload(
      intent: KamiIntentType.facilitySearch,
      title: title,
      subtitle: user != null
          ? (e.nearestOnly
              ? 'Konumunuza en yakın sonuç'
              : 'Mesafeye göre sıralı')
          : '${results.length} sonuç',
      cities: city != null ? [city] : const [],
      facilities: results,
      userLocation: user,
    );
  }

  String _facilitySearchTitle({
    required String? city,
    required KamiFacilityKind? kind,
    required String nameQuery,
    required bool nearestOnly,
    required bool nearby,
    required int count,
  }) {
    if (nearestOnly) {
      return kind != null
          ? 'En yakın ${kind.label.toLowerCase()}'
          : 'En yakın kamu tesisi';
    }
    if (nearby && kind != null) {
      return 'Yakınımdaki ${kind.label.toLowerCase()}ler';
    }
    if (nameQuery.isNotEmpty && city != null) {
      return '$city — $nameQuery';
    }
    if (nameQuery.isNotEmpty) {
      return nameQuery;
    }
    if (city != null && kind != null) {
      return '$city — ${kind.label}';
    }
    if (kind != null) {
      return kind.label;
    }
    if (city != null) {
      return '$city — Kamu tesisleri';
    }
    return 'Arama sonuçları ($count)';
  }

  Future<KamiPayload> _food(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    final user = await location.resolveUserLocation(hint: context.userLocation);
    final e = intent.entities;
    final nearby = e?.nearby == true || e?.nearestOnly == true;

    if (nearby) {
      final resolved = await _resolveRegionalDeparture(
        intent,
        context,
        KamiIntentType.food,
        requestLocationPermission: true,
      );
      if (resolved.clarify != null) return resolved.clarify!;
      final home = resolved.homeCity!;
      var items = KamiNearbyQuery.yemek(
        context.data,
        resolved.user!,
        homeCity: home,
      );
      if (items.isEmpty) {
        return KamiPayload(
          intent: KamiIntentType.food,
          title: '$home çevresi — Yöresel yemekler',
          emptyReason:
              '$home ve komşu illerde yemek önerisi bulunamadı.',
          userLocation: resolved.user,
          cities: [home],
        );
      }
      return KamiPayload(
        intent: KamiIntentType.food,
        title: '$home çevresi — Yöresel yemekler',
        subtitle: KamiNeighborRegion.regionalSubtitle(
          homeCity: home,
          totalCount: items.length,
        ),
        yemek: items,
        userLocation: resolved.user,
        cities: [home],
      );
    }

    final city = await _cityFromIntentOrGps(intent, context, user);
    if (city == null) {
      return const KamiPayload(
        intent: KamiIntentType.food,
        needsLocation: true,
        clarificationHint:
            'Yemek önerisi için konum gerekir. Alternatif: "Kayseri\'de ne yenir?"',
      );
    }
    final items = food.byCity(
      context.data,
      city,
      limit: KamiConstants.cityResultLimit,
    );
    if (items.isEmpty) {
      return KamiPayload(
        intent: KamiIntentType.food,
        title: '$city — Yöresel yemekler',
        cities: [city],
        emptyReason: '$city için şu an yöresel yemek önerisi bulunamadı.',
        userLocation: user,
      );
    }
    return KamiPayload(
      intent: KamiIntentType.food,
      title: '$city — Yöresel yemekler',
      subtitle: intent.city == null
          ? 'Konumunuza göre · ${items.length} öneri'
          : '${items.length} öneri',
      cities: [city],
      yemek: items,
      userLocation: user,
    );
  }

  Future<KamiPayload> _accommodation(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    final user = await location.resolveUserLocation(hint: context.userLocation);
    final city = await _cityFromIntentOrGps(intent, context, user);
    if (city == null) {
      return const KamiPayload(
        intent: KamiIntentType.accommodation,
        needsLocation: true,
        clarificationHint:
            'Misafirhane listesi için konum gerekir. Alternatif: "Kayseri misafirhaneleri"',
      );
    }
    final items = accommodation.byCity(
      context.data,
      city,
      user: user,
    );
    if (items.isEmpty) {
      return KamiPayload(
        intent: KamiIntentType.accommodation,
        title: '$city — Kamu misafirhaneleri',
        cities: [city],
        emptyReason: '$city için şu an kamu misafirhanesi önerisi bulunamadı.',
        userLocation: user,
      );
    }
    return KamiPayload(
      intent: KamiIntentType.accommodation,
      title: '$city — Kamu misafirhaneleri',
      subtitle: user != null
          ? '${items.length} tesis · size olan mesafeye göre sıralı'
          : '${items.length} tesis',
      cities: [city],
      facilities: items,
      userLocation: user,
    );
  }

  Future<KamiPayload> _sightseeing(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    final user = await location.resolveUserLocation(hint: context.userLocation);
    final e = intent.entities;
    final nearby = e?.nearby == true || e?.nearestOnly == true;
    final history = e?.wantsHistory == true;

    if (nearby) {
      final resolved = await _resolveRegionalDeparture(
        intent,
        context,
        KamiIntentType.sightseeing,
        requestLocationPermission: true,
      );
      if (resolved.clarify != null) return resolved.clarify!;
      final home = resolved.homeCity!;
      var items = KamiNearbyQuery.gezi(
        context.data,
        resolved.user!,
        homeCity: home,
      );
      items = KamiNearbyQuery.filterGeziTopic(
        items,
        history: history,
        queryNorm: KamiFuzzySearch.norm(intent.rawText),
      );
      if (items.isEmpty) {
        return KamiPayload(
          intent: KamiIntentType.sightseeing,
          title: history
              ? '$home çevresi — Tarihi yerler'
              : '$home çevresi — Gezilecek yerler',
          emptyReason:
              '$home ve komşu illerde gezi yeri bulunamadı.',
          userLocation: resolved.user,
          cities: [home],
        );
      }
      return KamiPayload(
        intent: KamiIntentType.sightseeing,
        title: history
            ? '$home çevresi — Tarihi yerler'
            : '$home çevresi — Gezilecek yerler',
        subtitle: KamiNeighborRegion.regionalSubtitle(
          homeCity: home,
          totalCount: items.length,
        ),
        gezi: items,
        userLocation: resolved.user,
        cities: [home],
      );
    }

    final city = await _cityFromIntentOrGps(intent, context, user);
    if (city == null) {
      return const KamiPayload(
        intent: KamiIntentType.sightseeing,
        needsLocation: true,
        clarificationHint:
            'Gezi önerisi için konum gerekir. Alternatif: "Konya gezilecek yerler"',
      );
    }
    final items = KamiNearbyQuery.filterGeziTopic(
      tourism.byCity(context.data, city, limit: KamiConstants.cityResultLimit),
      history: history || e?.wantsHistory == true,
      queryNorm: KamiFuzzySearch.norm(intent.rawText),
    );
    if (items.isEmpty) {
      return KamiPayload(
        intent: KamiIntentType.sightseeing,
        title: history ? '$city — Tarihi yerler' : '$city — Gezilecek yerler',
        cities: [city],
        emptyReason: history
            ? '$city için tarihi yer kaydı bulunamadı.'
            : '$city için şu an gezi önerisi bulunamadı.',
        userLocation: user,
      );
    }
    return KamiPayload(
      intent: KamiIntentType.sightseeing,
      title: history ? '$city — Tarihi yerler' : '$city — Gezilecek yerler',
      subtitle: '${items.length} yer · Rotalink veritabanı',
      cities: [city],
      gezi: items,
      userLocation: user,
    );
  }

  Future<KamiPayload> _nearbyExplore(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    final resolved = await _resolveRegionalDeparture(
      intent,
      context,
      KamiIntentType.nearbyExplore,
      requestLocationPermission: true,
    );
    if (resolved.clarify != null) return resolved.clarify!;
    return KamiNearbyQuery.exploreNearby(
      data: context.data,
      user: resolved.user!,
      homeCity: resolved.homeCity!,
    );
  }

  Future<KamiPayload> _nearbyMunicipal(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    final e = intent.entities;
    final resolved = await _resolveRegionalDeparture(
      intent,
      context,
      KamiIntentType.nearbyMunicipal,
      requestLocationPermission: true,
    );
    if (resolved.clarify != null) return resolved.clarify!;

    final homeCity = resolved.homeCity!;
    final user = resolved.user!;

    List<SosyalItem> items = KamiNearbyQuery.sosyal(
      context.data,
      user,
      homeCity: homeCity,
    );
    if (e?.wantsScenic == true || e?.wantsBreakfast == true) {
      items = items.where((s) {
        final h = KamiFuzzySearch.norm('${s.isim} ${s.aciklama}');
        if (e?.wantsBreakfast == true &&
            !(h.contains('kahvalti') || h.contains('kahvaltı'))) {
          return false;
        }
        if (e?.wantsScenic == true &&
            !(h.contains('manzara') || h.contains('manzarali'))) {
          return false;
        }
        return true;
      }).toList();
    }

    if (items.isEmpty) {
      final tag = e?.wantsBreakfast == true
          ? 'kahvaltı'
          : (e?.wantsScenic == true ? 'manzaralı' : '');
      return KamiPayload(
        intent: KamiIntentType.nearbyMunicipal,
        title: '$homeCity çevresi — Belediye sosyal tesisleri',
        cities: [homeCity],
        emptyReason: tag.isNotEmpty
            ? '$homeCity ve komşu illerde $tag belediye tesisi bulunamadı.'
            : '$homeCity ve komşu illerde belediye sosyal tesisi bulunamadı.',
        userLocation: user,
      );
    }

    var title = '$homeCity çevresi — Belediye sosyal tesisleri';
    if (e?.wantsBreakfast == true) {
      title = '$homeCity çevresi — Kahvaltı önerileri';
    } else if (e?.wantsScenic == true) {
      title = '$homeCity çevresi — Manzaralı tesisler';
    }

    return KamiPayload(
      intent: KamiIntentType.nearbyMunicipal,
      title: title,
      subtitle: KamiNeighborRegion.regionalSubtitle(
        homeCity: homeCity,
        totalCount: items.length,
      ),
      cities: [homeCity],
      sosyal: items,
      userLocation: user,
    );
  }

  Future<KamiPayload> _nearbyFacilities(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    if (intent.city != null) {
      return _accommodation(intent, context);
    }
    final resolved = await _resolveRegionalDeparture(
      intent,
      context,
      KamiIntentType.nearbyFacilities,
      requestLocationPermission: true,
    );
    if (resolved.clarify != null) return resolved.clarify!;

    final homeCity = resolved.homeCity!;
    final user = resolved.user!;
    final items = KamiNearbyQuery.facilities(
      context.data,
      user,
      homeCity: homeCity,
    );
    if (items.isEmpty) {
      return KamiPayload(
        intent: KamiIntentType.nearbyFacilities,
        title: '$homeCity çevresi — Kamu tesisleri',
        cities: [homeCity],
        emptyReason:
            '$homeCity ve komşu illerde kamu misafirhanesi bulunamadı. İl adı ile aramayı deneyin: "Kayseri tesisleri"',
        userLocation: user,
      );
    }
    return KamiPayload(
      intent: KamiIntentType.nearbyFacilities,
      title: '$homeCity çevresi — Kamu tesisleri',
      subtitle: KamiNeighborRegion.regionalSubtitle(
        homeCity: homeCity,
        totalCount: items.length,
      ),
      cities: [homeCity],
      facilities: items,
      userLocation: user,
    );
  }

  Future<KamiPayload> _route(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    if (!intent.hasRouteCities) {
      final cityFromIntent = intent.city ?? intent.entities?.primaryCity;
      LatLng? user;
      String? homeCity = cityFromIntent?.trim().isNotEmpty == true
          ? cityFromIntent!.trim()
          : null;

      if (homeCity == null) {
        user = await location.resolveForUserAction(
          hint: context.userLocation,
        );
        homeCity = user != null
            ? KamiDepartureCityResolver.fromLocation(user, context.data)
            : null;
      } else {
        user = await location.resolveUserLocation(hint: context.userLocation);
      }

      if (homeCity == null || homeCity.trim().isEmpty) {
        return KamiDepartureCityResolver.clarificationPayload(
          KamiIntentType.route,
        );
      }

      user ??= await location.resolveForUserAction(
        hint: context.userLocation,
      );
      user ??= KamiDistanceService.centerForCity(homeCity, context.data);
      if (user == null) {
        return KamiDepartureCityResolver.clarificationPayload(
          KamiIntentType.route,
        );
      }

      final scored = recommendations.nearbyRouteSuggestions(
        data: context.data,
        user: user,
        homeCity: homeCity,
      );
      if (scored.isEmpty) {
        return KamiPayload(
          intent: KamiIntentType.route,
          title: '$homeCity çevresi — Rota önerileri',
          cities: [homeCity],
          emptyReason:
              '$homeCity ile komşu illerde rota hedefi bulunamadı. İki il yazın: "Ankara\'dan Kayseri\'ye"',
          userLocation: user,
        );
      }
      return KamiPayload(
        intent: KamiIntentType.route,
        title: '$homeCity çevresi — Rota önerileri',
        subtitle: KamiNeighborRegion.regionalSubtitle(
          homeCity: homeCity,
          totalCount: scored.length,
          neighborProvinceCount: scored.length,
        ),
        cities: [homeCity, for (final s in scored) s.city],
        cityScores: scored,
        userLocation: user,
      );
    }

    final sections = await route.buildCityRoute(
      data: context.data,
      fromCity: intent.fromCity!,
      toCity: intent.toCity!,
    );
    final alongOnly = sections.where((s) => s.roleLabel != 'Başlangıç').toList();
    return KamiPayload(
      intent: KamiIntentType.route,
      title: '${intent.toCity}',
      subtitle: 'Yol üzeri ve varış önerileri',
      cities: [
        ...alongOnly
            .where((s) => s.roleLabel == 'Yol üzeri')
            .map((s) => s.city),
        intent.toCity!,
      ],
      routeSections: alongOnly,
    );
  }

  Future<KamiPayload> _weekend(
    DetectedIntent intent,
    KamiQueryContext context,
  ) async {
    if (intent.city != null) {
      final city = intent.city!;
      return KamiPayload(
        intent: KamiIntentType.weekendTrip,
        title: 'Hafta sonu önerisi',
        subtitle: city,
        cities: [city],
        facilities: accommodation.byCity(context.data, city, limit: 4),
        gezi: tourism.byCity(context.data, city, limit: 5),
        yemek: food.byCity(context.data, city, limit: 4),
        sosyal: municipal.byCity(context.data, city, limit: 3),
      );
    }

    final user = await location.resolveUserLocation(hint: context.userLocation);
    if (user == null) {
      return const KamiPayload(
        intent: KamiIntentType.weekendTrip,
        needsLocation: true,
        clarificationHint:
            'Hafta sonu önerisi için konum gerekir. Alternatif: "Eskişehir hafta sonu öner"',
      );
    }

    final scored = recommendations.weekendSuggestions(
      data: context.data,
      user: user,
      filters: _filtersFromText(intent.rawText),
    );
    if (scored.isEmpty) {
      return const KamiPayload(
        intent: KamiIntentType.weekendTrip,
        title: 'Hafta sonu önerileri',
        emptyReason:
            'Konumunuza yakın, Rotalink verisinde içerik bulunan destinasyon bulunamadı.',
      );
    }

    return KamiPayload(
      intent: KamiIntentType.weekendTrip,
      title: 'Hafta sonu önerileri',
      subtitle: 'Çevrenizdeki illerden öneriler',
      cities: [for (final s in scored) s.city],
      cityScores: scored,
      userLocation: user,
    );
  }

  /// Bölgesel öneriler için çıkış ili — [KamiSystemInstruction] kural 1.
  Future<
      ({
        String? homeCity,
        LatLng? user,
        KamiPayload? clarify,
      })> _resolveRegionalDeparture(
    DetectedIntent intent,
    KamiQueryContext context,
    KamiIntentType intentType, {
    bool requestLocationPermission = false,
  }) async {
    final cityFromIntent = intent.city ?? intent.entities?.primaryCity;
    LatLng? user;

    if (cityFromIntent == null || cityFromIntent.trim().isEmpty) {
      user = requestLocationPermission
          ? await location.resolveForUserAction(hint: context.userLocation)
          : await location.resolveUserLocation(hint: context.userLocation);
    } else {
      user = await location.resolveUserLocation(hint: context.userLocation);
    }

    final cityFromGps = KamiDepartureCityResolver.fromLocation(
      user,
      context.data,
    );
    final homeCity = KamiDepartureCityResolver.resolve(
      cityFromIntent: cityFromIntent,
      cityFromGps: cityFromGps,
    );

    if (homeCity == null) {
      return (
        homeCity: null,
        user: user,
        clarify: KamiDepartureCityResolver.clarificationPayload(intentType),
      );
    }

    if (user == null) {
      user = KamiDistanceService.centerForCity(homeCity, context.data);
    }
    if (user == null) {
      return (
        homeCity: homeCity,
        user: null,
        clarify: KamiDepartureCityResolver.clarificationPayload(intentType),
      );
    }

    return (homeCity: homeCity, user: user, clarify: null);
  }

  /// İl yoksa GPS / veri merkezine göre en yakın ili kullan.
  Future<String?> _cityFromIntentOrGps(
    DetectedIntent intent,
    KamiQueryContext context,
    LatLng? user,
  ) async {
    if (intent.city != null && intent.city!.trim().isNotEmpty) {
      return intent.city;
    }
    final loc = user ??
        await location.resolveUserLocation(hint: context.userLocation);
    if (loc == null) return null;
    return KamiDistanceService.resolveHomeCity(loc, context.data);
  }

  Set<KamiTripFilter> _filtersFromText(String raw) {
    final n = raw.toLowerCase();
    final out = <KamiTripFilter>{};
    if (n.contains('doğa') || n.contains('doga')) out.add(KamiTripFilter.nature);
    if (n.contains('tarih')) out.add(KamiTripFilter.history);
    if (n.contains('yemek') || n.contains('lezzet')) out.add(KamiTripFilter.food);
    if (n.contains('deniz') || n.contains('sahil')) out.add(KamiTripFilter.sea);
    if (n.contains('kamp')) out.add(KamiTripFilter.camp);
    if (n.contains('aile')) out.add(KamiTripFilter.family);
    if (n.contains('romantik')) out.add(KamiTripFilter.romantic);
    if (n.contains('foto')) out.add(KamiTripFilter.photo);
    if (n.contains('2 saat') || n.contains('2saat')) {
      out.add(KamiTripFilter.under2h);
    }
    if (n.contains('300')) out.add(KamiTripFilter.under300km);
    if (n.contains('konaklama')) out.add(KamiTripFilter.withStay);
    if (n.contains('günübirlik') || n.contains('gunubirlik')) {
      out.add(KamiTripFilter.dayTrip);
    }
    return out;
  }
}
