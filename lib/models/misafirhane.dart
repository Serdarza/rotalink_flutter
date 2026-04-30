/// Kotlin `Misafirhane` ile aynı alanlar; JSON anahtarları esnek okunur.
class Misafirhane {
  const Misafirhane({
    required this.isim,
    required this.il,
    required this.adres,
    required this.telefon,
    required this.latitude,
    required this.longitude,
    required this.tip,
  });

  final String isim;
  final String il;
  final String adres;
  final String telefon;
  final double latitude;
  final double longitude;
  final String tip;

  String get stableFacilityId => '$il\u0001$isim';

  /// Kotlin `MisafirhaneAdapter` eşlemesi: `isim` + `il`.
  bool sameFavoriteIdentity(Misafirhane other) =>
      isim.trim() == other.isim.trim() && il.trim() == other.il.trim();

  /// Yerel depolama (`favorites` prefs) için düz JSON.
  Map<String, dynamic> toJson() => {
        'isim': isim,
        'il': il,
        'adres': adres,
        'telefon': telefon,
        'latitude': latitude,
        'longitude': longitude,
        'tip': tip,
      };

  static Misafirhane? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final isim = _str(m, const ['isim', 'tesis_adi', 'name', 'title']);
    final il = _str(m, const ['il', 'il_adi', 'province', 'sehir']);
    final adres = _str(m, const ['adres', 'adres_bilgisi', 'address']);
    final telefon = _str(m, const ['telefon', 'phone', 'tel', 'telefon_no']);
    final lat = _dbl(m, const ['latitude', 'enlem', 'lat']);
    final lon = _dbl(m, const ['longitude', 'boylam', 'lng', 'lon']);
    final tip = _str(m, const ['tip', 'tesis_tipi', 'type', 'facility_type']);
    if (isim.isEmpty && il.isEmpty) return null;
    return Misafirhane(
      isim: isim,
      il: il,
      adres: adres,
      telefon: telefon,
      latitude: lat,
      longitude: lon,
      tip: tip,
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

  static double _dbl(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final p = double.tryParse(v.toString().replaceAll(',', '.'));
      if (p != null) return p;
    }
    return 0;
  }
}
