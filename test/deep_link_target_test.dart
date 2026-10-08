import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/deeplink/deep_link_target.dart';

void main() {
  group('rotalinkSlug (web slugifyCity ile aynı)', () {
    test('Türkçe karakterler', () {
      expect(rotalinkSlug('İstanbul'), 'istanbul');
      expect(rotalinkSlug('Şanlıurfa'), 'sanliurfa');
      expect(rotalinkSlug('Çanakkale'), 'canakkale');
      expect(rotalinkSlug('Muğla'), 'mugla');
      expect(rotalinkSlug('IĞDIR'), 'igdir');
      expect(rotalinkSlug('Düzce'), 'duzce');
    });

    test('tesis adları', () {
      expect(rotalinkSlug('DSİ 14. Bölge Misafirhanesi'), 'dsi-14-bolge-misafirhanesi');
      expect(rotalinkSlug('Akçakoca Öğretmen Evi'), 'akcakoca-ogretmen-evi');
      expect(rotalinkSlug('  Kayseri  Öğretmenevi (ASO) '), 'kayseri-ogretmenevi-aso');
    });

    test('facilityWebUrl', () {
      expect(
        facilityWebUrl(il: 'İstanbul', isim: 'DSİ 14. Bölge Misafirhanesi'),
        'https://rotalink.tr/tesis/istanbul/dsi-14-bolge-misafirhanesi/',
      );
    });
  });

  group('DeepLinkTarget.fromUri', () {
    DeepLinkTarget? parse(String s) => DeepLinkTarget.fromUri(Uri.parse(s));

    test('şehir sayfası (App Link)', () {
      final t = parse('https://rotalink.tr/sehir/kayseri/')!;
      expect(t.kind, DeepLinkKind.city);
      expect(t.citySlug, 'kayseri');
    });

    test('tesis sayfası', () {
      final t = parse('https://www.rotalink.tr/tesis/istanbul/dsi-14-bolge-misafirhanesi')!;
      expect(t.kind, DeepLinkKind.facility);
      expect(t.citySlug, 'istanbul');
      expect(t.facilitySlug, 'dsi-14-bolge-misafirhanesi');
      expect(t.path, '/tesis/istanbul/dsi-14-bolge-misafirhanesi');
    });

    test('kısa şehir linki ve web sayfaları', () {
      expect(parse('https://rotalink.tr/kayseri')!.kind, DeepLinkKind.city);
      expect(parse('https://rotalink.tr/blog')!.kind, DeepLinkKind.home);
      expect(parse('https://rotalink.tr/gizlilik-politikasi/')!.kind, DeepLinkKind.home);
      expect(parse('https://rotalink.tr/')!.kind, DeepLinkKind.home);
      expect(parse('https://rotalink.tr/resmi-tatiller/')!.kind, DeepLinkKind.holidays);
    });

    test('rotalink:// şeması (web → uygulama)', () {
      final t = parse('rotalink://open/tesis/kayseri/kayseri-ogretmenevi/?q=1')!;
      expect(t.kind, DeepLinkKind.facility);
      expect(t.facilitySlug, 'kayseri-ogretmenevi');
      expect(parse('rotalink://open/')!.kind, DeepLinkKind.home);
      expect(parse('rotalink://sehir/mugla')!.citySlug, 'mugla');
    });

    test('Türkçe karakterli / kodlanmış yol normalize edilir', () {
      final t = parse('https://rotalink.tr/sehir/%C4%B0stanbul')!;
      expect(t.citySlug, 'istanbul');
    });

    test('başka alan adı yok sayılır', () {
      expect(parse('https://example.com/sehir/kayseri'), isNull);
      expect(parse('mailto:info@rotalink.tr'), isNull);
    });
  });

  test('fromPath (install referrer rl_path)', () {
    final t = DeepLinkTarget.fromPath('/sehir/duzce/?sekme=tesis');
    expect(t.kind, DeepLinkKind.city);
    expect(t.citySlug, 'duzce');
  });
}
