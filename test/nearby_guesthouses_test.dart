import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';
import 'package:rotalink_flutter/services/nearby_guesthouses.dart';

Misafirhane facility(String name, double lat, double lon) => Misafirhane(
  isim: name,
  il: 'Ankara',
  adres: '',
  telefon: '',
  latitude: lat,
  longitude: lon,
  tip: 'Öğretmenevi',
);
void main() {
  test('Haversine bilinen mesafeyi ve aynı noktayı doğru hesaplar', () {
    expect(NearbyGuesthouses.haversineKm(39, 32, 39, 32), 0);
    expect(NearbyGuesthouses.haversineKm(0, 0, 0, 1), closeTo(111.195, 0.01));
    expect(
      NearbyGuesthouses.haversineKm(0, 0, 0, 180),
      closeTo(20015.114, 0.01),
    );
  });
  test('20/50/100 km sınırları, yakın sıralaması ve kimlik tekrarları', () {
    final close = facility('Yakın', 39.03, 32),
        medium = facility('Orta', 39.3, 32),
        far = facility('Uzak', 39.7, 32);
    final all = [far, medium, close, close];
    expect(NearbyGuesthouses.find(all, 39, 32).map((r) => r.facility.isim), [
      'Yakın',
    ]);
    expect(
      NearbyGuesthouses.find(
        all,
        39,
        32,
        radiusKm: 50,
      ).map((r) => r.facility.isim),
      ['Yakın', 'Orta'],
    );
    expect(
      NearbyGuesthouses.find(
        all,
        39,
        32,
        radiusKm: 100,
      ).map((r) => r.facility.isim),
      ['Yakın', 'Orta', 'Uzak'],
    );
  });
  test('eksik, NaN ve geçersiz koordinat mesafe üretmez', () {
    final all = [
      facility('Eksik', 0, 0),
      facility('Kısmi', 39, 0),
      facility('NaN', double.nan, 32),
      facility('Sınır', 91, 32),
    ];
    expect(NearbyGuesthouses.find(all, 39, 32, radiusKm: 10000), isEmpty);
    expect(
      NearbyGuesthouses.find([facility('A', 39, 32)], double.nan, 32),
      isEmpty,
    );
  });
  test('mesafe Türkçe virgül ve kuş uçuşu açıklaması içerir', () {
    expect(
      NearbyGuesthouse(facility('A', 39, 32), 3.42).distanceLabel,
      '3,4 km uzaklıkta · (Kuş Uçuşu)',
    );
    expect(
      NearbyGuesthouse(facility('A', 39, 32), 2.36).birdFlightLabel,
      '2,4 km · Kuş uçuşu',
    );
  });
}
