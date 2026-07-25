/// Kotlin [GeziYemekItem] — `geziler` / `yemekler` listeleri (+ görseller).
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
    this.imageUrls = const [],
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

  /// En fazla 3 görsel URL (Pexels / Wikimedia → JSON).
  final List<String> imageUrls;

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
      imageUrls: imageUrls,
    );
  }

  Map<String, dynamic> toJson() => {
        'il': il,
        'isim': isim,
        'adres': adres,
        'aciklama': aciklama,
        if (enlem != null) 'enlem': enlem,
        if (boylam != null) 'boylam': boylam,
        if (tur != null) 'tur': tur,
        if (accommodationInfo != null) 'accommodationInfo': accommodationInfo,
        if (day != null) 'day': day,
        if (imageUrls.isNotEmpty) 'image_urls': imageUrls,
      };

  static GeziYemekItem? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final isim = _str(m, const ['isim', 'tesis_adi', 'name', 'title']);
    final il = _str(m, const ['il', 'il_adi', 'province', 'sehir']);
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
      imageUrls: _imageUrls(m),
    );
  }

  static List<String> _imageUrls(Map<String, dynamic> m) {
    final out = <String>[];
    void add(String? s) {
      final t = s?.trim() ?? '';
      if (t.isEmpty || out.contains(t) || out.length >= 3) return;
      out.add(t);
    }

    final list = m['image_urls'] ?? m['images'] ?? m['gorseller'];
    if (list is List) {
      for (final e in list) {
        add(e?.toString());
      }
    }
    add(m['image_url']?.toString());
    add(m['gorsel']?.toString());
    add(m['photo']?.toString());
    return out;
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
