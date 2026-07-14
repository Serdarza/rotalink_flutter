import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import 'distance_service.dart';
import 'recommendation_engine.dart';
import 'route_optimizer.dart';
import 'trip_score_service.dart';
import 'weekend_recommender.dart';

/// KAMİ öneri API'si — puanlama + hafta sonu + rota detayı.
class KamiRecommendationService {
  const KamiRecommendationService();

  List<KamiCityScore> weekendSuggestions({
    required RotaDataState data,
    required LatLng user,
    Set<KamiTripFilter> filters = const {},
  }) {
    return KamiWeekendRecommender.suggest(
      data: data,
      user: user,
      filters: filters,
    );
  }

  List<KamiCityScore> recommend({
    required RotaDataState data,
    required LatLng user,
    Set<KamiTripFilter> filters = const {},
    int topN = 5,
    double maxKm = 350,
  }) {
    return KamiRecommendationEngine.recommend(
      data: data,
      user: user,
      filters: filters,
      topN: topN,
      maxKm: maxKm,
    );
  }

  List<KamiCityScore> nearbyRouteSuggestions({
    required RotaDataState data,
    required LatLng user,
    required String homeCity,
  }) {
    return KamiRecommendationEngine.nearbyRouteDestinations(
      data: data,
      user: user,
      homeCity: homeCity,
    );
  }

  Future<KamiOptimizedTrip> optimizeTrip({
    required RotaDataState data,
    required LatLng user,
    required KamiCityScore destination,
  }) {
    return KamiRouteOptimizer.buildTrip(
      data: data,
      user: user,
      destination: destination,
    );
  }

  String formatKm(double km) => KamiDistanceService.formatKm(km);
  String formatDrive(int minutes) => KamiDistanceService.formatDrive(minutes);
}
