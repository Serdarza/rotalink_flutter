/// Kotlin [RouteStop]; [items] içinde [Misafirhane] ve [GeziYemekItem] karışık.
class RouteStop {
  RouteStop({
    required this.city,
    required this.days,
    List<Object>? items,
  }) : items = items ?? <Object>[];

  final String city;
  final int days;
  final List<Object> items;
}
