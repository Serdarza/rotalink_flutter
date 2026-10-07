import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';
import 'package:rotalink_flutter/utils/il_ilce.dart';
import 'package:rotalink_flutter/utils/main_map_search.dart';
import 'package:rotalink_flutter/utils/search_normalize.dart';

Misafirhane _m(String il, String isim) => Misafirhane(
      isim: isim,
      il: il,
      adres: '',
      telefon: '',
      latitude: 0,
      longitude: 0,
      tip: 'Öğretmenevi',
    );

void main() {
  final kaynak = [
    _m('Düzce', 'Düzce Öğretmenevi'),
    _m('İstanbul', 'Beşiktaş Orduevi'),
    _m('Isparta', 'Isparta Öğretmenevi'),
  ];

  const queries = {
    'düzce': 'Düzce',
    'Düzce': 'Düzce',
    'DÜZCE': 'Düzce',
    'duzce': 'Düzce',
    'du\u0308zce': 'Düzce',
    'istanbul': 'İstanbul',
    'İstanbul': 'İstanbul',
    'İSTANBUL': 'İstanbul',
    'ISTANBUL': 'İstanbul',
    'I\u0307stanbul': 'İstanbul',
    'ıstanbul': 'İstanbul',
    'ısparta': 'Isparta',
    'ISPARTA': 'Isparta',
  };

  for (final e in queries.entries) {
    test('arama "${e.key}" → ${e.value}', () {
      final hits = MainMapSearch.perform(query: e.key, kaynak: kaynak, mapMisafirhaneler: kaynak);
      expect(hits.map((m) => m.il).toSet(), {e.value});
      expect(IlIlce.autocomplete(['Düzce', 'Isparta', 'İstanbul'], e.key).first, e.value);
    });
  }

  test('normalizeForSearch birleşik harfleri katlar', () {
    expect(normalizeForSearch('du\u0308zce'), 'duzce');
    expect(normalizeForSearch('I\u0307stanbul'), 'istanbul');
  });
}
