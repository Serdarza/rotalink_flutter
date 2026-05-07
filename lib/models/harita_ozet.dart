import 'misafirhane.dart';

/// Kotlin `HaritaOzetTemsilcisi` — `harita_ozet` modunda haritada il temsilcisi.
class HaritaOzetTemsilcisi {
  const HaritaOzetTemsilcisi({
    required this.id,
    required this.il,
    required this.isim,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String il;
  final String isim;
  final double latitude;
  final double longitude;

  static const String tipHaritaOzet = 'harita_ozet';

  Misafirhane toPlaceholderMisafirhane() => Misafirhane(
        isim: isim,
        il: il,
        adres: '',
        telefon: '',
        latitude: latitude,
        longitude: longitude,
        tip: tipHaritaOzet,
      );

  static HaritaOzetTemsilcisi? tryParse(dynamic raw, {String? mapKeyIl}) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    var il = _str(m, const ['il', 'sehir', 'province']);
    if (il.isEmpty && mapKeyIl != null) il = mapKeyIl.trim();
    final isim = _str(m, const ['isim', 'tesis_adi', 'name']);
    final id = _str(m, const ['id', 'tesis_id', 'facility_id']);
    final lat = _dbl(m, const ['latitude', 'enlem', 'lat']);
    final lon = _dbl(m, const ['longitude', 'boylam', 'lng']);
    if (il.isEmpty) return null;
    return HaritaOzetTemsilcisi(
      id: id,
      il: il,
      isim: isim,
      latitude: lat,
      longitude: lon,
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
