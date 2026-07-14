import '../../data/firebase_rota_repository.dart';
import '../../models/gezi_yemek_item.dart';
import '../../models/misafirhane.dart';
import '../../models/sosyal_item.dart';
import '../engine/city_resolver.dart';
import '../engine/fuzzy_search.dart';

/// Hafta sonu / gezi il puanlaması — yalnızca RTDB metin + sayımlar.
abstract final class KamiTripScoreService {
  static const Map<String, int> tagWeights = {
    'unesco': 18,
    'dunyamirasi': 16,
    'dogal': 8,
    'tabiat': 8,
    'millipark': 14,
    'gol': 10,
    'sahil': 12,
    'deniz': 12,
    'plaj': 10,
    'muze': 9,
    'selale': 11,
    'kanyon': 12,
    'yayla': 10,
    'kale': 8,
    'antik': 12,
    'antikkent': 14,
    'kamp': 9,
    'piknik': 7,
    'manzara': 8,
    'tarihi': 9,
    'tarih': 7,
    'osmanli': 6,
    'roma': 6,
    'abant': 6,
    'yedigoller': 8,
    'golcuk': 5,
  };

  static KamiCityScore scoreCity({
    required RotaDataState data,
    required String city,
    required double distanceKm,
  }) {
    final gezi = data.gezi
        .where((g) => KamiCityResolver.sameCity(g.il, city))
        .toList();
    final yemek = data.yemek
        .where((y) => KamiCityResolver.sameCity(y.il, city))
        .toList();
    final sosyal = data.sosyal
        .where((s) => KamiCityResolver.sameCity(s.il, city))
        .toList();
    final tesis = _facilities(data, city);

    var ogretmen = 0;
    var ordu = 0;
    var polis = 0;
    var misafir = 0;
    for (final m in tesis) {
      final hay = KamiFuzzySearch.norm('${m.tip} ${m.isim}');
      if (hay.contains('ogretmenevi') || hay.contains('ogretmen')) {
        ogretmen++;
      } else if (hay.contains('orduevi')) {
        ordu++;
      } else if (hay.contains('polisevi')) {
        polis++;
      } else {
        misafir++;
      }
    }

    var score = 0;
    score += gezi.length * 4;
    score += yemek.length * 3;
    score += sosyal.length * 2;
    score += tesis.length * 3;
    score += ogretmen * 2;
    score += ordu * 2;
    score += polis * 2;
    score += misafir * 2;

    final highlights = <String>[];
    final tagHits = <String, int>{};

    void scanText(String raw) {
      final h = KamiFuzzySearch.norm(raw);
      for (final e in tagWeights.entries) {
        if (h.contains(e.key)) {
          tagHits[e.key] = (tagHits[e.key] ?? 0) + 1;
        }
      }
    }

    for (final g in gezi) {
      scanText('${g.isim} ${g.aciklama} ${g.tur ?? ''}');
    }
    for (final s in sosyal) {
      scanText('${s.isim} ${s.aciklama}');
    }
    for (final y in yemek) {
      scanText('${y.isim} ${y.aciklama}');
    }

    for (final e in tagHits.entries) {
      final w = tagWeights[e.key] ?? 0;
      score += w * (e.value.clamp(1, 3));
      if (highlights.length < 6) {
        highlights.add(_prettyTag(e.key));
      }
    }

    // İçerik + etiketlerden sonra mesafe ağırlıklı bonus.
    // Yakın iller (≤100 km) güçlü; uzak iller cezalandırılır.
    final proximity = _proximityBonus(distanceKm);
    score += proximity;

    final placeNames = <String>[];
    for (final g in gezi.take(4)) {
      if (g.isim.trim().isNotEmpty) placeNames.add(g.isim.trim());
    }

    return KamiCityScore(
      city: city,
      score: score.clamp(0, 999),
      distanceKm: distanceKm,
      geziCount: gezi.length,
      yemekCount: yemek.length,
      sosyalCount: sosyal.length,
      facilityCount: tesis.length,
      ogretmeneviCount: ogretmen,
      ordueviCount: ordu,
      poliseviCount: polis,
      misafirhaneCount: misafir,
      highlights: [
        ...highlights,
        ...placeNames.where((p) => !highlights.contains(p)),
      ].take(6).toList(),
      gezi: gezi,
      yemek: yemek,
      sosyal: sosyal,
      facilities: tesis,
      tagHits: tagHits,
    );
  }

  static bool matchesFilter(KamiCityScore s, KamiTripFilter filter) {
    final blob = KamiFuzzySearch.norm(
      [
        ...s.highlights,
        ...s.tagHits.keys,
        for (final g in s.gezi) '${g.isim} ${g.aciklama}',
        for (final y in s.yemek) '${y.isim} ${y.aciklama}',
        for (final so in s.sosyal) '${so.isim} ${so.aciklama}',
      ].join(' '),
    );

    switch (filter) {
      case KamiTripFilter.nature:
        return _any(blob, const [
          'dogal',
          'tabiat',
          'milli',
          'gol',
          'yayla',
          'orman',
          'selale',
          'kanyon',
        ]);
      case KamiTripFilter.history:
        return _any(blob, const [
          'tarih',
          'antik',
          'kale',
          'unesco',
          'muze',
          'osmanli',
          'roma',
        ]);
      case KamiTripFilter.food:
        return s.yemekCount > 0 || s.sosyalCount > 0;
      case KamiTripFilter.sea:
        return _any(blob, const ['deniz', 'sahil', 'plaj', 'liman']);
      case KamiTripFilter.camp:
        return _any(blob, const ['kamp', 'cadir', 'piknik']);
      case KamiTripFilter.family:
        return s.geziCount + s.sosyalCount >= 3;
      case KamiTripFilter.romantic:
        return _any(blob, const ['manzara', 'gol', 'sahil', 'romant']);
      case KamiTripFilter.photo:
        return _any(blob, const ['manzara', 'foto', 'seyir', 'panoram']);
      case KamiTripFilter.under2h:
        return s.estimatedDriveMinutes <= 120;
      case KamiTripFilter.under300km:
        return s.distanceKm <= 300;
      case KamiTripFilter.withStay:
        return s.facilityCount > 0;
      case KamiTripFilter.dayTrip:
        return s.estimatedDriveMinutes <= 150;
    }
  }

  static bool _any(String hay, List<String> keys) => keys.any(hay.contains);

  /// 0–80 km: yüksek; 140+ hızla düşer — uzak zengin iller şişmesin.
  static int _proximityBonus(double distanceKm) {
    if (distanceKm <= 80) return 90;
    if (distanceKm <= 120) return 70;
    if (distanceKm <= 160) return 45;
    if (distanceKm <= 200) return 20;
    if (distanceKm <= 250) return 5;
    return 0;
  }

  static List<Misafirhane> _facilities(RotaDataState data, String city) {
    final src = data.aramaIcinTumTesisler.isNotEmpty
        ? data.aramaIcinTumTesisler
        : data.misafirhaneler;
    return src.where((m) => KamiCityResolver.sameCity(m.il, city)).toList();
  }

  static String _prettyTag(String key) {
    switch (KamiFuzzySearch.norm(key)) {
      case 'unesco':
      case 'dunyamirasi':
        return 'UNESCO / Dünya Mirası';
      case 'millipark':
        return 'Milli park';
      case 'gol':
        return 'Göl';
      case 'sahil':
      case 'deniz':
      case 'plaj':
        return 'Sahil';
      case 'muze':
        return 'Müze';
      case 'selale':
        return 'Şelale';
      case 'kanyon':
        return 'Kanyon';
      case 'yayla':
        return 'Yayla';
      case 'kamp':
        return 'Kamp';
      case 'piknik':
        return 'Piknik';
      case 'manzara':
        return 'Manzara';
      case 'antik':
      case 'antikkent':
        return 'Antik kent';
      case 'kale':
        return 'Kale';
      case 'tarihi':
      case 'tarih':
        return 'Tarihi yer';
      default:
        return key;
    }
  }
}

enum KamiTripFilter {
  nature,
  history,
  food,
  sea,
  camp,
  family,
  romantic,
  photo,
  under2h,
  under300km,
  withStay,
  dayTrip,
}

extension KamiTripFilterX on KamiTripFilter {
  String get label {
    switch (this) {
      case KamiTripFilter.nature:
        return '🌿 Doğa';
      case KamiTripFilter.history:
        return '🏛 Tarih';
      case KamiTripFilter.food:
        return '🍽 Yemek';
      case KamiTripFilter.sea:
        return '🏖 Deniz';
      case KamiTripFilter.camp:
        return '🏕 Kamp';
      case KamiTripFilter.family:
        return '👨‍👩‍👧 Aile';
      case KamiTripFilter.romantic:
        return '💑 Romantik';
      case KamiTripFilter.photo:
        return '📷 Fotoğraf';
      case KamiTripFilter.under2h:
        return '🚗 2 saatten yakın';
      case KamiTripFilter.under300km:
        return '🚙 300 km altı';
      case KamiTripFilter.withStay:
        return '🛏 Konaklamalı';
      case KamiTripFilter.dayTrip:
        return '☀ Günübirlik';
    }
  }
}

class KamiCityScore {
  KamiCityScore({
    required this.city,
    required this.score,
    required this.distanceKm,
    required this.geziCount,
    required this.yemekCount,
    required this.sosyalCount,
    required this.facilityCount,
    required this.ogretmeneviCount,
    required this.ordueviCount,
    required this.poliseviCount,
    required this.misafirhaneCount,
    required this.highlights,
    required this.gezi,
    required this.yemek,
    required this.sosyal,
    required this.facilities,
    required this.tagHits,
  });

  final String city;
  final int score;
  final double distanceKm;
  final int geziCount;
  final int yemekCount;
  final int sosyalCount;
  final int facilityCount;
  final int ogretmeneviCount;
  final int ordueviCount;
  final int poliseviCount;
  final int misafirhaneCount;
  final List<String> highlights;
  final List<GeziYemekItem> gezi;
  final List<GeziYemekItem> yemek;
  final List<SosyalItem> sosyal;
  final List<Misafirhane> facilities;
  final Map<String, int> tagHits;

  int get estimatedDriveMinutes =>
      (distanceKm / 75 * 60).round().clamp(15, 24 * 60);

  String get driveLabel {
    final m = estimatedDriveMinutes;
    final h = m ~/ 60;
    final mm = m % 60;
    if (h <= 0) return '$mm dk';
    if (mm == 0) return '$h saat';
    return '$h saat $mm dk';
  }

  Map<String, Object?> toMap() => {
        'city': city,
        'score': score,
        'distanceKm': distanceKm,
        'geziCount': geziCount,
        'yemekCount': yemekCount,
        'sosyalCount': sosyalCount,
        'facilityCount': facilityCount,
        'highlights': highlights,
        'driveMinutes': estimatedDriveMinutes,
        'driveLabel': driveLabel,
      };

  static KamiCityScore? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final city = (m['city'] ?? '').toString().trim();
    if (city.isEmpty) return null;
    return KamiCityScore(
      city: city,
      score: (m['score'] as num?)?.toInt() ?? 0,
      distanceKm: (m['distanceKm'] as num?)?.toDouble() ?? 0,
      geziCount: (m['geziCount'] as num?)?.toInt() ?? 0,
      yemekCount: (m['yemekCount'] as num?)?.toInt() ?? 0,
      sosyalCount: (m['sosyalCount'] as num?)?.toInt() ?? 0,
      facilityCount: (m['facilityCount'] as num?)?.toInt() ?? 0,
      ogretmeneviCount: 0,
      ordueviCount: 0,
      poliseviCount: 0,
      misafirhaneCount: 0,
      highlights: [
        for (final h in (m['highlights'] as List? ?? const [])) h.toString(),
      ],
      gezi: const [],
      yemek: const [],
      sosyal: const [],
      facilities: const [],
      tagHits: const {},
    );
  }
}
