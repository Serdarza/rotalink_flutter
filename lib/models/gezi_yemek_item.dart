/// Kotlin [GeziYemekItem] — `geziler` / `yemekler` RTDB listeleri.
class GeziYemekItem {
  const GeziYemekItem({
    required this.il,
    required this.isim,
    required this.adres,
    required this.aciklama,
    this.enlem,
    this.boylam,
    this.tur,
    this.accommodationInfo,
    this.day,
  });

  final String il;
  final String isim;
  final String adres;
  final String aciklama;
  final double? enlem;
  final double? boylam;
  final String? tur;
  final String? accommodationInfo;
  final int? day;

  /// Kotlin `copy(tur = ..., accommodationInfo = null, day = ...)`.
  GeziYemekItem forRouteSuggestion({required String turLabel, required int day}) {
    return GeziYemekItem(
      il: il,
      isim: isim,
      adres: adres,
      aciklama: aciklama,
      enlem: enlem,
      boylam: boylam,
      tur: turLabel,
      accommodationInfo: null,
      day: day,
    );
  }

  static GeziYemekItem? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final il = _str(m, const ['il', 'il_adi', 'province', 'sehir']);
    final isim = _str(m, const ['isim', 'tesis_adi', 'name', 'title']);
    if (isim.isEmpty && il.isEmpty) return null;
    return GeziYemekItem(
      il: il,
      isim: isim,
      adres: _str(m, const ['adres', 'adres_bilgisi', 'address']),
      aciklama: _str(m, const ['aciklama', 'description', 'aciklama_metni']),
      enlem: _dblOrNull(m, const ['enlem', 'latitude', 'lat']),
      boylam: _dblOrNull(m, const ['boylam', 'longitude', 'lng', 'lon']),
      tur: _strOpt(m, const ['tur', 'type', 'kategori']),
      accommodationInfo: _strOpt(m, const ['accommodationInfo', 'konaklama']),
      day: _intOrNull(m, const ['day', 'gun']),
    );
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

  static String? _strOpt(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return null;
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

  static int? _intOrNull(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is int) return v;
      if (v is num) return v.toInt();
      final p = int.tryParse(v.toString());
      if (p != null) return p;
    }
    return null;
  }
}
