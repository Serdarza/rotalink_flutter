import '../utils/search_normalize.dart';

/// `fiyatlar.json` içindeki tek tesis fiyat kaydı.
///
/// Eşleşme anahtarı: normalize([il]) + normalize([isim])
/// → tesisler JSON'daki aynı il/isim ile buluşur.
class FacilityPriceEntry {
  const FacilityPriceEntry({
    required this.il,
    required this.isim,
    this.fiyatSivil,
    this.fiyatKamuPersoneli,
    this.fiyatKurumPersoneli,
    this.fiyatSivilDefined = false,
    this.fiyatKamuDefined = false,
    this.fiyatKurumDefined = false,
  });

  final String il;
  final String isim;

  final String? fiyatSivil;
  final String? fiyatKamuPersoneli;
  final String? fiyatKurumPersoneli;

  final bool fiyatSivilDefined;
  final bool fiyatKamuDefined;
  final bool fiyatKurumDefined;

  bool get hasFiyatBilgisi =>
      fiyatSivilDefined || fiyatKamuDefined || fiyatKurumDefined;

  /// Tesis kaydı ile aynı mantık: Türkçe normalize + boşluksuz.
  static String matchKey(String il, String isim) =>
      '${normalizeForSearch(il)}\u0001${normalizeForSearch(isim)}';

  String get key => matchKey(il, isim);

  static FacilityPriceEntry? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final isim = _str(m, const ['isim', 'tesis_adi', 'name', 'title']);
    final il = _str(m, const ['il', 'il_adi', 'province', 'sehir']);
    if (isim.isEmpty || il.isEmpty) return null;

    final sivil = _priceField(m, const ['fiyat_sivil', 'sivil']);
    final kamu = _priceField(m, const [
      'fiyat_kamu_personeli',
      'fiyat_kamu',
      'kamu_personeli',
    ]);
    final kurum = _priceField(m, const [
      'fiyat_kurum_personeli',
      'fiyat_kurum',
      'kurum_personeli',
    ]);

    return FacilityPriceEntry(
      il: il,
      isim: isim,
      fiyatSivil: sivil.present ? sivil.value : null,
      fiyatKamuPersoneli: kamu.present ? kamu.value : null,
      fiyatKurumPersoneli: kurum.present ? kurum.value : null,
      fiyatSivilDefined: sivil.present,
      fiyatKamuDefined: kamu.present,
      fiyatKurumDefined: kurum.present,
    );
  }

  static ({bool present, String? value}) _priceField(
    Map<String, dynamic> m,
    List<String> keys,
  ) {
    for (final k in keys) {
      if (!m.containsKey(k)) continue;
      final v = m[k];
      if (v == null) return (present: true, value: null);
      final s = v.toString().trim();
      if (s.isEmpty || s.toLowerCase() == 'null') {
        return (present: true, value: null);
      }
      return (present: true, value: s);
    }
    return (present: false, value: null);
  }

  static String _str(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }
}
