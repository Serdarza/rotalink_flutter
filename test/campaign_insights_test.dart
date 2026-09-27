import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/campaign.dart';
import 'package:rotalink_flutter/models/campaign_insights.dart';

Campaign _c(Map<String, dynamic> m) => Campaign.fromJson(m, index: 0);

void main() {
  test('tags from the collector decide the audience', () {
    final c = _c({
      'baslik': 'Candent: Öğretmenlere Özel %50\'ye Varan İndirim',
      'aciklama':
          'Diş hekimi muayenesinde %20, implantta %50 indirim. Kampanya 31.12.2026 tarihine kadar geçerlidir.',
      'etiketler': ['Öğretmen'],
      'tarih': '2026-09-27T00:00:00Z',
    });
    final i = CampaignInsights.of(c);
    expect(i.audiences, {CampaignAudience.teacher});
    expect(i.matches(CampaignAudience.health), isFalse);
    expect(i.maxDiscountPercent, 50);
    expect(i.endDate, DateTime(2026, 12, 31));
    expect(i.daysLeft(DateTime(2026, 12, 28, 15)), 3);
  });

  test('legacy records without tags use the title', () {
    final c = _c({
      'baslik': 'Magnet Hastanelerinde MEB Personeline Sağlık İndirimi',
      'aciklama': 'Sağlık hizmetlerinde indirim.',
    });
    expect(CampaignInsights.of(c).audiences, {CampaignAudience.teacher});
  });

  test('general public-employee campaigns appear in every group', () {
    final c = _c({
      'baslik': 'Kamu Personeline Özel Kasko %20 İndirim',
      'aciklama': '',
    });
    final i = CampaignInsights.of(c);
    expect(i.matches(CampaignAudience.police), isTrue);
    expect(i.matches(CampaignAudience.teacher), isTrue);
  });

  test('multiple groups and named-month dates', () {
    final c = _c({
      'baslik': 'Skyes: Polis ve Sağlık Çalışanlarına Özel %10 İndirim',
      'aciklama': 'Geçerlilik: 7 Kasım – 31 Aralık 2026 tarihleri arasında.',
    });
    final i = CampaignInsights.of(c);
    expect(
      i.audiences,
      containsAll([CampaignAudience.police, CampaignAudience.health]),
    );
    expect(i.endDate, DateTime(2026, 12, 31));
  });

  test('url escapes are not discounts and no date means no end', () {
    final c = _c({
      'baslik': 'Öğretmen kampanyası',
      'aciklama': 'https://x.tr/a%3Ab sayfası',
    });
    final i = CampaignInsights.of(c);
    expect(i.maxDiscountPercent, isNull);
    expect(i.endDate, isNull);
    expect(i.daysLeft(DateTime(2026, 1, 1)), isNull);
  });

  test('foldTr', () {
    expect(foldTr('ÖĞRETMENLERE  Özel'), 'ogretmenlere ozel');
    expect(foldTr('İBB Çalışanları'), 'ibb calisanlari');
  });
}
