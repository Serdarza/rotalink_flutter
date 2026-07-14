import 'package:latlong2/latlong.dart';

import '../../models/gezi_yemek_item.dart';
import '../../models/misafirhane.dart';
import '../../models/sosyal_item.dart';
import '../../utils/geo_helpers.dart';
import 'kami_models.dart';
import 'kami_neighbor_region.dart';

enum KamiResultCardTap { none, maps, images }

/// UI kart modeli — profesyonel liste satırı.
class KamiResultCard {
  const KamiResultCard({
    required this.index,
    required this.title,
    this.phone = '',
    this.distanceLabel = '',
    this.city = '',
    this.description = '',
    this.address = '',
    this.section = '',
    this.tapAction = KamiResultCardTap.none,
  });

  final int index;
  final String title;
  final String phone;
  final String distanceLabel;
  final String city;

  /// Veritabanındaki açıklama metni (gezi / yemek / sosyal).
  final String description;
  final String address;

  /// Grup başlığı (rota / hafta sonu için).
  final String section;

  /// Arama listesi ile aynı: gezi/tesis/sosyal → Haritalar; yemek → Görseller.
  final KamiResultCardTap tapAction;

  Map<String, Object?> toMap() => {
        'index': index,
        'title': title,
        'phone': phone,
        'distanceLabel': distanceLabel,
        'city': city,
        'description': description,
        'address': address,
        'section': section,
        'tapAction': tapAction.name,
      };

  static KamiResultCardTap _tapActionFromSection(String section) {
    final s = section.toLowerCase();
    if (s.contains('yemek') || s.contains('yöresel')) {
      return KamiResultCardTap.images;
    }
    if (s.contains('gezi') ||
        s.contains('gezilecek') ||
        s.contains('sosyal') ||
        s.contains('belediye') ||
        s.contains('misafir') ||
        s.contains('kamu') ||
        s.contains('tesis')) {
      return KamiResultCardTap.maps;
    }
    return KamiResultCardTap.none;
  }

  static KamiResultCardTap _resolveTapAction(Object? raw, String section) {
    if (raw is String) {
      for (final v in KamiResultCardTap.values) {
        if (v.name == raw) return v;
      }
    }
    return _tapActionFromSection(section);
  }

  static KamiResultCard? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final title = (m['title'] ?? '').toString().trim();
    if (title.isEmpty) return null;
    final section = (m['section'] ?? '').toString();
    return KamiResultCard(
      index: (m['index'] as num?)?.toInt() ?? 0,
      title: title,
      phone: (m['phone'] ?? '').toString(),
      distanceLabel: (m['distanceLabel'] ?? '').toString(),
      city: (m['city'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      address: (m['address'] ?? '').toString(),
      section: section,
      tapAction: _resolveTapAction(m['tapAction'], section),
    );
  }
}

/// Yanıt oluşturucu — kart UI + DB alanları.
abstract final class KamiResponseBuilder {
  /// Kart stili kullanan tüm sonuç intent'leri.
  static bool usesResultCards(KamiIntentType intent) =>
      intent == KamiIntentType.nearbyFacilities ||
      intent == KamiIntentType.accommodation ||
      intent == KamiIntentType.cityOverview ||
      intent == KamiIntentType.databaseSearch ||
      intent == KamiIntentType.nearbyMunicipal ||
      intent == KamiIntentType.nearbyExplore ||
      intent == KamiIntentType.food ||
      intent == KamiIntentType.sightseeing ||
      intent == KamiIntentType.weekendTrip ||
      intent == KamiIntentType.route ||
      intent == KamiIntentType.facilitySearch;

  /// Eski ad — geriye uyumluluk.
  static bool usesFacilityCards(KamiIntentType intent) =>
      usesResultCards(intent);

  static List<KamiResultCard> buildFacilityCards(KamiPayload payload) =>
      buildResultCards(payload);

  static List<KamiResultCard> buildResultCards(KamiPayload payload) {
    final user = payload.userLocation;
    final cards = <KamiResultCard>[];
    var index = 0;
    final homeCity =
        payload.cities.isNotEmpty ? payload.cities.first.trim() : '';
    final useNeighborSections =
        homeCity.isNotEmpty && _usesNeighborSections(payload.intent);

    String sectionForCity(String itemCity, String fallback) {
      if (!useNeighborSections || itemCity.trim().isEmpty) return fallback;
      return KamiNeighborRegion.sectionLabel(homeCity, itemCity.trim());
    }

    void addFacility(Misafirhane m, {String section = ''}) {
      index++;
      final tip = m.tip.trim();
      final desc = tip.isNotEmpty ? tip : '';
      final city = m.il.trim();
      cards.add(
        KamiResultCard(
          index: index,
          title: m.isim.trim().isEmpty ? 'İsimsiz tesis' : m.isim.trim(),
          phone: _formatPhone(m.telefon),
          distanceLabel: _distanceFor(user, m.latitude, m.longitude),
          city: city,
          address: m.adres.trim(),
          description: desc,
          section: section.isNotEmpty
              ? section
              : sectionForCity(city, 'Kamu misafirhaneleri'),
          tapAction: KamiResultCardTap.maps,
        ),
      );
    }

    void addGezi(GeziYemekItem g, {String section = ''}) {
      index++;
      final city = g.il.trim();
      cards.add(
        KamiResultCard(
          index: index,
          title: g.isim.trim().isEmpty ? 'İsimsiz yer' : g.isim.trim(),
          distanceLabel: _distanceFor(user, g.enlem ?? 0, g.boylam ?? 0),
          city: city,
          address: g.adres.trim(),
          description: g.aciklama.trim(),
          section:
              section.isNotEmpty ? section : sectionForCity(city, 'Gezilecek yerler'),
          tapAction: KamiResultCardTap.maps,
        ),
      );
    }

    void addYemek(GeziYemekItem y, {String section = ''}) {
      index++;
      final city = y.il.trim();
      cards.add(
        KamiResultCard(
          index: index,
          title: y.isim.trim().isEmpty ? 'İsimsiz yemek' : y.isim.trim(),
          distanceLabel: _distanceFor(user, y.enlem ?? 0, y.boylam ?? 0),
          city: city,
          address: y.adres.trim(),
          description: y.aciklama.trim(),
          section:
              section.isNotEmpty ? section : sectionForCity(city, 'Yöresel yemekler'),
          tapAction: KamiResultCardTap.images,
        ),
      );
    }

    void addSosyal(SosyalItem s, {String section = ''}) {
      index++;
      final city = s.il.trim();
      cards.add(
        KamiResultCard(
          index: index,
          title: s.isim.trim().isEmpty ? 'İsimsiz tesis' : s.isim.trim(),
          distanceLabel: _distanceFor(user, s.enlem ?? 0, s.boylam ?? 0),
          city: city,
          address: s.adres.trim(),
          description: s.aciklama.trim(),
          section: section.isNotEmpty
              ? section
              : sectionForCity(city, 'Belediye sosyal tesisleri'),
          tapAction: KamiResultCardTap.maps,
        ),
      );
    }

    if (payload.routeSections.isNotEmpty) {
      for (final section in payload.routeSections) {
        final label = '${section.roleLabel}: ${section.city}';
        for (final m in section.facilities) {
          addFacility(m, section: '$label · Kamu tesisleri');
        }
        for (final s in section.sosyal) {
          addSosyal(s, section: '$label · Belediye tesisleri');
        }
        for (final g in section.gezi) {
          addGezi(g, section: '$label · Gezilecek yerler');
        }
        for (final y in section.yemek) {
          addYemek(y, section: '$label · Yöresel yemekler');
        }
      }
      return cards;
    }

    for (final m in payload.facilities) {
      addFacility(m);
    }
    for (final s in payload.sosyal) {
      addSosyal(s);
    }
    for (final g in payload.gezi) {
      addGezi(g);
    }
    for (final y in payload.yemek) {
      addYemek(y);
    }

    return cards;
  }

  static String build(KamiPayload payload) {
    if (payload.needsClarification) {
      return payload.clarificationHint;
    }
    if (payload.needsLocation) {
      return payload.clarificationHint.isNotEmpty
          ? payload.clarificationHint
          : 'Bu öneri için konum izni gerekir.';
    }
    if (payload.emptyReason.isNotEmpty &&
        payload.facilities.isEmpty &&
        payload.gezi.isEmpty &&
        payload.yemek.isEmpty &&
        payload.sosyal.isEmpty &&
        payload.routeSections.isEmpty &&
        payload.cityScores.isEmpty) {
      return payload.emptyReason;
    }

    if (payload.cityScores.isNotEmpty) {
      final buf = StringBuffer();
      if (payload.title.isNotEmpty) buf.writeln(payload.title);
      if (payload.subtitle.isNotEmpty) buf.writeln(payload.subtitle);
      return buf.toString().trim();
    }

    final cards = buildResultCards(payload);
    if (usesResultCards(payload.intent) &&
        cards.isNotEmpty &&
        payload.routeSections.isEmpty) {
      final buf = StringBuffer();
      if (payload.title.isNotEmpty) buf.writeln(payload.title);
      if (payload.subtitle.isNotEmpty) buf.writeln(payload.subtitle);
      return buf.toString().trim();
    }

    if (payload.intent == KamiIntentType.help) {
      if (payload.subtitle.isNotEmpty) {
        return '${payload.title}\n${payload.subtitle}'.trim();
      }
      return payload.title.isNotEmpty
          ? payload.title
          : 'Size rota, yemek, gezi, konaklama ve belediye tesisi konularında yardımcı olabilirim.';
    }

    return payload.emptyReason.isNotEmpty
        ? payload.emptyReason
        : 'Uygun kayıt bulunamadı.';
  }

  static String _distanceFor(LatLng? user, double lat, double lon) {
    final chip = formatDistanceChipText(user, lat, lon);
    if (chip == null) return '';
    return chip.replaceFirst('Size uzaklık: ', '').trim();
  }

  static String _formatPhone(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t == '0' || t.toLowerCase() == 'null') return '';
    final digits = t.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.length < 7) return t;
    return t;
  }

  static bool _usesNeighborSections(KamiIntentType intent) =>
      intent == KamiIntentType.nearbyFacilities ||
      intent == KamiIntentType.nearbyExplore ||
      intent == KamiIntentType.nearbyMunicipal ||
      intent == KamiIntentType.food ||
      intent == KamiIntentType.sightseeing;
}
