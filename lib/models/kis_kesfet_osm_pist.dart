import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

@immutable
class KisKesfetOsmCizgi {
  const KisKesfetOsmCizgi({
    required this.ad,
    required this.tur,
    required this.zorluk,
    required this.noktalar,
  });

  final String ad;
  final String tur;
  final String zorluk;
  final List<LatLng> noktalar;

  bool get hasLine => noktalar.length >= 2;

  /// Şehir teleferiği gibi pist sahasının dışındaki uzun hat.
  bool get isLongHaul {
    if (noktalar.length < 2) return false;
    final a = noktalar.first;
    final b = noktalar.last;
    return (a.latitude - b.latitude).abs() > 0.03 ||
        (a.longitude - b.longitude).abs() > 0.03;
  }
}

@immutable
class KisKesfetOsmHarita {
  const KisKesfetOsmHarita({
    required this.pistler,
    required this.liftler,
    this.latitude,
    this.longitude,
  });

  final List<KisKesfetOsmCizgi> pistler;
  final List<KisKesfetOsmCizgi> liftler;
  final double? latitude;
  final double? longitude;

  bool get hasGeometry =>
      pistler.any((p) => p.hasLine) || liftler.any((p) => p.hasLine);

  LatLng get center {
    final b = cameraBounds;
    if (b != null) {
      return LatLng(
        (b.south + b.north) / 2,
        (b.west + b.east) / 2,
      );
    }
    if (latitude != null && longitude != null) {
      return LatLng(latitude!, longitude!);
    }
    return const LatLng(39.0, 35.0);
  }

  /// Kamera pistlere sığar; şehir teleferiği gibi uzun hatlar dışarıda kalır.
  ({double south, double west, double north, double east})? get cameraBounds {
    final pts = [
      for (final p in pistler)
        if (p.hasLine) ...p.noktalar,
    ];
    if (pts.isEmpty) {
      pts.addAll([
        for (final l in liftler)
          if (l.hasLine && !l.isLongHaul) ...l.noktalar,
      ]);
    }
    if (pts.isEmpty) return null;
    var s = pts.first.latitude;
    var n = pts.first.latitude;
    var w = pts.first.longitude;
    var e = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < s) s = p.latitude;
      if (p.latitude > n) n = p.latitude;
      if (p.longitude < w) w = p.longitude;
      if (p.longitude > e) e = p.longitude;
    }
    return (south: s, west: w, north: n, east: e);
  }
}
