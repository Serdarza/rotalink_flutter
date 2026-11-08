import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';
import 'package:rotalink_flutter/utils/geo_helpers.dart';

Misafirhane _facility(String name, double lat, double lon) {
  return Misafirhane(
    isim: name,
    il: 'Ankara',
    adres: '',
    telefon: '',
    latitude: lat,
    longitude: lon,
    tip: 'Öğretmenevi',
  );
}

void main() {
  test('konum yoksa tesis sırası değişmez', () {
    final list = [
      _facility('Uzak', 41.0, 29.0),
      _facility('Yakın', 39.93, 32.86),
    ];
    final sorted = sortMisafirhaneByDistance(list, null);
    expect(sorted.map((m) => m.isim).toList(), ['Uzak', 'Yakın']);
  });

  test('(0,0) konum tesisleri sıralamaz', () {
    final list = [
      _facility('Uzak', 41.0, 29.0),
      _facility('Yakın', 39.93, 32.86),
    ];
    final sorted = sortMisafirhaneByDistance(list, const LatLng(0, 0));
    expect(sorted.map((m) => m.isim).toList(), ['Uzak', 'Yakın']);
  });

  test('geçerli konumda en yakın tesis başa gelir', () {
    final list = [
      _facility('Uzak', 41.01, 28.98),
      _facility('Yakın', 39.93, 32.86),
      _facility('Orta', 39.75, 30.52),
    ];
    final sorted = sortMisafirhaneByDistance(list, const LatLng(39.92, 32.85));
    expect(sorted.first.isim, 'Yakın');
    expect(sorted.last.isim, 'Uzak');
  });
}
