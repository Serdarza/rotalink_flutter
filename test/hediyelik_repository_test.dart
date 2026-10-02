import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/data/hediyelik_repository.dart';
import 'package:rotalink_flutter/utils/search_normalize.dart';

void main() {
  const json = '''
{
  "guncelleme": "2026-10-01",
  "iller": {
    "DÃ¼zce": [
      {"ad": "TÃ¼tÃ¼n KolonyasÄ±", "aciklama": "Kolonya.", "kategori": "YÃ¶resel Ã¼rÃ¼n", "cografi_isaret": false},
      {"ad": "DÃ¼zce Kestane BalÄ±", "kategori": "Bal / peynir / ÅŸarkÃ¼teri", "cografi_isaret": true},
      {"ad": "  "}
    ],
    "Kocaeli": [
      {"ad": "Ä°zmit PiÅŸmaniyesi", "kategori": "TatlÄ± / ÅŸekerleme", "cografi_isaret": true}
    ]
  }
}
''';

  test('il bazÄ±nda ayrÄ±ÅŸtÄ±rÄ±r, boÅŸ adlarÄ± atlar', () {
    final repo = HediyelikRepository.instance..applyJsonString(json);
    final duzce = repo.forIller({normalizeForSearch('DÃ¼zce')});
    expect(duzce.map((e) => e.ad), ['TÃ¼tÃ¼n KolonyasÄ±', 'DÃ¼zce Kestane BalÄ±']);
    expect(duzce.first.cografiIsaret, isFalse);
    expect(duzce.last.cografiIsaret, isTrue);
    expect(duzce.first.il, 'DÃ¼zce');
  });

  test('il filtresi yoksa tÃ¼m Ã¼rÃ¼nler', () {
    final repo = HediyelikRepository.instance..applyJsonString(json);
    expect(repo.forIller({}).length, 3);
    expect(repo.forIller({normalizeForSearch('Kocaeli')}).single.ad,
        'Ä°zmit PiÅŸmaniyesi');
  });
}
