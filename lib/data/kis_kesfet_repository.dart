import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/kis_kesfet_place.dart';
import '../models/kis_kesfet_ucret.dart';
import '../utils/safe_map_coordinates.dart';
import '../utils/search_normalize.dart';
import 'github_kis_kesfet_data_source.dart';
import 'kis_kesfet_official_sources.dart';

/// Gömülü `kis_kesfet.json` okuyucusu. Ana misafirhane verisine dokunmaz.
abstract final class KisKesfetRepository {
  static const assetPath = 'assets/data/kis_kesfet.json';

  static Future<List<KisKesfetPlace>> load() async {
    final text = await rootBundle.loadString(assetPath);
    return parse(text);
  }

  /// GitHub aylık tarama dosyası. Boş veya hatalıysa null.
  static Future<List<KisKesfetPlace>?> fetchRemote() async {
    final text = await GithubKisKesfetDataSource.fetch();
    if (text == null) return null;
    final parsed = parse(text);
    return parsed.isEmpty ? null : parsed;
  }

  /// Uzak kayıt aynı id'de yereli günceller; yeni id ekler. Yerel id silinmez.
  /// Eski şemalı/önceki tarihli uzak kayıt doğrulanmış ücret bilgisini silmez.
  static List<KisKesfetPlace> mergeById(
    List<KisKesfetPlace> local,
    List<KisKesfetPlace> remote,
  ) {
    final byId = {for (final place in local) place.id: place};
    for (final place in remote) {
      final localFees = byId[place.id]?.ucretBilgisi;
      final remoteFees = place.ucretBilgisi;
      byId[place.id] =
          localFees != null &&
              (remoteFees == null ||
                  localFees.sonKontrol.compareTo(remoteFees.sonKontrol) > 0)
          ? place.withUcretBilgisi(localFees)
          : place;
    }
    return byId.values.toList();
  }

  /// Geçersiz kaynak, eksik ad veya kategori kayıtlarını atlar.
  static List<KisKesfetPlace> parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final rows = decoded['kayitlar'];
    if (rows is! List) return const [];
    final out = <KisKesfetPlace>[];
    for (final row in rows) {
      final place = _parsePlace(row);
      if (place != null) out.add(place);
    }
    return out;
  }

  static List<KisKesfetPlace> forCategory(
    List<KisKesfetPlace> places,
    KisKesfetKategori kategori,
  ) {
    return [
      for (final place in places)
        if (place.kategori == kategori) place,
    ];
  }

  static Map<String, List<KisKesfetPlace>> groupByIl(
    List<KisKesfetPlace> places,
  ) {
    final grouped = <String, List<KisKesfetPlace>>{};
    for (final place in places) {
      grouped.putIfAbsent(place.il, () => []).add(place);
    }
    for (final list in grouped.values) {
      list.sort((a, b) {
        final rank = _tesisRank(a).compareTo(_tesisRank(b));
        if (rank != 0) return rank;
        return normalizeForSearch(a.isim).compareTo(normalizeForSearch(b.isim));
      });
    }
    return grouped;
  }

  static List<String> sortedIller(Map<String, List<KisKesfetPlace>> grouped) {
    final names = grouped.keys.toList()
      ..sort((a, b) => normalizeForSearch(a).compareTo(normalizeForSearch(b)));
    return names;
  }
}

KisKesfetPlace? _parsePlace(Object? row) {
  if (row is! Map) return null;
  final kategori = KisKesfetKategoriX.fromKod(_text(row['kategori']));
  final isim = _text(row['isim']);
  final il = _text(row['il']);
  final rawSource = _text(row['resmiKaynak']);
  final kaynak = kategori == KisKesfetKategori.termal
      ? KisKesfetOfficialSources.resolveThermal(_text(row['id']), rawSource)
      : rawSource;
  if (kategori == null || isim.isEmpty || il.isEmpty) return null;
  final probe = KisKesfetPlace(
    id: _text(row['id']),
    kategori: kategori,
    il: il,
    ilce: _text(row['ilce']),
    isim: isim,
    kurumTuru: _text(row['kurumTuru']),
    kisaAciklama: _text(row['kisaAciklama']),
    adres: _text(row['adres']),
    telefon: _text(row['telefon']),
    kullanimTuru: _text(row['kullanimTuru']),
    latitude: null,
    longitude: null,
    resmiKaynak: kaynak,
    sonDogrulama: _text(row['sonDogrulama']),
    tesisSinifi: _text(row['tesisSinifi']),
    anaBilgiler: _bilgiler(row['anaBilgiler']),
    pistHaritasi: _pistHaritasi(row['pistHaritasi']),
    ucretBilgisi: kategori == KisKesfetKategori.termal
        ? KisKesfetUcretBilgisi.fromJson(row['ucretBilgisi'])
        : null,
  );
  if (!probe.hasOfficialSource) return null;
  if (kategori == KisKesfetKategori.termal && !probe.isKamuTesis) return null;
  final coords = _coordinates(row['latitude'], row['longitude']);
  return KisKesfetPlace(
    id: probe.id.isEmpty
        ? '${kategori.kod}-${normalizeForSearch(il)}-${normalizeForSearch(isim)}'
        : probe.id,
    kategori: kategori,
    il: il,
    ilce: probe.ilce,
    isim: isim,
    kurumTuru: probe.kurumTuru,
    kisaAciklama: probe.kisaAciklama,
    adres: probe.adres,
    telefon: probe.telefon,
    kullanimTuru: probe.kullanimTuru,
    latitude: coords?.$1,
    longitude: coords?.$2,
    resmiKaynak: kaynak,
    sonDogrulama: probe.sonDogrulama,
    tesisSinifi: probe.tesisSinifi,
    anaBilgiler: probe.anaBilgiler,
    pistHaritasi: probe.pistHaritasi,
    ucretBilgisi: probe.ucretBilgisi,
  );
}

KisKesfetPistHaritasi? _pistHaritasi(Object? raw) {
  if (raw is! Map) return null;
  var durum = KisKesfetPistHaritasi.durumFrom(_text(raw['durum']));
  final gorsel = _text(raw['gorselUrl']);
  final sayfa = _text(raw['sayfaUrl']);
  if (durum == KisKesfetPistDurum.gorsel &&
      KisKesfetPistHaritasi.httpUri(gorsel) == null) {
    durum = KisKesfetPistHaritasi.httpUri(sayfa) == null
        ? KisKesfetPistDurum.yok
        : KisKesfetPistDurum.sayfa;
  }
  return KisKesfetPistHaritasi(
    sayfaUrl: sayfa,
    gorselUrl: gorsel,
    kaynakAdi: _text(raw['kaynakAdi']),
    resmi: raw['resmi'] == true,
    sonKontrol: _text(raw['sonKontrol']),
    durum: durum,
  );
}

int _tesisRank(KisKesfetPlace place) {
  if (place.isKamuTesis) return 0;
  if (place.isOzelTesis) return 1;
  return 2;
}

List<KisKesfetBilgi> _bilgiler(Object? raw) {
  if (raw is! List) return const [];
  final out = <KisKesfetBilgi>[];
  for (final row in raw) {
    if (row is! Map) continue;
    final baslik = _text(row['baslik']);
    final deger = _text(row['deger']);
    if (baslik.isEmpty || deger.isEmpty) continue;
    out.add(KisKesfetBilgi(baslik: baslik, deger: deger));
  }
  return out;
}

String _text(Object? value) => value == null ? '' : value.toString().trim();

(double, double)? _coordinates(Object? latRaw, Object? lonRaw) {
  final lat = _number(latRaw);
  final lon = _number(lonRaw);
  if (lat == null || lon == null) return null;
  if (lat == 0 && lon == 0) return null;
  if (!isValidWgs84LatLng(lat, lon)) return null;
  return (lat, lon);
}

double? _number(Object? value) {
  if (value == null || value is! num) return null;
  final n = value.toDouble();
  if (!n.isFinite) return null;
  return n;
}
