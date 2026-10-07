import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/data/hediyelik_repository.dart';
import 'package:rotalink_flutter/utils/search_normalize.dart';

void main() {
  const json = '''
{
  "guncelleme": "2026-10-01",
  "iller": {
    "Düzce": [
      {"ad": "Tütün Kolonyası", "aciklama": "Kolonya.", "kategori": "Yöresel ürün", "cografi_isaret": false},
      {"ad": "Düzce Kestane Balı", "kategori": "Bal / peynir / şarküteri", "cografi_isaret": true},
      {"ad": "  "}
    ],
    "Kocaeli": [
      {"ad": "İzmit Pişmaniyesi", "kategori": "Tatlı / şekerleme", "cografi_isaret": true}
    ]
  }
}
''';

  test('il bazında ayrıştırır, boş adları atlar', () {
    final repo = HediyelikRepository.instance..applyJsonString(json);
    final duzce = repo.forIller({normalizeForSearch('Düzce')});
    expect(duzce.map((e) => e.ad), ['Tütün Kolonyası', 'Düzce Kestane Balı']);
    expect(duzce.first.cografiIsaret, isFalse);
    expect(duzce.last.cografiIsaret, isTrue);
    expect(duzce.first.il, 'Düzce');
  });

  test('il filtresi yoksa tüm ürünler', () {
    final repo = HediyelikRepository.instance..applyJsonString(json);
    expect(repo.forIller({}).length, 3);
    expect(repo.forIller({normalizeForSearch('Kocaeli')}).single.ad,
        'İzmit Pişmaniyesi');
  });
}
