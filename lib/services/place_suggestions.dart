import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../kami/engine/city_resolver.dart';
import '../utils/text_encoding.dart';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
    this.placeId,
    this.recent = false,
  });

  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;

  /// Google Places kimliği. Koordinat seçilince Place ID ile alınır.
  final String? placeId;
  final bool recent;
}

/// Son üç yer araması. Google çağrısı yapmaz.
abstract final class PlaceSearchHistory {
  static const _key = 'location_place_history_v1';

  static Future<List<PlaceSuggestion>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    return [
      for (final line in raw.take(3)) ?_parse(line),
    ];
  }

  static Future<List<PlaceSuggestion>> remember(PlaceSuggestion item) async {
    final current = await load();
    final next = <PlaceSuggestion>[
      PlaceSuggestion(
        title: item.title,
        subtitle: 'Son arama',
        latitude: item.latitude,
        longitude: item.longitude,
        recent: true,
      ),
      for (final saved in current)
        if (!_same(saved, item)) saved,
    ].take(3).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [
      for (final saved in next)
        '${saved.latitude}|${saved.longitude}|${saved.title}',
    ]);
    return next;
  }

  static bool _same(PlaceSuggestion a, PlaceSuggestion b) =>
      a.title.toLowerCase() == b.title.toLowerCase();

  static PlaceSuggestion? _parse(String line) {
    final parts = line.split('|');
    if (parts.length < 3) return null;
    final latitude = double.tryParse(parts[0]);
    final longitude = double.tryParse(parts[1]);
    final title = parts.sublist(2).join('|').trim();
    if (latitude == null || longitude == null || title.isEmpty) return null;
    return PlaceSuggestion(
      title: title,
      subtitle: 'Son arama',
      latitude: latitude,
      longitude: longitude,
      recent: true,
    );
  }
}

/// Yazarken Türkiye içinden Photon önerisi. Seçim Google’a gitmez.
abstract final class PhotonPlaceSearch {
  static const _bbox = '25.6,34.9,44.95,42.2';
  static const _agent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';
  static final Map<String, Future<List<({int score, PlaceSuggestion item})>>>
      _inflight = {};
  static final Map<String, ({DateTime at, List<({int score, PlaceSuggestion item})> rows})>
      _memory = {};

  static Future<List<PlaceSuggestion>> suggest(String query) async {
    final ranked = await _ranked(query);
    return [for (final row in ranked.take(5)) row.item];
  }

  /// Çok kelimeli sorguda il merkezini değil, ada uyan yeri seçer.
  static Future<PlaceSuggestion?> best(String query) async {
    final ranked = await _ranked(query);
    if (ranked.isEmpty) return null;
    final words = KamiCityResolver.normalize(query)
        .split(' ')
        .where((word) => word.isNotEmpty)
        .length;
    if (words >= 2 && ranked.first.score <= 0) return null;
    return ranked.first.item;
  }

  /// Diğer kaynaklar boşsa eldeki en iyi Photon noktasını kullanır.
  static Future<PlaceSuggestion?> any(String query) async {
    final ranked = await _ranked(query);
    if (ranked.isEmpty) return null;
    return ranked.first.item;
  }

  static Future<List<({int score, PlaceSuggestion item})>> _ranked(
    String query,
  ) {
    final raw = query.trim();
    final key = KamiCityResolver.normalize(raw);
    if (raw.length < 3) return Future.value(const []);
    final saved = _memory[key];
    if (saved != null &&
        saved.rows.isNotEmpty &&
        DateTime.now().difference(saved.at) < const Duration(minutes: 3)) {
      return Future.value(saved.rows);
    }
    final pending = _inflight[key];
    if (pending != null) return pending;
    late final Future<List<({int score, PlaceSuggestion item})>> future;
    future = _load(raw).then((rows) {
      if (rows.isNotEmpty) {
        _memory[key] = (at: DateTime.now(), rows: rows);
      }
      return rows;
    }).whenComplete(() {
      if (identical(_inflight[key], future)) _inflight.remove(key);
    });
    _inflight[key] = future;
    return future;
  }

  static Future<List<({int score, PlaceSuggestion item})>> _load(
    String raw,
  ) async {
    final first = await _request(raw);
    if (first != null) return first;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return await _request(raw) ?? const [];
  }

  static Future<List<({int score, PlaceSuggestion item})>?> _request(
    String raw,
  ) async {
    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/api/'
        '?q=${Uri.encodeComponent(raw)}'
        '&limit=8'
        '&bbox=$_bbox'
        '&lang=tr',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': _agent})
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 429 || response.statusCode >= 500) {
        return null;
      }
      if (response.statusCode != 200) return const [];
      final root = jsonDecode(responseText(response));
      if (root is! Map) return const [];
      final features = root['features'];
      if (features is! List) return const [];
      final found = <({int score, PlaceSuggestion item})>[];
      final seen = <String>{};
      for (final feature in features) {
        final item = _feature(feature);
        if (item == null) continue;
        final key = item.title.toLowerCase();
        if (!seen.add(key)) continue;
        final props = feature is Map ? feature['properties'] : null;
        found.add((
          score: props is Map ? _score(props, raw) : 0,
          item: item,
        ));
      }
      found.sort((a, b) => b.score.compareTo(a.score));
      return found;
    } catch (_) {
      return null;
    }
  }

  static int _score(Map<dynamic, dynamic> props, String query) {
    final name = KamiCityResolver.normalize(props['name']?.toString() ?? '');
    final value = props['osm_value']?.toString() ?? '';
    final key = props['osm_key']?.toString() ?? '';
    var score = 0;
    for (final token in KamiCityResolver.normalize(query).split(' ')) {
      if (token.length < 3) continue;
      if (name.contains(token)) score += 4;
    }
    final settlement =
        value == 'city' ||
        value == 'town' ||
        value == 'administrative' ||
        (key == 'place' && (value == 'city' || value == 'town'));
    if (settlement) score -= 5;
    if (value == 'mosque' ||
        value == 'place_of_worship' ||
        value == 'attraction' ||
        value == 'hotel' ||
        value == 'guest_house') {
      score += 6;
    }
    return score;
  }

  static PlaceSuggestion? _feature(Object? feature) {
    if (feature is! Map) return null;
    final props = feature['properties'];
    final geometry = feature['geometry'];
    if (props is! Map || geometry is! Map) return null;
    final country = props['countrycode']?.toString().toUpperCase();
    if (country != null && country.isNotEmpty && country != 'TR') return null;
    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    final longitude = double.tryParse(coords[0].toString());
    final latitude = double.tryParse(coords[1].toString());
    if (latitude == null || longitude == null) return null;
    if (latitude < 35.5 ||
        latitude > 42.5 ||
        longitude < 25 ||
        longitude > 45.5) {
      return null;
    }
    final name = props['name']?.toString().trim() ?? '';
    final street = props['street']?.toString().trim() ?? '';
    final number = props['housenumber']?.toString().trim() ?? '';
    final title = name.isNotEmpty
        ? name
        : [street, number].where((part) => part.isNotEmpty).join(' ');
    if (title.isEmpty) return null;
    final city = props['city']?.toString().trim() ?? '';
    final county = props['county']?.toString().trim() ?? '';
    final state = props['state']?.toString().trim() ?? '';
    final subtitle = [
      if (county.isNotEmpty && county != city) county,
      if (city.isNotEmpty) city else state,
    ].join(' · ');
    return PlaceSuggestion(
      title: title,
      subtitle: subtitle.isEmpty ? 'Harita' : subtitle,
      latitude: latitude,
      longitude: longitude,
    );
  }
}
