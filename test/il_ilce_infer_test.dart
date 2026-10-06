import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/utils/il_ilce.dart';

void main() {
  test('ilçe alanı resmi ilçeyse kullanılır', () {
    expect(IlIlce.inferIlce('İstanbul', ilce: 'kadıköy'), 'Kadıköy');
  });

  test('il adı ilçe alanına yazılmışsa adrese bakılır', () {
    expect(
      IlIlce.inferIlce(
        'Adana',
        ilce: 'Adana',
        adres: 'Turgut Özal Blv. Çukurova',
      ),
      'Çukurova',
    );
    expect(IlIlce.inferIlce('Adana', ilce: 'Adana'), '');
  });

  test('adresteki İlçe/İl kalıbı', () {
    expect(
      IlIlce.inferIlce('Muğla', adres: 'Kumbahçe Mah., 48400 Bodrum/Muğla'),
      'Bodrum',
    );
  });

  test('adreste tam kelime olarak geçen ilçe; kelime içi eşleşmez', () {
    expect(
      IlIlce.inferIlce('Antalya', adres: 'Kaleiçi, Muratpaşa'),
      'Muratpaşa',
    );
    expect(IlIlce.inferIlce('Antalya', adres: 'Sahil yolu üzeri'), '');
  });

  test('merkez kelimesi yalnız Merkez ilçesi olan ilde', () {
    expect(IlIlce.inferIlce('Düzce', adres: 'Düzce merkez'), 'Merkez');
    expect(IlIlce.inferIlce('Adana', adres: 'Adana merkez'), '');
  });

  test('bilinmeyen il boş döner', () {
    expect(IlIlce.inferIlce('Atlantis', ilce: 'Merkez'), '');
  });
}
