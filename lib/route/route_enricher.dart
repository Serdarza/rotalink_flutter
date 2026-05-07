import '../models/route_stop.dart';

/// Öneriler ve seçimler rota planı ekranında yönetilir; burada yalnızca geçirilir.
abstract final class RouteEnricher {
  static List<RouteStop> enrich(List<RouteStop> stops) => stops;
}
