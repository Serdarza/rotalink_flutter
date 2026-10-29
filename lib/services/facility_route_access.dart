import 'dart:convert';

import 'package:http/http.dart' as http;

import '../billing/premium_auth_service.dart';
import 'facility_route.dart';

/// One driving or walking route. Repeating the same facility uses the saved result.
abstract final class FacilityRouteAccess {
  static final Map<String, FacilityRoute> _memory = {};

  static Future<FacilityRoute> fetch({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required String mode,
  }) async {
    final key =
        '$mode:${(originLat * 100).round()}:${(originLon * 100).round()}:'
        '${destLat.toStringAsFixed(4)}:${destLon.toStringAsFixed(4)}';
    final saved = _memory[key];
    if (saved != null) return saved;
    final token = await PremiumAuthService.instance.freshIdToken();
    final uri = Uri.https('admin.rotalink.tr', '/api/premium/nearby/route', {
      'originLat': originLat.toStringAsFixed(6),
      'originLon': originLon.toStringAsFixed(6),
      'destLat': destLat.toStringAsFixed(6),
      'destLon': destLon.toStringAsFixed(6),
      'mode': mode,
    });
    final response = await http
        .get(uri, headers: {'authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 20));
    final Object? value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {
      throw StateError('Yol hesabına ulaşılamadı. Daha sonra tekrar deneyin.');
    }
    if (value is! Map || response.statusCode != 200) {
      throw StateError(
        value is Map && value['error'] is String
            ? value['error'] as String
            : 'Yol hesabı tamamlanamadı.',
      );
    }
    final points = value['points'];
    final meters = value['distanceMeters'];
    final seconds = value['durationSeconds'];
    if (points is! List || meters is! num || seconds is! num) {
      throw StateError('Yol hesabı geçersiz yanıt verdi.');
    }
    final route = FacilityRoute(
      mode: mode,
      distanceMeters: meters.toInt(),
      durationSeconds: seconds.toInt(),
      points: [
        for (final point in points)
          if (point is Map &&
              point['latitude'] is num &&
              point['longitude'] is num)
            (
              latitude: (point['latitude'] as num).toDouble(),
              longitude: (point['longitude'] as num).toDouble(),
            ),
      ],
    );
    if (route.points.length < 2) {
      throw StateError('Yol hesabı geçersiz yanıt verdi.');
    }
    _memory[key] = route;
    return route;
  }
}
