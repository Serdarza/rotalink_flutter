import '../recommendation/city_neighbors.dart';
import 'city_resolver.dart';

/// Türkiye il sınırı komşuluğuna göre bölgesel filtre — [KamiSystemInstruction] kural 2–3.
abstract final class KamiNeighborRegion {
  /// Çıkış ili + kara sınırı komşuları.
  static Set<String> allowedCities(String homeCity) {
    return {homeCity, ...KamiCityNeighbors.neighborsOf(homeCity)};
  }

  static bool isInRegion(String homeCity, String itemCity) {
    if (KamiCityResolver.sameCity(itemCity, homeCity)) return true;
    return KamiCityNeighbors.isNeighbor(homeCity, itemCity);
  }

  static bool isNeighborOnly(String homeCity, String itemCity) {
    return KamiCityNeighbors.isNeighbor(homeCity, itemCity);
  }

  static int countNeighborsInResults(String homeCity, Iterable<String> cities) {
    var n = 0;
    for (final c in cities) {
      if (isNeighborOnly(homeCity, c)) n++;
    }
    return n;
  }

  /// Kart bölüm başlığı — kural 4.
  static String sectionLabel(String homeCity, String itemCity) {
    if (KamiCityResolver.sameCity(itemCity, homeCity)) {
      return '$homeCity (bulunduğunuz il)';
    }
    return 'Komşu ilimiz $itemCity';
  }

  static String routeCitySectionLabel(String homeCity, String destinationCity) {
    if (KamiCityResolver.sameCity(destinationCity, homeCity)) {
      return destinationCity;
    }
    return 'Komşu ilimiz $destinationCity';
  }

  static String regionalSubtitle({
    required String homeCity,
    required int totalCount,
    int? neighborProvinceCount,
  }) {
    final neighbors = neighborProvinceCount ??
        KamiCityNeighbors.neighborsOf(homeCity).length;
    return 'Çıkış: $homeCity · $neighbors komşu il · $totalCount öneri';
  }
}
