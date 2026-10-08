import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/data/sosyal_menu_repository.dart';
import 'package:rotalink_flutter/widgets/sosyal_menu_sheet.dart';

Map<String, dynamic> _item({String kaynak = 'https://www.fatsa.bel.tr/a.pdf', String isim = 'Fatsa Belediyesi Sosyal Tesisleri'}) => {
      'il': 'Ordu',
      'isim': isim,
      'kapsam': 'tesis',
      'kaynak': kaynak,
      'kaynak_adi': 'Fatsa Belediyesi',
      'yil': 2026,
      'kontrol': '2026-10-05',
      'kategoriler': [
        {
          'ad': 'Sıcak içecekler',
          'urunler': [
            {'ad': 'Çay', 'fiyat': 15},
            {'ad': '', 'fiyat': 10},
            {'ad': 'Bozuk', 'fiyat': 'x'},
          ],
        },
      ],
    };

void main() {
  test('menü il+isim ile eşlenir, geçersiz ürünler atlanır', () {
    final repo = SosyalMenuRepository.instance;
    repo.applyJsonForTest(jsonEncode({'items': [_item()]}));
    final m = repo.lookup('ORDU', 'fatsa belediyesi sosyal tesisleri');
    expect(m, isNotNull);
    expect(m!.urunSayisi, 1);
    expect(m.tesisMenusu, isTrue);
    expect(sosyalMenuKaynakSatiri(m), 'Kaynak: Fatsa Belediyesi · 05.10.2026');
  });

  test('resmî olmayan kaynaklı kayıt reddedilir', () {
    final repo = SosyalMenuRepository.instance;
    repo.applyJsonForTest(jsonEncode({
      'items': [
        _item(kaynak: 'https://menufiyatlar.com/fatsa', isim: 'A'),
        _item(kaynak: 'javascript:alert(1)', isim: 'B'),
        _item(kaynak: 'https://fatsa.bel.tr.evil.com/x', isim: 'C'),
      ],
    }));
    expect(repo.count, 0);
  });

  test('birim, önceki fiyat ve kaynak bulunamadı uyarısı', () {
    final raw = _item()
      ..['durum'] = 'kaynak_bulunamadi'
      ..['dogrulama'] = '2026-06-01'
      ..['kategoriler'] = [
        {
          'ad': 'Ana yemekler',
          'urunler': [
            {'ad': 'Köfte', 'fiyat': 250, 'birim': 'porsiyon', 'onceki': {'fiyat': 220, 'tarih': '2026-09-05'}},
            {'ad': 'Ayran', 'fiyat': 40},
          ],
        },
      ];
    final m = SosyalMenu.tryParse(raw)!;
    final kofte = m.kategoriler.first.urunler.first;
    expect(kofte.birim, 'porsiyon');
    expect(kofte.oncekiFiyat, 220);
    expect(m.kategoriler.first.urunler.last.oncekiFiyat, isNull);
    expect(m.kaynakBulunamadi, isTrue);
    expect(sosyalMenuUyari(m), contains('01.06.2026'));
    expect(sosyalMenuUyari(SosyalMenu.tryParse(_item())!), isNull);
  });

  test('TL biçimi', () {
    expect(formatTl(15), '15 ₺');
    expect(formatTl(1250), '1.250 ₺');
    expect(formatTl(12.5), '12,50 ₺');
  });
}
