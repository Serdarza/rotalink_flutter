import '../kami/engine/city_resolver.dart';
import 'nearby_guesthouses.dart';

/// Konum ekranının mesafe ve liste kuralları.
///
/// Sunucu 5, 10, 25, 50 ve 2000 km kabul eder. 2000 km ekranda Türkiye
/// olarak görünür. Hak yaklaşık 1 km'lik hücreye yazılır; aynı hücrede mesafe
/// veya tür değiştirmek yeni hak açmaz.
abstract final class LocationDiscoveryQuery {
  static const List<double> radiiKm = [5, 10, 25, 50, 2000];

  static const List<String> facilityTypes = [
    'Tümü',
    'Orduevi',
    'Polisevi',
    'Öğretmenevi',
  ];

  static const List<String> sorts = ['En yakın', 'En uzak', 'Ada göre'];

  static String radiusLabel(double radiusKm) =>
      radiusKm >= 2000 ? 'Türkiye' : '${radiusKm.toInt()} km';

  static String actionLabel(double radiusKm) => radiusKm >= 2000
      ? 'Türkiye genelinde göster'
      : '${radiusKm.toInt()} km çevresinde göster';

  static double zoomForRadius(double radiusKm) {
    if (radiusKm >= 2000) return 5.4;
    if (radiusKm >= 50) return 9.2;
    if (radiusKm >= 25) return 10.4;
    if (radiusKm >= 10) return 11.6;
    return 12.8;
  }

  static String kilometers(double km) =>
      '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

  /// Sunucudaki `nearby:{lat*100}:{lon*100}` hücresiyle aynı yuvarlama.
  static bool sameCell(
    double latitude,
    double longitude,
    double otherLatitude,
    double otherLongitude,
  ) =>
      (latitude * 100).round() == (otherLatitude * 100).round() &&
      (longitude * 100).round() == (otherLongitude * 100).round();

  static bool matchesType(String tip, String filter) {
    if (filter == 'Tümü') return true;
    final type = KamiCityResolver.normalize(tip);
    return switch (filter) {
      'Öğretmenevi' => type.contains('ogretmen'),
      'Polisevi' => type.contains('polis'),
      'Orduevi' => type.contains('ordu'),
      'Kamu misafirhanesi' => type.contains('misafirhane'),
      _ =>
        !type.contains('ogretmen') &&
            !type.contains('polis') &&
            !type.contains('ordu') &&
            !type.contains('misafirhane'),
    };
  }

  static List<NearbyGuesthouse> present(
    List<NearbyGuesthouse> items, {
    required String type,
    required String sort,
  }) {
    final filtered = items
        .where((item) => matchesType(item.facility.tip, type))
        .toList();
    switch (sort) {
      case 'En uzak':
        filtered.sort((a, b) => b.km.compareTo(a.km));
      case 'Ada göre':
        filtered.sort((a, b) => a.facility.isim.compareTo(b.facility.isim));
      default:
        filtered.sort((a, b) => a.km.compareTo(b.km));
    }
    return filtered;
  }
}
