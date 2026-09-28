import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';
import 'package:rotalink_flutter/utils/main_map_search.dart';

Misafirhane _m(String il, String isim) => Misafirhane(
      isim: isim,
      il: il,
      adres: '',
      telefon: '',
      latitude: 0,
      longitude: 0,
      tip: '',
    );

void main() {
  final kaynak = [
    _m('Ankara', 'Ankara Öğretmenevi'),
    _m('Ankara', 'Gölbaşı Öğretmenevi'),
    _m('Bolu', 'Ankara Caddesi Misafirhanesi'),
    _m('İstanbul', 'İstanbul Kalender Öğretmenevi'),
    _m('İstanbul', 'Şişli Öğretmenevi'),
    _m('Kahramanmaraş', 'Kahramanmaraş Öğretmenevi'),
  ];

  Misafirhane? target(String q) {
    final narrow = MainMapSearch.narrowFuzzyMatches(query: q, kaynak: kaynak);
    return MainMapSearch.findPrimaryMatchForScroll(
      query: q,
      displayedFacilities: narrow.isNotEmpty ? narrow : kaynak,
    );
  }

  test('yalnızca il adı: tesis hedeflenmez', () {
    expect(target('Ankara'), isNull);
    expect(target('istanbul'), isNull);
    expect(target('Kahraman Maraş'), isNull);
  });

  test('il adından farklı arama: tesis hedeflenir', () {
    expect(target('İstanbul Kalender')?.isim, 'İstanbul Kalender Öğretmenevi');
    expect(target('kalender')?.isim, 'İstanbul Kalender Öğretmenevi');
    expect(target('Gölbaşı')?.isim, 'Gölbaşı Öğretmenevi');
  });

  test('il araması o ilin tüm tesislerini listeler', () {
    final list = MainMapSearch.perform(query: 'Ankara', kaynak: kaynak, mapMisafirhaneler: const []);
    expect(list.map((m) => m.il).toSet(), {'Ankara'});
    expect(list, hasLength(2));
  });
}
