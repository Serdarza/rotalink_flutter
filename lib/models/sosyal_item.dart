/// Kotlin [SosyalItem] — RTDB `sosyal` listesi.
class SosyalItem {
  const SosyalItem({
    required this.il,
    required this.ilce,
    required this.isim,
    required this.adres,
    required this.aciklama,
    this.enlem,
    this.boylam,
  });

  final String il;
  final String ilce;
  final String isim;
  final String adres;
  final String aciklama;
  final double? enlem;
  final double? boylam;

  static SosyalItem? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final il = _str(m, const ['il', 'il_adi', 'province', 'sehir']);
    final isim = _str(m, const ['isim', 'tesis_adi', 'name', 'title']);
    if (isim.isEmpty && il.isEmpty) return null;
    return SosyalItem(
      il: il,
      ilce: _str(m, const ['ilce', 'ilce_adi', 'district']),
      isim: isim,
      adres: _str(m, const ['adres', 'adres_bilgisi', 'address']),
      aciklama: _str(m, const ['aciklama', 'description', 'aciklama_metni']),
      enlem: _dblOrNull(m, const ['enlem', 'latitude', 'lat']),
      boylam: _dblOrNull(m, const ['boylam', 'longitude', 'lng', 'lon']),
    );
  }

  static double? _dblOrNull(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final p = double.tryParse(v.toString().replaceAll(',', '.'));
      if (p != null) return p;
    }
    return null;
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
