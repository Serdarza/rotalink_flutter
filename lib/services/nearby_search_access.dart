import 'dart:convert';

import 'package:http/http.dart' as http;

import '../billing/premium_auth_service.dart';

class NearbySearchAccessResult {
  const NearbySearchAccessResult({
    required this.accepted,
    this.empty = false,
    this.charged = false,
    this.remaining,
  });
  final bool accepted;
  final bool empty;

  /// True only when this response created a new nearby claim.
  final bool charged;
  final int? remaining;
}

class NearbyPlace {
  const NearbyPlace(this.name, this.latitude, this.longitude);
  final String name;
  final double latitude;
  final double longitude;
}

class PlacePrediction {
  const PlacePrediction(
    this.placeId,
    this.title,
    this.subtitle, {
    this.latitude,
    this.longitude,
  });
  final String? placeId;
  final String title;
  final String subtitle;
  final double? latitude;
  final double? longitude;

  bool get hasPoint =>
      latitude != null &&
      longitude != null &&
      latitude != 0 &&
      longitude != 0;
}

/// Only the verified server may consume a nearby-search entitlement.
abstract final class NearbySearchAccess {
  static Future<List<NearbyPlace>> geocode(String query) async {
    final token = await PremiumAuthService.instance.freshIdToken();
    final uri = Uri.https('admin.rotalink.tr', '/api/premium/nearby/geocode', {
      'q': query,
    });
    final response = await http
        .get(uri, headers: {'authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 15));
    final Object? value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {
      throw StateError(
        'Konum servisi yanıt vermedi. Haritadan nokta seçebilirsiniz.',
      );
    }
    if (value is! Map || response.statusCode != 200) {
      throw StateError(
        value is Map && value['error'] is String
            ? value['error'] as String
            : 'Konum bulunamadı. Haritadan nokta seçebilirsiniz.',
      );
    }
    final raw = value['results'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .where(
          (item) =>
              item['name'] is String &&
              item['latitude'] is num &&
              item['longitude'] is num,
        )
        .map(
          (item) => NearbyPlace(
            item['name'] as String,
            (item['latitude'] as num).toDouble(),
            (item['longitude'] as num).toDouble(),
          ),
        )
        .toList();
  }

  /// Yazarken Google Places önerisi. Arama hakkı düşmez.
  static Future<List<PlacePrediction>> suggest(String query) async {
    final token = await PremiumAuthService.instance.freshIdToken();
    final uri = Uri.https('admin.rotalink.tr', '/api/premium/nearby/suggest', {
      'q': query,
    });
    final response = await http
        .get(uri, headers: {'authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 8));
    final Object? value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {
      return const [];
    }
    if (value is! Map || response.statusCode != 200) return const [];
    final raw = value['suggestions'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map && item['title'] is String)
          if (item['placeId'] is String ||
              (item['latitude'] is num && item['longitude'] is num))
            PlacePrediction(
              item['placeId'] is String ? item['placeId'] as String : null,
              item['title'] as String,
              item['subtitle'] is String ? item['subtitle'] as String : '',
              latitude: item['latitude'] is num
                  ? (item['latitude'] as num).toDouble()
                  : null,
              longitude: item['longitude'] is num
                  ? (item['longitude'] as num).toDouble()
                  : null,
            ),
    ];
  }

  /// Hesap olmadan yer araması. Hak düşmez.
  static Future<List<NearbyPlace>> publicSearch(String query) async {
    final uri = Uri.https('admin.rotalink.tr', '/api/geo/search', {'q': query});
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    return _places(response);
  }

  static List<NearbyPlace> _places(http.Response response) {
    final Object? value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {
      return const [];
    }
    if (value is! Map || response.statusCode != 200) return const [];
    final raw = value['results'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .where(
          (item) =>
              item['name'] is String &&
              item['latitude'] is num &&
              item['longitude'] is num,
        )
        .map(
          (item) => NearbyPlace(
            item['name'] as String,
            (item['latitude'] as num).toDouble(),
            (item['longitude'] as num).toDouble(),
          ),
        )
        .toList();
  }

  /// Seçilen yerin koordinatı. Bulunamazsa veya servis hata verirse hak düşmez.
  static Future<NearbyPlace?> place(String placeId) async {
    final token = await PremiumAuthService.instance.freshIdToken();
    final uri = Uri.https('admin.rotalink.tr', '/api/premium/nearby/place', {
      'id': placeId,
    });
    final response = await http
        .get(uri, headers: {'authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 12));
    final Object? value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {
      throw StateError(
        'Konum servisi yanıt vermedi. Haritadan nokta seçebilirsiniz.',
      );
    }
    if (response.statusCode == 404) return null;
    if (value is! Map || response.statusCode != 200) {
      throw StateError(
        value is Map && value['error'] is String
            ? value['error'] as String
            : 'Konum servisine ulaşılamadı.',
      );
    }
    final name = value['name'];
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    if (name is! String || latitude is! num || longitude is! num) return null;
    return NearbyPlace(name, latitude.toDouble(), longitude.toDouble());
  }

  static Future<NearbySearchAccessResult> claim(
    double latitude,
    double longitude,
    double radiusKm,
  ) async {
    final token = await PremiumAuthService.instance.freshIdToken();
    final response = await http
        .post(
          Uri.parse('https://admin.rotalink.tr/api/premium/nearby/search'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'latitude': latitude,
            'longitude': longitude,
            'radiusKm': radiusKm,
          }),
        )
        .timeout(const Duration(seconds: 25));
    final Object? value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {
      throw StateError(
        'Konum arama servisine ulaşılamadı. Daha sonra tekrar deneyin.',
      );
    }
    if (value is! Map) {
      throw StateError('Konum arama servisi geçersiz yanıt verdi.');
    }
    if (response.statusCode == 429) {
      return const NearbySearchAccessResult(accepted: false);
    }
    if (response.statusCode != 200) {
      throw StateError(
        value['error']?.toString() ?? 'Konum araması tamamlanamadı.',
      );
    }
    return NearbySearchAccessResult(
      accepted: value['accepted'] == true,
      empty: value['empty'] == true,
      charged: value['charged'] == true,
      remaining: value['remaining'] is num
          ? (value['remaining'] as num).toInt()
          : null,
    );
  }
}
