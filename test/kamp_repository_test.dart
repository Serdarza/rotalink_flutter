import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/data/kamp_repository.dart';
import 'package:rotalink_flutter/utils/search_normalize.dart';

const _json = '''
{
  "atif": "© OpenStreetMap katkıları (ODbL)",
  "items": [
    {
      "id": "osm-node-1", "ad": "Olimpos Kamp", "il": "Antalya", "ilce": "Kumluca",
      "enlem": 36.4, "boylam": 30.5, "kamp_turu": "cadir", "cadir": true, "karavan": false,
      "ucret": "ucretli", "elektrik": true, "tuvalet": true, "dus": null,
      "fiyat": 900, "dogrulama": "acik_veri", "durum": "aktif",
      "kaynak_url": "https://www.openstreetmap.org/node/1", "son_kontrol": "2026-10-08"
    },
    {
      "id": "osm-node-2", "ad": "Kapalı Alan", "il": "Muğla", "enlem": 36.7, "boylam": 27.4,
      "durum": "inceleme", "ucret": "bilinmiyor", "dogrulama": "inceleniyor"
    },
    {
      "id": "x", "ad": "Denizdışı", "il": "Antalya", "enlem": 10, "boylam": 10, "durum": "aktif"
    }
  ]
}
''';

void main() {
  test('aktif kayıt alınır, inceleme ve bozuk koordinat atılır', () {
    final repo = KampRepository.instance..applyJsonString(_json);
    expect(repo.items.value.map((e) => e.ad), ['Olimpos Kamp']);
    final k = repo.items.value.single;
    expect(k.cadir, isTrue);
    expect(k.dus, isNull);
    expect(k.fiyat, isNull);
    expect(repo.forIller({normalizeForSearch('Muğla')}), isEmpty);
  });

  test('filtre çadır ve tuvalet ister, ücreti bilinmeyeni elemez', () {
    final repo = KampRepository.instance..applyJsonString(_json);
    final tum = repo.items.value;
    expect(kampFiltrele(tum, const KampFiltre(cadir: true, tuvalet: true)).single.ad, 'Olimpos Kamp');
    expect(kampFiltrele(tum, const KampFiltre(ucretsiz: true)), isEmpty);
    expect(kampFiltrele(tum, const KampFiltre(sorgu: 'kumluca')).single.ilce, 'Kumluca');
  });
}
