import 'route_stop.dart';
import '../services/osrm_route_service.dart';

/// Rota plan ekranından dönüş: duraklar ve isteğe bağlı OSRM segmentleri (çift istek önlenir).
class RoutePlanOutcome {
  const RoutePlanOutcome({
    required this.stops,
    this.segments,
  });

  final List<RouteStop> stops;
  final List<OsrmSegment>? segments;
}
