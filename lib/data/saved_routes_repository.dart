import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/route_stop.dart';

/// Kotlin `encryptedPrefs` + `saved_routes` anahtarı; en fazla 5 rota.
class SavedRouteRecord {
  const SavedRouteRecord({
    required this.name,
    required this.savedDateMillis,
    required this.stops,
  });

  final String name;
  final int savedDateMillis;
  final List<RouteStopLite> stops;

  Map<String, dynamic> toJson() => {
        'name': name,
        'savedDate': savedDateMillis,
        'routeStops': stops.map((e) => e.toJson()).toList(),
      };

  static SavedRouteRecord? tryParse(Map<String, dynamic> m) {
    final name = (m['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final saved = (m['savedDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final rawStops = m['routeStops'] as List<dynamic>? ?? const [];
    final stops = rawStops.map((e) {
      if (e is! Map) return null;
      final mm = e.map((k, v) => MapEntry(k.toString(), v));
      return RouteStopLite.tryParse(mm);
    }).whereType<RouteStopLite>().toList();
    if (stops.isEmpty) return null;
    return SavedRouteRecord(name: name, savedDateMillis: saved, stops: stops);
  }
}

class RouteStopLite {
  const RouteStopLite({required this.city, required this.days});

  final String city;
  final int days;

  Map<String, dynamic> toJson() => {'city': city, 'days': days};

  static RouteStopLite? tryParse(Map<String, dynamic> m) {
    final city = (m['city'] ?? '').toString().trim();
    if (city.isEmpty) return null;
    final d = (m['days'] as num?)?.toInt() ?? 1;
    return RouteStopLite(city: city, days: d);
  }

  RouteStop toRouteStop() => RouteStop(city: city, days: days, items: []);
}

class SavedRoutesRepository {
  SavedRoutesRepository({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;

  static const _key = 'saved_routes';
  static const int maxRoutes = 5;

  Future<SharedPreferences> _sp() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<List<SavedRouteRecord>> loadAll() async {
    final sp = await _sp();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) {
            if (e is! Map) return null;
            final m = e.map((k, v) => MapEntry(k.toString(), v));
            return SavedRouteRecord.tryParse(m);
          })
          .whereType<SavedRouteRecord>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsert(SavedRouteRecord route) async {
    final sp = await _sp();
    var list = await loadAll();
    final idx = list.indexWhere((r) => r.name == route.name);
    if (idx >= 0) {
      final copy = List<SavedRouteRecord>.from(list);
      copy[idx] = route;
      list = copy;
    } else {
      if (list.length >= maxRoutes) {
        list = [...list.sublist(1), route];
      } else {
        list = [...list, route];
      }
    }
    await sp.setString(
      _key,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> deleteByName(String name) async {
    final sp = await _sp();
    final list = (await loadAll()).where((r) => r.name != name).toList();
    await sp.setString(
      _key,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }
}
