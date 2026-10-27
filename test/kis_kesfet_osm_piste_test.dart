import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/data/kis_kesfet_osm_piste_repository.dart';
import 'package:rotalink_flutter/data/kis_kesfet_repository.dart';

void main() {
  test('OSM pist katmanı 9 kayak merkezini Palandöken ve Konaklı ayrı tutar', () {
    final raw = File('assets/data/kis_kesfet_osm_pistes.json').readAsStringSync();
    final haritalar = KisKesfetOsmPisteRepository.parse(raw);

    expect(haritalar.keys, hasLength(9));
    expect(haritalar.containsKey('kayak-erzurum-kandilli'), isFalse);
    expect(haritalar['kayak-kayseri-erciyes']!.pistler, isNotEmpty);
    expect(haritalar['kayak-bursa-uludag']!.pistler.length, greaterThan(10));
    expect(haritalar['kayak-kastamonu-ilgaz']!.pistler, isNotEmpty);

    final pala = haritalar['kayak-erzurum-palandoken']!.cameraBounds!;
    final konak = haritalar['kayak-erzurum-konakli']!.cameraBounds!;
    expect(pala.north < konak.south || konak.north < pala.south, isTrue);
    expect(pala.east < konak.west || konak.east < pala.west, isTrue);

    final uludag = haritalar['kayak-bursa-uludag']!;
    expect(uludag.cameraBounds!.north, lessThan(40.13));
  });

  test('gömülü kayak kayıtları OSM koordinatını ve Kandilli yedeğini korur', () {
    final places = KisKesfetRepository.parse(
      File('assets/data/kis_kesfet.json').readAsStringSync(),
    );
    final kayak = places.where((p) => p.isKayak).toList();
    expect(kayak, hasLength(10));

    final osm = KisKesfetOsmPisteRepository.parse(
      File('assets/data/kis_kesfet_osm_pistes.json').readAsStringSync(),
    );
    for (final place in kayak) {
      if (place.id == 'kayak-erzurum-kandilli') {
        expect(osm.containsKey(place.id), isFalse);
        expect(place.pistHaritasiBaglanti, isNotNull);
        continue;
      }
      expect(osm[place.id]!.hasGeometry, isTrue);
      expect(place.hasCoordinates, isTrue);
    }
  });
}
