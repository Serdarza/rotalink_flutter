import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/services/facility_route.dart';

void main() {
  test('yürüme sınırı ve süre yazımı', () {
    expect(FacilityRouteFormat.walkingOffered(15), isTrue);
    expect(FacilityRouteFormat.walkingOffered(15.1), isFalse);
    expect(FacilityRouteFormat.distance(850), '850 m');
    expect(FacilityRouteFormat.distance(12400), '12,4 km');
    expect(FacilityRouteFormat.summary(12400, 18 * 60), '12,4 km · 18 dk');
    expect(FacilityRouteFormat.duration(90 * 60), '1 sa 30 dk');
  });

  test('yürüme çizgisi işaretlenen noktadan başlar', () {
    final route = FacilityRoute(
      mode: 'walk',
      distanceMeters: 420,
      durationSeconds: 300,
      points: [
        (latitude: 39.9210, longitude: 32.8550),
        (latitude: 39.9230, longitude: 32.8580),
      ],
    );
    final drawn = FacilityRouteDraw.of(
      route,
      originLatitude: 39.9200,
      originLongitude: 32.8540,
      destinationLatitude: 39.9234,
      destinationLongitude: 32.8586,
    );
    expect(drawn.fromMarkedPoint.first.latitude, 39.9200);
    expect(drawn.fromMarkedPoint.first.longitude, 32.8540);
    expect(drawn.fromMarkedPoint.last.latitude, 39.9210);
    expect(drawn.road.first.latitude, 39.9210);
    expect(drawn.toFacility.last.latitude, 39.9234);
  });
}
