import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import 'recommendation_engine.dart';
import 'trip_score_service.dart';

/// "Bu hafta sonu nereye?" için özel facade.
abstract final class KamiWeekendRecommender {
  static List<KamiCityScore> suggest({
    required RotaDataState data,
    required LatLng user,
    Set<KamiTripFilter> filters = const {},
    int topN = 5,
  }) {
    return KamiRecommendationEngine.recommend(
      data: data,
      user: user,
      filters: filters,
      topN: topN,
      maxKm: KamiRecommendationEngine.defaultMaxKm,
    );
  }
}
