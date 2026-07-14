import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import '../../models/gezi_yemek_item.dart';
import '../../models/misafirhane.dart';
import '../../models/sosyal_item.dart';
import 'accommodation_service.dart';
import 'city_resolver.dart';
import 'food_service.dart';
import 'fuzzy_search.dart';
import 'kami_models.dart';
import 'municipal_service.dart';
import 'tourism_service.dart';

/// Tek kaynak: tüm KAMİ cevapları yalnızca RTDB kayıtlarından üretilir.
abstract final class KamiDatabaseQuery {
  static const _accommodation = KamiAccommodationService();
  static const _food = KamiFoodService();
  static const _tourism = KamiTourismService();
  static const _municipal = KamiMunicipalService();

  /// Bir il için veritabanındaki tüm kategorilerden özet.
  static KamiPayload cityOverview({
    required RotaDataState data,
    required String city,
    LatLng? user,
    int facilityLimit = 8,
    int geziLimit = 6,
    int yemekLimit = 6,
    int sosyalLimit = 4,
  }) {
    final facilities = _accommodation.byCity(
      data,
      city,
      user: user,
      limit: facilityLimit,
    );
    final gezi = _tourism.byCity(data, city, limit: geziLimit);
    final yemek = _food.byCity(data, city, limit: yemekLimit);
    final sosyal = _municipal.byCity(data, city, limit: sosyalLimit);

    final totalFacilities = data.aramaIcinTumTesisler
        .where((m) => KamiCityResolver.sameCity(m.il, city))
        .length;
    final totalGezi =
        data.gezi.where((g) => KamiCityResolver.sameCity(g.il, city)).length;
    final totalYemek =
        data.yemek.where((y) => KamiCityResolver.sameCity(y.il, city)).length;
    final totalSosyal =
        data.sosyal.where((s) => KamiCityResolver.sameCity(s.il, city)).length;

    if (facilities.isEmpty &&
        gezi.isEmpty &&
        yemek.isEmpty &&
        sosyal.isEmpty) {
      return KamiPayload(
        intent: KamiIntentType.cityOverview,
        title: city,
        cities: [city],
        emptyReason:
            '$city için Rotalink veritabanında kayıt bulunamadı. Başka bir il veya tesis adı deneyin.',
        userLocation: user,
      );
    }

    final parts = <String>[];
    if (totalFacilities > 0) parts.add('$totalFacilities kamu tesisi');
    if (totalGezi > 0) parts.add('$totalGezi gezi yeri');
    if (totalYemek > 0) parts.add('$totalYemek yöresel yemek');
    if (totalSosyal > 0) parts.add('$totalSosyal belediye tesisi');

    return KamiPayload(
      intent: KamiIntentType.cityOverview,
      title: '$city — Rotalink veritabanı',
      subtitle: parts.join(' · '),
      cities: [city],
      facilities: facilities,
      gezi: gezi,
      yemek: yemek,
      sosyal: sosyal,
      userLocation: user,
    );
  }

  /// Bilinmeyen / belirsiz sorularda tüm koleksiyonlarda metin araması.
  static KamiPayload? searchAllCollections({
    required RotaDataState data,
    required String rawQuery,
    LatLng? user,
    String? city,
    int limit = 20,
  }) {
    final query = rawQuery.trim();
    if (query.length < 2) return null;

    final qNorm = KamiFuzzySearch.norm(query);
    if (qNorm.isEmpty) return null;

    final facilityHits = <({Misafirhane item, double score})>[];
    final geziHits = <({GeziYemekItem item, double score})>[];
    final yemekHits = <({GeziYemekItem item, double score})>[];
    final sosyalHits = <({SosyalItem item, double score})>[];

    final src = data.aramaIcinTumTesisler.isNotEmpty
        ? data.aramaIcinTumTesisler
        : data.misafirhaneler;

    for (final m in src) {
      if (city != null && !KamiCityResolver.sameCity(m.il, city)) continue;
      final score = _scoreText(
        qNorm,
        '${m.isim} ${m.tip} ${m.il} ${m.adres}',
      );
      if (score >= 0.4) facilityHits.add((item: m, score: score));
    }
    for (final g in data.gezi) {
      if (city != null && !KamiCityResolver.sameCity(g.il, city)) continue;
      final score = _scoreText(qNorm, '${g.isim} ${g.il} ${g.aciklama} ${g.adres}');
      if (score >= 0.4) geziHits.add((item: g, score: score));
    }
    for (final y in data.yemek) {
      if (city != null && !KamiCityResolver.sameCity(y.il, city)) continue;
      final score = _scoreText(qNorm, '${y.isim} ${y.il} ${y.aciklama} ${y.adres}');
      if (score >= 0.4) yemekHits.add((item: y, score: score));
    }
    for (final s in data.sosyal) {
      if (city != null && !KamiCityResolver.sameCity(s.il, city)) continue;
      final score = _scoreText(
        qNorm,
        '${s.isim} ${s.il} ${s.ilce} ${s.aciklama} ${s.adres}',
      );
      if (score >= 0.4) sosyalHits.add((item: s, score: score));
    }

    facilityHits.sort((a, b) => b.score.compareTo(a.score));
    geziHits.sort((a, b) => b.score.compareTo(a.score));
    yemekHits.sort((a, b) => b.score.compareTo(a.score));
    sosyalHits.sort((a, b) => b.score.compareTo(a.score));

    final bestCategory = _bestCategoryScore(
      facilityHits.isNotEmpty ? facilityHits.first.score : 0,
      geziHits.isNotEmpty ? geziHits.first.score : 0,
      yemekHits.isNotEmpty ? yemekHits.first.score : 0,
      sosyalHits.isNotEmpty ? sosyalHits.first.score : 0,
    );

    if (bestCategory == null) return null;

    switch (bestCategory) {
      case _DbCategory.facility:
        final list = [
          for (final h in facilityHits.take(limit)) h.item,
        ];
        return KamiPayload(
          intent: KamiIntentType.databaseSearch,
          title: 'Veritabanı araması',
          subtitle: '${list.length} kamu tesisi · "${_shortQuery(query)}"',
          facilities: list,
          userLocation: user,
        );
      case _DbCategory.gezi:
        final list = [for (final h in geziHits.take(limit)) h.item];
        return KamiPayload(
          intent: KamiIntentType.databaseSearch,
          title: 'Veritabanı araması',
          subtitle: '${list.length} gezi yeri · "${_shortQuery(query)}"',
          gezi: list,
          userLocation: user,
        );
      case _DbCategory.yemek:
        final list = [for (final h in yemekHits.take(limit)) h.item];
        return KamiPayload(
          intent: KamiIntentType.databaseSearch,
          title: 'Veritabanı araması',
          subtitle: '${list.length} yöresel yemek · "${_shortQuery(query)}"',
          yemek: list,
          userLocation: user,
        );
      case _DbCategory.sosyal:
        final list = [for (final h in sosyalHits.take(limit)) h.item];
        return KamiPayload(
          intent: KamiIntentType.databaseSearch,
          title: 'Veritabanı araması',
          subtitle: '${list.length} belediye tesisi · "${_shortQuery(query)}"',
          sosyal: list,
          userLocation: user,
        );
    }
  }

  static double _scoreText(String queryNorm, String haystack) {
    final hay = KamiFuzzySearch.norm(haystack);
    if (hay.isEmpty) return 0;
    if (hay.contains(queryNorm) && queryNorm.length >= 3) {
      return 0.95;
    }
    final tokens = queryNorm
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3)
        .toList();
    if (tokens.isEmpty) return 0;
    var matched = 0;
    for (final t in tokens) {
      if (hay.contains(t)) matched++;
    }
    final tokenScore = matched / tokens.length;
    final sim = KamiFuzzySearch.similarity(queryNorm, hay);
    return (tokenScore * 0.6 + sim * 0.4).clamp(0.0, 1.0);
  }

  static _DbCategory? _bestCategoryScore(
    double facility,
    double gezi,
    double yemek,
    double sosyal,
  ) {
    final scores = <_DbCategory, double>{
      _DbCategory.facility: facility,
      _DbCategory.gezi: gezi,
      _DbCategory.yemek: yemek,
      _DbCategory.sosyal: sosyal,
    };
    _DbCategory? best;
    var bestScore = 0.45;
    for (final e in scores.entries) {
      if (e.value > bestScore) {
        bestScore = e.value;
        best = e.key;
      }
    }
    return best;
  }

  static String _shortQuery(String q) {
    final t = q.trim();
    if (t.length <= 40) return t;
    return '${t.substring(0, 37)}...';
  }
}

enum _DbCategory { facility, gezi, yemek, sosyal }
