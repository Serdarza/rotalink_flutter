import 'package:latlong2/latlong.dart';

import '../engine/city_resolver.dart';

/// Türkiye 81 il merkezi koordinatları — GPS → il eşlemesi için sabit referans.
///
/// Veritabanındaki hatalı tesis koordinatlarına bağlı kalmaz; Kayseri konumunda
/// Bartın gibi yanlış iller seçilmesini önler.
abstract final class KamiProvinceCenters {
  static const Map<String, LatLng> _byNormKey = {
    'adana': LatLng(37.0000, 35.3213),
    'adiyaman': LatLng(37.7648, 38.2786),
    'afyonkarahisar': LatLng(38.7507, 30.5567),
    'agri': LatLng(39.7191, 43.0503),
    'aksaray': LatLng(38.3687, 34.0370),
    'amasya': LatLng(40.6539, 35.8330),
    'ankara': LatLng(39.9334, 32.8597),
    'antalya': LatLng(36.8969, 30.7133),
    'ardahan': LatLng(41.1105, 42.7022),
    'artvin': LatLng(41.1828, 41.8183),
    'aydin': LatLng(37.8444, 27.8458),
    'balikesir': LatLng(39.6484, 27.8826),
    'bartin': LatLng(41.6344, 32.3375),
    'batman': LatLng(37.8812, 41.1351),
    'bayburt': LatLng(40.2552, 40.2249),
    'bilecik': LatLng(40.0567, 30.0665),
    'bingol': LatLng(38.8847, 40.4981),
    'bitlis': LatLng(38.4006, 42.1095),
    'bolu': LatLng(40.7392, 31.6089),
    'burdur': LatLng(37.7203, 30.2908),
    'bursa': LatLng(40.1826, 29.0665),
    'canakkale': LatLng(40.1553, 26.4142),
    'cankiri': LatLng(40.6013, 33.6134),
    'corum': LatLng(40.5506, 34.9556),
    'denizli': LatLng(37.7765, 29.0864),
    'diyarbakir': LatLng(37.9144, 40.2306),
    'duzce': LatLng(40.8438, 31.1565),
    'edirne': LatLng(41.6771, 26.5557),
    'elazig': LatLng(38.6810, 39.2264),
    'erzincan': LatLng(39.7500, 39.5000),
    'erzurum': LatLng(39.9043, 41.2679),
    'eskisehir': LatLng(39.7767, 30.5206),
    'gaziantep': LatLng(37.0662, 37.3833),
    'giresun': LatLng(40.9128, 38.3895),
    'gumushane': LatLng(40.4603, 39.4814),
    'hakkari': LatLng(37.5744, 43.7408),
    'hatay': LatLng(36.4018, 36.3498),
    'igdir': LatLng(39.9237, 44.0450),
    'isparta': LatLng(37.7648, 30.5566),
    'istanbul': LatLng(41.0082, 28.9784),
    'izmir': LatLng(38.4237, 27.1428),
    'kahramanmaras': LatLng(37.5858, 36.9371),
    'karabuk': LatLng(41.2061, 32.6204),
    'karaman': LatLng(37.1759, 33.2287),
    'kars': LatLng(40.6013, 43.0975),
    'kastamonu': LatLng(41.3887, 33.7827),
    'kayseri': LatLng(38.7312, 35.4787),
    'kilis': LatLng(36.7165, 37.1147),
    'kirikkale': LatLng(39.8468, 33.5153),
    'kirklareli': LatLng(41.7350, 27.2256),
    'kirsehir': LatLng(39.1425, 34.1709),
    'kocaeli': LatLng(40.8533, 29.8815),
    'konya': LatLng(37.8746, 32.4932),
    'kutahya': LatLng(39.4180, 29.9830),
    'malatya': LatLng(38.3552, 38.3095),
    'manisa': LatLng(38.6191, 27.4289),
    'mardin': LatLng(37.3212, 40.7245),
    'mersin': LatLng(36.8121, 34.6415),
    'mugla': LatLng(37.2153, 28.3636),
    'mus': LatLng(38.9462, 41.7539),
    'nevsehir': LatLng(38.6939, 34.6857),
    'nigde': LatLng(37.9667, 34.6857),
    'ordu': LatLng(40.9862, 37.8797),
    'osmaniye': LatLng(37.0742, 36.2478),
    'rize': LatLng(41.0201, 40.5234),
    'sakarya': LatLng(40.7569, 30.3783),
    'samsun': LatLng(41.2867, 36.3300),
    'sanliurfa': LatLng(37.1591, 38.7969),
    'siirt': LatLng(37.9333, 41.9500),
    'sinop': LatLng(42.0264, 35.1551),
    'sirnak': LatLng(37.5164, 42.4611),
    'sivas': LatLng(39.7477, 37.0179),
    'tekirdag': LatLng(40.9833, 27.5167),
    'tokat': LatLng(40.3167, 36.5500),
    'trabzon': LatLng(41.0015, 39.7178),
    'tunceli': LatLng(39.1079, 39.5401),
    'usak': LatLng(38.6823, 29.4082),
    'van': LatLng(38.4891, 43.4089),
    'yalova': LatLng(40.6500, 29.2667),
    'yozgat': LatLng(39.8181, 34.8147),
    'zonguldak': LatLng(41.4564, 31.7987),
  };

  static final Map<String, LatLng> byDisplayName = () {
    final out = <String, LatLng>{};
    for (final p in KamiCityResolver.provinces) {
      final c = centerFor(p);
      if (c != null) out[p] = c;
    }
    return out;
  }();

  static LatLng? centerFor(String displayName) {
    final key = KamiCityResolver.normalize(displayName);
    if (key.isEmpty) return null;
    return _byNormKey[key];
  }

  static String? displayNameForNorm(String normKey) {
    for (final p in KamiCityResolver.provinces) {
      if (KamiCityResolver.normalize(p) == normKey) return p;
    }
    return null;
  }
}
