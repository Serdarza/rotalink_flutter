import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum KisKesfetUcretTuru {
  giris('Giriş'),
  havuz('Havuz'),
  aileBanyosu('Aile banyosu'),
  konaklama('Konaklama');

  const KisKesfetUcretTuru(this.etiket);
  final String etiket;
}

@immutable
class KisKesfetUcret {
  const KisKesfetUcret({
    required this.tur,
    required this.ad,
    required this.tutar,
    required this.birim,
    required this.kaynakUrl,
    this.kosul = '',
    this.baslangic = false,
    this.gecerlilikBitis = '',
  });

  final KisKesfetUcretTuru tur;
  final String ad;
  final double tutar;
  final String birim;
  final String kaynakUrl;
  final String kosul;
  // Çocuk, indirim, ek yatak ve paket eklentileri başlangıç fiyatı değildir.
  final bool baslangic;
  final String gecerlilikBitis;

  String get fiyat => tutar == 0
      ? 'Ücretsiz'
      : '${NumberFormat('#,##0.##', 'tr_TR').format(tutar)} TL';

  bool gecerli(DateTime tarih) {
    final bitis = DateTime.tryParse(gecerlilikBitis);
    return bitis == null ||
        !DateTime(tarih.year, tarih.month, tarih.day).isAfter(bitis);
  }
}

@immutable
class KisKesfetUcretBilgisi {
  const KisKesfetUcretBilgisi({
    required this.sonKontrol,
    this.aciklama = '',
    this.kaynaklar = const [],
    this.kalemler = const [],
  });

  final String sonKontrol;
  final String aciklama;
  final List<String> kaynaklar;
  final List<KisKesfetUcret> kalemler;

  List<KisKesfetUcret> gecerliKalemler(DateTime tarih) =>
      kalemler.where((k) => k.gecerli(tarih)).toList();

  KisKesfetUcret? baslangicUcreti(DateTime tarih) {
    final adaylar = gecerliKalemler(tarih).where((k) => k.baslangic).toList()
      ..sort((a, b) => a.tutar.compareTo(b.tutar));
    return adaylar.firstOrNull;
  }

  static KisKesfetUcretBilgisi? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String text(Object? v) => v is String ? v.trim() : '';
    bool url(String s) {
      final uri = Uri.tryParse(s);
      return uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty;
    }

    final kontrol = text(raw['sonKontrol']);
    final tarih = DateTime.tryParse(kontrol);
    if (tarih == null || tarih.toIso8601String().split('T').first != kontrol) {
      return null;
    }
    final kaynaklar = raw['kaynaklar'];
    final kalemler = <KisKesfetUcret>[];
    final rows = raw['kalemler'];
    if (rows is! List) return null;
    for (final row in rows) {
      if (row is! Map) continue;
      final tur = KisKesfetUcretTuru.values
          .where((t) => t.name == row['tur'])
          .firstOrNull;
      final tutar = row['tutar'];
      final ad = text(row['ad']);
      final birim = text(row['birim']);
      final kaynak = text(row['kaynakUrl']);
      final bitis = text(row['gecerlilikBitis']);
      if (tur == null ||
          tutar is! num ||
          !tutar.isFinite ||
          tutar < 0 ||
          ad.isEmpty ||
          birim.isEmpty ||
          !url(kaynak) ||
          (bitis.isNotEmpty && DateTime.tryParse(bitis) == null)) {
        continue;
      }
      kalemler.add(
        KisKesfetUcret(
          tur: tur,
          ad: ad,
          tutar: tutar.toDouble(),
          birim: birim,
          kaynakUrl: kaynak,
          kosul: text(row['kosul']),
          baslangic: row['baslangic'] == true,
          gecerlilikBitis: bitis,
        ),
      );
    }
    // Bozuk bir uzak tarife, son doğrulanan yerel tarifenin yerini almasın.
    if (rows.isNotEmpty && kalemler.isEmpty) return null;
    return KisKesfetUcretBilgisi(
      sonKontrol: kontrol,
      aciklama: text(raw['aciklama']),
      kaynaklar: kaynaklar is List
          ? kaynaklar.map(text).where(url).toSet().toList()
          : const [],
      kalemler: List.unmodifiable(kalemler),
    );
  }
}
