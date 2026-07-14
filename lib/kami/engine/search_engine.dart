import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import '../../models/misafirhane.dart';
import '../../models/sosyal_item.dart';
import '../../utils/geo_helpers.dart';
import '../../utils/safe_map_coordinates.dart';
import 'city_resolver.dart';
import 'fuzzy_search.dart';
import 'kami_entities.dart';
import 'kami_neighbor_region.dart';

/// Aranan kamu tesisinin sıralama sonucu.
class KamiFacilityHit {
  const KamiFacilityHit({
    required this.facility,
    required this.score,
    required this.rankReason,
  });

  final Misafirhane facility;
  final double score;
  final String rankReason;
}

/// Kamu tesisi / tesis türü akıllı arama — yalnızca DB kayıtları.
abstract final class KamiSearchEngine {
  /// Öncelik:
  /// 1 Tam tesis adı
  /// 2 İl + tür
  /// 3 İlçe + tür
  /// 4 Benzer isimler
  /// 5 Aynı kategoride alternatifler
  static List<Misafirhane> searchFacilities({
    required RotaDataState data,
    required KamiEntities entities,
    LatLng? user,
    int limit = 25,
  }) {
    final src = data.aramaIcinTumTesisler.isNotEmpty
        ? data.aramaIcinTumTesisler
        : data.misafirhaneler;
    if (src.isEmpty) return const [];

    final hits = <KamiFacilityHit>[];
    final nameQ = entities.nameQuery.trim();
    final nameNorm = KamiFuzzySearch.norm(nameQ);
    final city = entities.primaryCity;
    final kind = entities.facilityKind;
    final district = entities.district;

    for (final m in src) {
      final scored = _scoreFacility(
        m,
        nameNorm: nameNorm,
        nameRaw: nameQ,
        city: city,
        district: district,
        kind: kind,
      );
      if (scored == null) continue;
      hits.add(scored);
    }

    if (hits.isEmpty && kind != null && city != null) {
      // Sadece il + tür — isim boş olsa bile
      for (final m in src) {
        if (!KamiCityResolver.sameCity(m.il, city)) continue;
        if (!_matchesKind(m, kind)) continue;
        hits.add(
          KamiFacilityHit(
            facility: m,
            score: 70,
            rankReason: 'il_tur',
          ),
        );
      }
    }

    if (hits.isEmpty && kind != null && city == null && nameNorm.isEmpty) {
      // Tür bazlı arama yalnızca yakınlık modunda — aksi halde yanlış şehir riski.
      if (!entities.nearby && !entities.nearestOnly) {
        // Atla
      } else {
        for (final m in src) {
          if (!_matchesKind(m, kind)) continue;
          hits.add(
            KamiFacilityHit(facility: m, score: 40, rankReason: 'tur'),
          );
        }
      }
    }

    if (hits.isEmpty && nameNorm.isNotEmpty) {
      // Saf isim fuzzy — şehir yoksa daha sıkı eşik (yanlış eşleşme önlenir).
      final minSim = city != null ? 0.68 : 0.78;
      for (final m in src) {
        if (city != null && !KamiCityResolver.sameCity(m.il, city)) continue;
        final s = KamiFuzzySearch.similarity(m.isim, nameQ);
        if (s < minSim) continue;
        hits.add(
          KamiFacilityHit(
            facility: m,
            score: 50 + s * 40,
            rankReason: 'benzer_isim',
          ),
        );
      }
    }

    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      if (user != null) {
        final da = _dist(user, a.facility);
        final db = _dist(user, b.facility);
        return da.compareTo(db);
      }
      return a.facility.isim.compareTo(b.facility.isim);
    });

    var list = hits.map((h) => h.facility).toList();

    // En yakın tek tesis
    if (entities.nearestOnly && user != null && list.isNotEmpty) {
      list = [sortMisafirhaneByDistance(list, user).first];
      return list;
    }

    // Yakınımdaki: çıkış ili + komşu iller (sistem yönergesi).
    if ((entities.nearby || entities.nearestOnly) && user != null) {
      if (city != null) {
        list = list
            .where((m) => KamiNeighborRegion.isInRegion(city, m.il))
            .toList();
      }
      final withCoords = list
          .where(
            (m) =>
                m.latitude != 0 &&
                m.longitude != 0 &&
                isValidWgs84LatLng(m.latitude, m.longitude),
          )
          .toList();
      final withoutCoords = list.where(
        (m) =>
            m.latitude == 0 ||
            m.longitude == 0 ||
            !isValidWgs84LatLng(m.latitude, m.longitude),
      );
      list = [
        ...sortMisafirhaneByDistance(withCoords, user),
        ...withoutCoords,
      ];
    } else if (user != null && city != null) {
      // İl içi mesafeye göre
      list = [
        ...sortMisafirhaneByDistance(
          list
              .where(
                (m) =>
                    m.latitude != 0 &&
                    m.longitude != 0 &&
                    isValidWgs84LatLng(m.latitude, m.longitude),
              )
              .toList(),
          user,
        ),
        ...list.where(
          (m) =>
              m.latitude == 0 ||
              m.longitude == 0 ||
              !isValidWgs84LatLng(m.latitude, m.longitude),
        ),
      ];
    }

    if (list.length <= limit) return list;
    return list.sublist(0, limit);
  }

  static KamiFacilityHit? _scoreFacility(
    Misafirhane m, {
    required String nameNorm,
    required String nameRaw,
    required String? city,
    required String? district,
    required KamiFacilityKind? kind,
  }) {
    final isimN = KamiFuzzySearch.norm(m.isim);
    final tipN = KamiFuzzySearch.norm(m.tip);
    final ilN = KamiFuzzySearch.norm(m.il);
    final adresN = KamiFuzzySearch.norm(m.adres);
    final combined = '$ilN$isimN$tipN';

    var score = 0.0;
    var reason = '';

    // Tam tesis adı (isim == sorgu veya çok yüksek benzerlik)
    if (nameNorm.isNotEmpty) {
      if (isimN == nameNorm || isimN == KamiFuzzySearch.norm(nameRaw)) {
        score = 100;
        reason = 'tam_ad';
      } else if (isimN.contains(nameNorm) && nameNorm.length >= 4) {
        score = 92;
        reason = 'ad_icerir';
      } else {
        final sim = KamiFuzzySearch.similarity(m.isim, nameRaw);
        if (sim >= 0.86) {
          score = 88;
          reason = 'tam_yakin_ad';
        } else if (sim >= 0.68) {
          score = 62;
          reason = 'benzer_isim';
        }
      }

      // "Kalender Orduevi" gibi: isimde hem tür hem isim
      if (kind != null && _matchesKind(m, kind) && score >= 60) {
        score += 5;
      }
      if (score < 55 && !combined.contains(nameNorm)) {
        return null;
      }
    }

    // İl filtresi
    if (city != null) {
      if (!KamiCityResolver.sameCity(m.il, city)) {
        // İsim sorgusu çok güçlüyse (tam ad) şehir şartı gevşek tutulmaz — kullanıcı şehir yazdıysa zorunlu
        if (nameNorm.isEmpty || score < 90) return null;
        if (!KamiCityResolver.sameCity(m.il, city)) return null;
      } else if (score > 0) {
        score += 8;
      } else if (kind != null && _matchesKind(m, kind)) {
        score = 75;
        reason = 'il_tur';
      }
    }

    // İlçe
    if (district != null && district.trim().isNotEmpty) {
      final d = KamiFuzzySearch.norm(district);
      if (adresN.contains(d) || isimN.contains(d)) {
        if (kind != null && _matchesKind(m, kind)) {
          score = score < 78 ? 78 : score + 4;
          reason = reason.isEmpty ? 'ilce_tur' : reason;
        } else {
          score = score < 65 ? 65 : score + 2;
        }
      }
    }

    // Sadece tür (isim yok, şehir yok veya şehir zaten işlendi)
    if (kind != null) {
      if (!_matchesKind(m, kind)) {
        if (nameNorm.isEmpty) return null;
        // isim sorgu var ama tür uyuşmazsa ele (ör. "Kalender Orduevi" için tür şart)
        if (score < 85) return null;
      } else if (score == 0 && city == null && nameNorm.isEmpty) {
        score = 40;
        reason = 'tur';
      }
    }

    if (score <= 0) return null;
    return KamiFacilityHit(
      facility: m,
      score: score,
      rankReason: reason.isEmpty ? 'eslesme' : reason,
    );
  }

  static bool _matchesKind(Misafirhane m, KamiFacilityKind kind) {
    final hay = KamiFuzzySearch.norm('${m.tip} ${m.isim}');
    for (final key in kind.matchKeys) {
      if (hay.contains(key)) return true;
    }
    return false;
  }

  static double _dist(LatLng user, Misafirhane m) {
    if (m.latitude == 0 ||
        m.longitude == 0 ||
        !isValidWgs84LatLng(m.latitude, m.longitude)) {
      return double.infinity;
    }
    return const Distance().as(
      LengthUnit.Meter,
      user,
      LatLng(m.latitude, m.longitude),
    );
  }

  /// Belediye sosyal — isteğe bağlı tag filtresi (manzara / kahvaltı).
  static List<SosyalItem> searchSosyal({
    required RotaDataState data,
    String? city,
    LatLng? user,
    bool scenic = false,
    bool breakfast = false,
    int limit = 15,
  }) {
    var list = data.sosyal.toList();
    if (city != null) {
      list = list
          .where((s) => KamiCityResolver.sameCity(s.il, city))
          .toList();
    }

    if (scenic || breakfast) {
      final filtered = list.where((s) {
        final h = KamiFuzzySearch.norm('${s.isim} ${s.aciklama} ${s.adres}');
        if (scenic &&
            (h.contains('manzara') ||
                h.contains('seyir') ||
                h.contains('panoram'))) {
          return true;
        }
        if (breakfast &&
            (h.contains('kahvalti') ||
                h.contains('kahvalt') ||
                h.contains('breakfast'))) {
          return true;
        }
        return false;
      }).toList();
      if (filtered.isNotEmpty) {
        list = filtered;
      } else {
        // Etiket yoksa tüm listeyi gösterme — kullanıcıya doğru boş cevap ver.
        return const [];
      }
    }

    if (user != null) {
      if (city != null) {
        list = list
            .where((s) => KamiNeighborRegion.isInRegion(city, s.il))
            .toList();
      }
      list.sort((a, b) {
        final da = _sosyalDist(user, a);
        final db = _sosyalDist(user, b);
        return da.compareTo(db);
      });
    }

    if (list.length <= limit) return list;
    return list.sublist(0, limit);
  }

  static double _sosyalDist(LatLng user, SosyalItem s) {
    final e = s.enlem;
    final b = s.boylam;
    if (e == null ||
        b == null ||
        e == 0 ||
        b == 0 ||
        !isValidWgs84LatLng(e, b)) {
      return double.infinity;
    }
    return const Distance().as(LengthUnit.Meter, user, LatLng(e, b));
  }
}
