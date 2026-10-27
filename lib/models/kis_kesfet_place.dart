import 'package:flutter/foundation.dart';

import 'kis_kesfet_ucret.dart';

/// Kış Keşfet kategorileri.
enum KisKesfetKategori { kayak, termal, kisGezisi }

extension KisKesfetKategoriX on KisKesfetKategori {
  String get kod {
    switch (this) {
      case KisKesfetKategori.kayak:
        return 'kayak';
      case KisKesfetKategori.termal:
        return 'termal';
      case KisKesfetKategori.kisGezisi:
        return 'kisGezisi';
    }
  }

  String get etiket {
    switch (this) {
      case KisKesfetKategori.kayak:
        return 'Kayak';
      case KisKesfetKategori.termal:
        return 'Termal';
      case KisKesfetKategori.kisGezisi:
        return 'Kış Gezileri';
    }
  }

  String sayiMetni(int n) {
    switch (this) {
      case KisKesfetKategori.kayak:
        return n == 1 ? '1 kayak merkezi' : '$n kayak merkezi';
      case KisKesfetKategori.termal:
        return n == 1 ? '1 termal tesis' : '$n termal tesis';
      case KisKesfetKategori.kisGezisi:
        return n == 1 ? '1 kış rotası' : '$n kış rotası';
    }
  }

  static KisKesfetKategori? fromKod(String raw) {
    switch (raw.trim()) {
      case 'kayak':
        return KisKesfetKategori.kayak;
      case 'termal':
        return KisKesfetKategori.termal;
      case 'kisGezisi':
        return KisKesfetKategori.kisGezisi;
      default:
        return null;
    }
  }
}

@immutable
class KisKesfetBilgi {
  const KisKesfetBilgi({required this.baslik, required this.deger});

  final String baslik;
  final String deger;
}

enum KisKesfetPistDurum { gorsel, sayfa, yok }

@immutable
class KisKesfetPistHaritasi {
  const KisKesfetPistHaritasi({
    this.sayfaUrl = '',
    this.gorselUrl = '',
    this.kaynakAdi = '',
    this.resmi = false,
    this.sonKontrol = '',
    this.durum = KisKesfetPistDurum.yok,
  });

  final String sayfaUrl;
  final String gorselUrl;
  final String kaynakAdi;
  final bool resmi;
  final String sonKontrol;
  final KisKesfetPistDurum durum;

  static KisKesfetPistDurum durumFrom(String raw) {
    switch (raw.trim()) {
      case 'gorsel':
        return KisKesfetPistDurum.gorsel;
      case 'sayfa':
        return KisKesfetPistDurum.sayfa;
      default:
        return KisKesfetPistDurum.yok;
    }
  }

  bool get hasGorsel =>
      durum == KisKesfetPistDurum.gorsel && httpUri(gorselUrl) != null;

  bool get hasSayfa => httpUri(sayfaUrl) != null;

  Uri? get gorselUri => httpUri(gorselUrl);

  Uri? get sayfaUri => httpUri(sayfaUrl);

  static Uri? httpUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return uri;
  }
}

@immutable
class KisKesfetPlace {
  const KisKesfetPlace({
    required this.id,
    required this.kategori,
    required this.il,
    required this.ilce,
    required this.isim,
    required this.kurumTuru,
    required this.kisaAciklama,
    required this.adres,
    required this.telefon,
    required this.kullanimTuru,
    required this.latitude,
    required this.longitude,
    required this.resmiKaynak,
    required this.sonDogrulama,
    this.tesisSinifi = '',
    this.anaBilgiler = const [],
    this.pistHaritasi,
    this.ucretBilgisi,
  });

  final String id;
  final KisKesfetKategori kategori;
  final String il;
  final String ilce;
  final String isim;
  final String kurumTuru;
  final String kisaAciklama;
  final String adres;
  final String telefon;
  final String kullanimTuru;
  final double? latitude;
  final double? longitude;
  final String resmiKaynak;
  final String sonDogrulama;
  final String tesisSinifi;
  final List<KisKesfetBilgi> anaBilgiler;
  final KisKesfetPistHaritasi? pistHaritasi;
  final KisKesfetUcretBilgisi? ucretBilgisi;

  KisKesfetPlace withUcretBilgisi(KisKesfetUcretBilgisi bilgi) =>
      KisKesfetPlace(
        id: id,
        kategori: kategori,
        il: il,
        ilce: ilce,
        isim: isim,
        kurumTuru: kurumTuru,
        kisaAciklama: kisaAciklama,
        adres: adres,
        telefon: telefon,
        kullanimTuru: kullanimTuru,
        latitude: latitude,
        longitude: longitude,
        resmiKaynak: resmiKaynak,
        sonDogrulama: sonDogrulama,
        tesisSinifi: tesisSinifi,
        anaBilgiler: anaBilgiler,
        pistHaritasi: pistHaritasi,
        ucretBilgisi: bilgi,
      );

  bool get isKayak => kategori == KisKesfetKategori.kayak;

  /// Kayak kaydında doğrulanmış pist haritası (görsel veya resmî sayfa) yok.
  bool get pistHaritasiEksik =>
      isKayak &&
      (pistHaritasi == null || pistHaritasi!.durum == KisKesfetPistDurum.yok);

  /// Uygulama içinde yakınlaştırılabilir pist görseli var.
  bool get pistHaritasiUygulamada => pistHaritasi?.hasGorsel ?? false;

  /// Görsel yoksa tarayıcıda açılacak pist veya merkez sayfası.
  Uri? get pistHaritasiBaglanti {
    final sayfa = pistHaritasi?.sayfaUri;
    if (sayfa != null) return sayfa;
    if (hasOfficialSource) return Uri.tryParse(resmiKaynak.trim());
    return null;
  }

  static const _kamuKurum = {
    'Belediye',
    'Üniversite',
    'Sağlık Bakanlığı',
    'Devlet hastanesi',
    'Köy',
    'Emniyet',
    'Vakıf',
  };

  bool get isOzelTesis =>
      kategori == KisKesfetKategori.termal &&
      (tesisSinifi == 'ozel' || kurumTuru == 'Özel tesis');

  bool get isKamuTesis =>
      kategori == KisKesfetKategori.termal &&
      !isOzelTesis &&
      (tesisSinifi == 'kamu' || _kamuKurum.contains(kurumTuru));

  /// Kartta görünen tesis etiketi: "Kamu · Belediye" veya "Özel tesis".
  String get tesisRozeti {
    if (kategori != KisKesfetKategori.termal) return kurumTuru;
    if (isOzelTesis) return 'Özel tesis';
    if (kurumTuru.isNotEmpty && kurumTuru != 'Özel tesis') {
      return 'Kamu · $kurumTuru';
    }
    return 'Kamu tesisi';
  }

  bool get hasPhone => telefon.trim().isNotEmpty;

  bool get hasFacts => anaBilgiler.isNotEmpty;

  bool get hasCoordinates => latitude != null && longitude != null;

  bool get hasOfficialSource {
    final uri = Uri.tryParse(resmiKaynak.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  String get ilIlceSatiri {
    final district = ilce.trim();
    if (district.isEmpty) return il;
    return '$il · $district';
  }
}
