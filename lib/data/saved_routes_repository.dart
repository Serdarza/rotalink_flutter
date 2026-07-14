import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
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
    final saved =
        (m['savedDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
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

/// Kayıtlı rota durağı — şehir, gün ve seçili tesis/gezi/yemek.
class RouteStopLite {
  const RouteStopLite({
    required this.city,
    required this.days,
    this.items = const [],
  });

  final String city;
  final int days;

  /// [Misafirhane] veya [GeziYemekItem] JSON map listesi.
  final List<Map<String, dynamic>> items;

  Map<String, dynamic> toJson() => {
        'city': city,
        'days': days,
        if (items.isNotEmpty) 'items': items,
      };

  static RouteStopLite? tryParse(Map<String, dynamic> m) {
    final city = (m['city'] ?? '').toString().trim();
    if (city.isEmpty) return null;
    final d = (m['days'] as num?)?.toInt() ?? 1;
    final rawItems = m['items'];
    final items = <Map<String, dynamic>>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is! Map) continue;
        items.add(e.map((k, v) => MapEntry(k.toString(), v)));
      }
    }
    return RouteStopLite(city: city, days: d, items: items);
  }

  factory RouteStopLite.fromRouteStop(RouteStop stop) {
    final items = <Map<String, dynamic>>[];
    for (final o in stop.items) {
      if (o is Misafirhane) {
        items.add({...o.toJson(), '_kind': 'tesis'});
      } else if (o is GeziYemekItem) {
        items.add({...o.toJson(), '_kind': 'gezi_yemek'});
      }
    }
    return RouteStopLite(city: stop.city, days: stop.days, items: items);
  }

  RouteStop toRouteStop() {
    final out = <Object>[];
    for (final raw in items) {
      final kind = (raw['_kind'] ?? '').toString();
      if (kind == 'tesis') {
        final m = Misafirhane.tryParse(raw);
        if (m != null) out.add(m);
        continue;
      }
      if (kind == 'gezi_yemek') {
        final g = GeziYemekItem.tryParse(raw);
        if (g != null) out.add(g);
        continue;
      }
      // Eski / belirsiz kayıtlar: önce tesis, değilse gezi-yemek dene.
      final m = Misafirhane.tryParse(raw);
      if (m != null && m.isim.trim().isNotEmpty) {
        out.add(m);
        continue;
      }
      final g = GeziYemekItem.tryParse(raw);
      if (g != null) out.add(g);
    }
    return RouteStop(city: city, days: days, items: out);
  }
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
