import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';
import 'package:rotalink_flutter/services/location_discovery_query.dart';
import 'package:rotalink_flutter/services/nearby_guesthouses.dart';

NearbyGuesthouse stay(String name, String tip, double km) => NearbyGuesthouse(
  Misafirhane(
    isim: name,
    il: 'Ankara',
    adres: '',
    telefon: '',
    latitude: 39,
    longitude: 32,
    tip: tip,
  ),
  km,
);

void main() {
  test('mesafe seçenekleri sunucunun kabul ettiği değerlerdir', () {
    expect(LocationDiscoveryQuery.radiiKm, [5, 10, 25, 50, 2000]);
    expect(LocationDiscoveryQuery.radiusLabel(5), '5 km');
    expect(LocationDiscoveryQuery.radiusLabel(50), '50 km');
    expect(LocationDiscoveryQuery.radiusLabel(2000), 'Türkiye');
    expect(
      LocationDiscoveryQuery.actionLabel(2000),
      'Türkiye genelinde göster',
    );
    expect(LocationDiscoveryQuery.actionLabel(10), '10 km çevresinde göster');
    expect(LocationDiscoveryQuery.kilometers(2.4), '2,4 km');
  });

  test('aynı yaklaşık 1 km hücre yeni arama sayılmaz', () {
    expect(
      LocationDiscoveryQuery.sameCell(39.001, 32.001, 39.004, 32.004),
      isTrue,
    );
    expect(LocationDiscoveryQuery.sameCell(39.001, 32, 39.009, 32), isFalse);
  });

  test('tür ve sıralama listeyi hak düşürmeden süzer', () {
    final items = [
      stay('Zeta', 'Polisevi', 4),
      stay('Alfa', 'Öğretmenevi', 1),
      stay('Beta', 'Orduevi', 2),
    ];
    expect(
      LocationDiscoveryQuery.present(
        items,
        type: 'Öğretmenevi',
        sort: 'En yakın',
      ).map((item) => item.facility.isim),
      ['Alfa'],
    );
    expect(
      LocationDiscoveryQuery.present(
        items,
        type: 'Tümü',
        sort: 'Ada göre',
      ).map((item) => item.facility.isim),
      ['Alfa', 'Beta', 'Zeta'],
    );
    expect(
      LocationDiscoveryQuery.present(
        items,
        type: 'Tümü',
        sort: 'En uzak',
      ).map((item) => item.facility.isim),
      ['Zeta', 'Beta', 'Alfa'],
    );
  });
}
