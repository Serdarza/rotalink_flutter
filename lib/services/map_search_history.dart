import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../billing/premium_auth_service.dart';

class OwnedLocation {
  const OwnedLocation({
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.source,
  });

  final String displayName;
  final double latitude;
  final double longitude;
  final String source;
}

class MapHistoryEntry {
  const MapHistoryEntry({
    required this.id,
    required this.displayName,
    required this.addressSummary,
    required this.radiusKm,
    required this.facilityType,
    required this.resultCount,
    required this.searchedAt,
    required this.originExpired,
    this.originLatitude,
    this.originLongitude,
    this.facilities = const [],
  });

  final String id;
  final String displayName;
  final String addressSummary;
  final double radiusKm;
  final String facilityType;
  final int resultCount;
  final DateTime searchedAt;
  final double? originLatitude;
  final double? originLongitude;
  final bool originExpired;
  final List<({String il, String isim})> facilities;

  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'addressSummary': addressSummary,
    'radiusKm': radiusKm,
    'facilityType': facilityType,
    'resultCount': resultCount,
    'searchedAt': searchedAt.toUtc().toIso8601String(),
    'originLatitude': originLatitude,
    'originLongitude': originLongitude,
    'facilities': [
      for (final facility in facilities)
        {'il': facility.il, 'isim': facility.isim},
    ],
  };

  static MapHistoryEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['displayName'];
    final summary = value['addressSummary'];
    final radius = value['radiusKm'];
    final type = value['facilityType'];
    final count = value['resultCount'];
    final searchedAt = value['searchedAt'];
    if (id is! String ||
        name is! String ||
        summary is! String ||
        radius is! num ||
        type is! String ||
        count is! num ||
        searchedAt is! String) {
      return null;
    }
    final parsed = DateTime.tryParse(searchedAt);
    if (parsed == null) return null;
    final rawFacilities = value['facilities'];
    return MapHistoryEntry(
      id: id,
      displayName: name,
      addressSummary: summary,
      radiusKm: radius.toDouble(),
      facilityType: type,
      resultCount: count.toInt(),
      searchedAt: parsed.toLocal(),
      originLatitude: value['originLatitude'] is num
          ? (value['originLatitude'] as num).toDouble()
          : null,
      originLongitude: value['originLongitude'] is num
          ? (value['originLongitude'] as num).toDouble()
          : null,
      originExpired: false,
      facilities: [
        for (final item in rawFacilities is List ? rawFacilities : const [])
          if (item is Map && item['il'] is String && item['isim'] is String)
            (il: item['il'] as String, isim: item['isim'] as String),
      ],
    );
  }
}

/// Harita aramaları bu telefonda durur. Sunucu ve giriş gerekmez.
abstract final class LocalMapSearchHistory {
  static const _key = 'map_search_history_v1';
  static const maxEntries = 100;

  static Future<List<MapHistoryEntry>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded) ?MapHistoryEntry.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> remember({
    required String displayName,
    required String addressSummary,
    required double radiusKm,
    required String facilityType,
    required double latitude,
    required double longitude,
    required List<({String il, String isim})> facilities,
  }) async {
    final current = await load();
    final entry = MapHistoryEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      displayName: displayName,
      addressSummary: addressSummary,
      radiusKm: radiusKm,
      facilityType: facilityType,
      resultCount: facilities.length,
      searchedAt: DateTime.now(),
      originLatitude: latitude,
      originLongitude: longitude,
      originExpired: false,
      facilities: facilities.take(400).toList(),
    );
    final next = [entry, ...current].take(maxEntries).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final item in next) item.toJson()]),
    );
  }

  static Future<void> delete(String id) async {
    final next = [
      for (final item in await load())
        if (item.id != id) item,
    ];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final item in next) item.toJson()]),
    );
  }
}

class MapHistoryPage {
  const MapHistoryPage({required this.items, this.nextCursor});

  final List<MapHistoryEntry> items;
  final String? nextCursor;
}

class MapHistoryDetail {
  const MapHistoryDetail({required this.entry, required this.facilities});

  final MapHistoryEntry entry;
  final List<({String il, String isim})> facilities;
}

/// Account map-search history on the existing admin worker.
///
/// Listing and replay never call geocode or nearby search.
abstract final class MapSearchHistory {
  static Future<List<OwnedLocation>> matchOwned(String query) async {
    final payload = await _send(
      'GET',
      '/api/premium/locations/match',
      query: {'q': query},
    );
    final raw = payload['matches'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map &&
            item['displayName'] is String &&
            item['latitude'] is num &&
            item['longitude'] is num &&
            item['source'] is String)
          OwnedLocation(
            displayName: item['displayName'] as String,
            latitude: (item['latitude'] as num).toDouble(),
            longitude: (item['longitude'] as num).toDouble(),
            source: item['source'] as String,
          ),
    ];
  }

  static Future<MapHistoryPage> list({String? cursor}) async {
    final payload = await _send(
      'GET',
      '/api/premium/history',
      query: {
        'limit': '20',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final raw = payload['items'];
    return MapHistoryPage(
      items: [
        for (final item in raw is List ? raw : const []) ?_entry(item),
      ],
      nextCursor: payload['nextCursor'] is String
          ? payload['nextCursor'] as String
          : null,
    );
  }

  static Future<MapHistoryDetail> facilities(String id) async {
    final payload = await _send('GET', '/api/premium/history/$id');
    final entry = _entry(payload);
    if (entry == null) {
      throw StateError('Kayıt okunamadı.');
    }
    final raw = payload['facilities'];
    return MapHistoryDetail(
      entry: entry,
      facilities: [
        for (final item in raw is List ? raw : const [])
          if (item is Map && item['il'] is String && item['isim'] is String)
            (il: item['il'] as String, isim: item['isim'] as String),
      ],
    );
  }

  static Future<void> save({
    required String displayName,
    required String addressSummary,
    required double radiusKm,
    required String facilityType,
    required double latitude,
    required double longitude,
    required String originSource,
    required List<({String il, String isim})> facilities,
  }) async {
    await _send(
      'POST',
      '/api/premium/history',
      body: {
        'displayName': displayName,
        'addressSummary': addressSummary,
        'radiusKm': radiusKm,
        'facilityType': facilityType,
        'latitude': latitude,
        'longitude': longitude,
        'originSource': originSource,
        'facilities': [
          for (final facility in facilities)
            {'il': facility.il, 'isim': facility.isim},
        ],
      },
    );
  }

  static Future<void> delete(String id) async {
    await _send('DELETE', '/api/premium/history/$id');
  }

  static MapHistoryEntry? _entry(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['displayName'];
    final summary = value['addressSummary'];
    final radius = value['radiusKm'];
    final type = value['facilityType'];
    final count = value['resultCount'];
    final searchedAt = value['searchedAt'];
    if (id is! String ||
        name is! String ||
        summary is! String ||
        radius is! num ||
        type is! String ||
        count is! num ||
        searchedAt is! String) {
      return null;
    }
    final parsed = DateTime.tryParse(searchedAt);
    if (parsed == null) return null;
    return MapHistoryEntry(
      id: id,
      displayName: name,
      addressSummary: summary,
      radiusKm: radius.toDouble(),
      facilityType: type,
      resultCount: count.toInt(),
      searchedAt: parsed.toLocal(),
      originLatitude: value['originLatitude'] is num
          ? (value['originLatitude'] as num).toDouble()
          : null,
      originLongitude: value['originLongitude'] is num
          ? (value['originLongitude'] as num).toDouble()
          : null,
      originExpired: value['originExpired'] == true,
    );
  }

  static Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final token = await PremiumAuthService.instance.freshIdToken();
    final uri = Uri.https('admin.rotalink.tr', path, query);
    final headers = {
      'authorization': 'Bearer $token',
      if (body != null) 'content-type': 'application/json',
    };
    final encoded = body == null ? null : jsonEncode(body);
    final response = await switch (method) {
      'POST' => http.post(uri, headers: headers, body: encoded),
      'DELETE' => http.delete(uri, headers: headers),
      _ => http.get(uri, headers: headers),
    }.timeout(const Duration(seconds: 20));
    final Object? value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {
      throw StateError('Arama geçmişine ulaşılamadı.');
    }
    if (value is! Map || response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        value is Map && value['error'] is String
            ? value['error'] as String
            : 'Arama geçmişi tamamlanamadı.',
      );
    }
    return value.cast<String, Object?>();
  }
}
