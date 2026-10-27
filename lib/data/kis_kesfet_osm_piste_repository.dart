import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../models/kis_kesfet_osm_pist.dart';

/// Gömülü OpenStreetMap pist/lift geometrisi. Ana veritabanına dokunmaz.
abstract final class KisKesfetOsmPisteRepository {
  static const assetPath = 'assets/data/kis_kesfet_osm_pistes.json';

  static Map<String, KisKesfetOsmHarita>? _byId;

  static Future<void> ensureLoaded() async {
    if (_byId != null) return;
    final text = await rootBundle.loadString(assetPath);
    _byId = parse(text);
  }

  static Map<String, KisKesfetOsmHarita> parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    final rows = decoded['merkezler'];
    if (rows is! Map) return const {};
    final out = <String, KisKesfetOsmHarita>{};
    for (final entry in rows.entries) {
      final id = entry.key.toString();
      final row = entry.value;
      if (row is! Map) continue;
      final harita = _harita(row);
      if (harita.hasGeometry) out[id] = harita;
    }
    return out;
  }

  static bool contains(String id) => _byId?[id]?.hasGeometry == true;

  static Future<KisKesfetOsmHarita?> forId(String id) async {
    await ensureLoaded();
    return _byId?[id];
  }

  static KisKesfetOsmHarita _harita(Map row) {
    return KisKesfetOsmHarita(
      latitude: _num(row['latitude']),
      longitude: _num(row['longitude']),
      pistler: _cizgiler(row['pistler'], zorlukAl: true),
      liftler: _cizgiler(row['liftler'], zorlukAl: false),
    );
  }

  static List<KisKesfetOsmCizgi> _cizgiler(Object? raw, {required bool zorlukAl}) {
    if (raw is! List) return const [];
    final out = <KisKesfetOsmCizgi>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final pts = _noktalar(row['coords']);
      if (pts.length < 2) continue;
      out.add(
        KisKesfetOsmCizgi(
          ad: (row['ad'] ?? '').toString().trim(),
          tur: (row['tur'] ?? '').toString().trim(),
          zorluk: zorlukAl ? (row['zorluk'] ?? '').toString().trim() : '',
          noktalar: pts,
        ),
      );
    }
    return out;
  }

  static List<LatLng> _noktalar(Object? raw) {
    if (raw is! List) return const [];
    final out = <LatLng>[];
    for (final pair in raw) {
      if (pair is! List || pair.length < 2) continue;
      final lat = _num(pair[0]);
      final lng = _num(pair[1]);
      if (lat == null || lng == null) continue;
      out.add(LatLng(lat, lng));
    }
    return out;
  }

  static double? _num(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }
}
