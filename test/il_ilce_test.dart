import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';
import 'package:rotalink_flutter/providers/facility_filter_provider.dart';
import 'package:rotalink_flutter/utils/il_ilce.dart';
import 'package:rotalink_flutter/utils/main_map_search.dart';

Misafirhane _m(String il, String ilce, String isim, [String tip = 'Öğretmenevi']) =>
    Misafirhane(
      isim: isim,
      il: il,
      ilce: ilce,
      adres: '',
      telefon: '',
      latitude: 0,
      longitude: 0,
      tip: tip,
    );

String _ilce(Misafirhane m) => m.ilce;

void main() {
  final kaynak = [
    _m('İstanbul', 'Sarıyer', 'Baltalimanı Polisevi', 'Polisevi'),
    _m('İstanbul', 'Sarıyer', 'Tarabya Sosyal Tesisleri'),
    _m('İstanbul', 'Fatih', 'Diyanet Evi Sultanahmet'),
    _m('İstanbul', '', 'Doğrulanamayan Tesis'),
    _m('Ankara', 'Çankaya', 'Ankara Hakimevi'),
    _m('Ankara', 'Yenimahalle', 'Yenimahalle Öğretmenevi'),
    _m('İzmir', 'Konak', 'İzmir Konak Merkez Öğretmenevi'),
    _m('Van', 'Edremit', 'Van Karayolları Misafirhanesi'),
    _m('Van', 'Tuşba', 'Van Öğretmenevi'),
    _m('Balıkesir', 'Edremit', 'Edremit Altınoluk Öğretmenevi'),
    _m('Çanakkale', 'Merkez', 'Çanakkale Öğretmenevi'),
  ];
  final iller = kaynak.map((m) => m.il).toSet();

  List<Misafirhane> ilTesisleri(String il) =>
      kaynak.where((m) => m.il == il).toList();

  List<Misafirhane> secim(String il, String? ilce) => filterFacilitiesByIlce(
        ilTesisleri(il),
        ilce == null ? null : IlceSelection(il: il, ilce: ilce),
        ilceOf: _ilce,
      );

  group('IlIlce.key / standartlaştırma', () {
    test('Türkçe karakter ve büyük/küçük harf duyarsız', () {
      for (final s in ['istanbul', 'İSTANBUL', 'İstanbul', 'ISTANBUL']) {
        expect(IlIlce.key(s), 'istanbul', reason: s);
      }
      for (final s in ['sariyer', 'SARIYER', 'Sarıyer', 'SarıYER']) {
        expect(IlIlce.key(s), 'sariyer', reason: s);
      }
    });

    test('ilçe yazımları resmi ada çevrilir', () {
      expect(IlIlce.canonicalIlce('İstanbul', 'SARIYER'), 'Sarıyer');
      expect(IlIlce.canonicalIlce('Çanakkale', 'Çanakkale Merkez'), 'Merkez');
      expect(IlIlce.canonicalIlce('Çanakkale', 'ayvacik'), 'Ayvacık');
      expect(IlIlce.canonicalIlce('Niğde', 'Ulukışla'), 'Ulukışla');
      expect(IlIlce.canonicalIlce('Erzincan', 'İliç'), 'İliç');
      expect(IlIlce.canonicalIlce('Adıyaman', 'Kâhta'), 'Kahta');
    });

    test('referansta olmayan ilçe boş döner (tahmin yok)', () {
      expect(IlIlce.canonicalIlce('İstanbul', 'Merkez'), '');
      expect(IlIlce.canonicalIlce('İstanbul', 'Çankaya'), '');
      expect(IlIlce.canonicalIlce('Ankara', ''), '');
    });

    test('ilçe listesi ile özgü ve alfabetik', () {
      final ist = IlIlce.ilceleri('istanbul');
      expect(ist, contains('Sarıyer'));
      expect(ist, isNot(contains('Çankaya')));
      expect(ist, hasLength(39));
      expect(IlIlce.ilceleri('Van'), contains('Edremit'));
      expect(IlIlce.ilceleri('Balıkesir'), contains('Edremit'));
    });

    test('kart etiketi İl / İlçe', () {
      expect(IlIlce.label('İstanbul', 'Sarıyer'), 'İstanbul / Sarıyer');
      expect(IlIlce.label('İstanbul', ''), 'İstanbul');
    });
  });

  group('arama sorgusu → il / ilçe', () {
    test('il adı', () {
      expect(IlIlce.matchQuery('istanbul', iller), [const IlIlceMatch('İstanbul')]);
      expect(IlIlce.matchQuery('İSTANBUL', iller), [const IlIlceMatch('İstanbul')]);
    });

    test('ilçe adı ve il + ilçe', () {
      const s = IlIlceMatch('İstanbul', 'Sarıyer');
      for (final q in ['sariyer', 'SARIYER', 'Sarıyer', 'İstanbul Sarıyer', 'İstanbul / Sarıyer', 'sarıyer istanbul']) {
        expect(IlIlce.matchQuery(q, iller), [s], reason: q);
      }
      expect(IlIlce.matchQuery('Ankara Çankaya', iller), [const IlIlceMatch('Ankara', 'Çankaya')]);
      expect(IlIlce.matchQuery('izmir konak', iller), [const IlIlceMatch('İzmir', 'Konak')]);
    });

    test('birden çok ilde olan ilçe seçim için hepsini döner', () {
      expect(
        IlIlce.matchQuery('edremit', iller).toSet(),
        {const IlIlceMatch('Van', 'Edremit'), const IlIlceMatch('Balıkesir', 'Edremit')},
      );
      expect(IlIlce.matchQuery('Van Edremit', iller), [const IlIlceMatch('Van', 'Edremit')]);
    });

    test('tek başına "merkez" ilçe sayılmaz; tesis adı eşleşmez', () {
      expect(IlIlce.matchQuery('merkez', iller), isEmpty);
      expect(IlIlce.matchQuery('Baltalimanı', iller), isEmpty);
    });

    test('öneriler: önce il, sonra İl / İlçe', () {
      final sorted = iller.toList()..sort();
      expect(IlIlce.autocomplete(sorted, 'ist').first, 'İstanbul');
      expect(IlIlce.autocomplete(sorted, 'sarı'), contains('İstanbul / Sarıyer'));
      expect(IlIlce.autocomplete(sorted, 'istanbul sa'), contains('İstanbul / Sarıyer'));
      expect(IlIlce.autocomplete(sorted, 'edrem'), containsAll(['Balıkesir / Edremit', 'Van / Edremit']));
    });
  });

  group('il → ilçe filtresi', () {
    test('İstanbul → Tüm ilçeler (doğrulanamayan dahil)', () {
      expect(secim('İstanbul', null), hasLength(4));
    });

    test('İstanbul → Sarıyer', () {
      final r = secim('İstanbul', 'Sarıyer');
      expect(r.map((m) => m.isim), ['Baltalimanı Polisevi', 'Tarabya Sosyal Tesisleri']);
    });

    test('İstanbul → Fatih', () {
      expect(secim('İstanbul', 'Fatih').single.isim, 'Diyanet Evi Sultanahmet');
    });

    test('Ankara → Çankaya', () {
      expect(secim('Ankara', 'Çankaya').single.isim, 'Ankara Hakimevi');
    });

    test('İzmir → Konak', () {
      expect(secim('İzmir', 'Konak'), hasLength(1));
    });

    test('Van → Edremit, Balıkesir Edremit karışmaz', () {
      expect(secim('Van', 'Edremit').single.isim, 'Van Karayolları Misafirhanesi');
    });

    test('tesisi olmayan ilçe boş liste', () {
      expect(secim('İstanbul', 'Adalar'), isEmpty);
    });

    test('il değişince eski ilçe seçimi yeni ili süzmez', () {
      final r = filterFacilitiesByIlce(
        ilTesisleri('Ankara'),
        const IlceSelection(il: 'İstanbul', ilce: 'Sarıyer'),
        ilceOf: _ilce,
      );
      expect(r, hasLength(2));
    });

    test('tür + ilçe birlikte', () {
      final typed = filterFacilitiesByType(ilTesisleri('İstanbul'), 'Polisevi');
      final r = filterFacilitiesByIlce(
        typed,
        const IlceSelection(il: 'İstanbul', ilce: 'Sarıyer'),
        ilceOf: _ilce,
      );
      expect(r.single.isim, 'Baltalimanı Polisevi');
    });

    test('özet: ilin bütün ilçeleri ve sayıları', () {
      final src = ilTesisleri('İstanbul');
      final s = summarizeFacilityLocations(src, src, ilceOf: _ilce);
      expect(s.il, 'İstanbul');
      expect(s.total, 4);
      expect(s.ilceCounts['Sarıyer'], 2);
      expect(s.ilceCounts['Fatih'], 1);
      expect(s.ilceCounts['Adalar'], 0);
      expect(s.ilceCounts, hasLength(39));
    });

    test('özet: birden çok il → ilçe seçimi yok', () {
      final s = summarizeFacilityLocations(kaynak, kaynak, ilceOf: _ilce);
      expect(s.il, isNull);
      expect(s.total, kaynak.length);
    });
  });

  test('tesis adıyla arama: ilçe karta yazılır', () {
    final r = MainMapSearch.perform(
      query: 'Baltalimanı',
      kaynak: kaynak,
      mapMisafirhaneler: const [],
      ilceOf: _ilce,
    );
    expect(r, isNotEmpty);
    final m = r.firstWhere((m) => m.isim == 'Baltalimanı Polisevi');
    expect(IlIlce.label(m.il, m.ilce), 'İstanbul / Sarıyer');
  });

  test('ilçe adıyla bulanık arama ilçedeki tesisleri bulur', () {
    final r = MainMapSearch.narrowFuzzyMatches(query: 'sarıyer', kaynak: kaynak, ilceOf: _ilce);
    expect(r.map((m) => m.isim).toSet(), {'Baltalimanı Polisevi', 'Tarabya Sosyal Tesisleri'});
  });
}
