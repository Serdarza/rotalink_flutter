import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/campaign.dart';
import 'package:rotalink_flutter/models/campaign_insights.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';
import 'package:rotalink_flutter/services/pro_update_notifier.dart';

Misafirhane _m(String isim) => Misafirhane(
      isim: isim,
      il: 'İstanbul',
      adres: '',
      telefon: '',
      latitude: 0,
      longitude: 0,
      tip: '',
    );

Campaign _c(String kurum, String baslik, List<String> etiketler) =>
    Campaign.fromJson({'kurum': kurum, 'baslik': baslik, 'etiketler': etiketler}, index: 0);

void main() {
  test('favorite price changes: only known favorites with a new price', () {
    final a = _m('A'), b = _m('B'), c = _m('C'), d = _m('D');
    final previous = {
      a.stableFacilityId: (sivil: 1000.0, kamu: 800.0),
      b.stableFacilityId: (sivil: 1000.0, kamu: null),
      d.stableFacilityId: (sivil: 500.0, kamu: null),
    };
    final next = {
      a.stableFacilityId: (sivil: 1200.0, kamu: 800.0),
      b.stableFacilityId: (sivil: 1000.0, kamu: null),
      c.stableFacilityId: (sivil: 900.0, kamu: null),
      d.stableFacilityId: (sivil: null, kamu: null),
    };
    final changed = ProUpdateNotifier.changedFavoritePrices(previous, next, [a, b, c, d]);
    expect(changed.map((e) => e.$1.isim), ['A']);
  });

  test('new campaigns: unseen and matching the chosen group only', () {
    final old = _c('OYAK', 'TSK Personeline İndirim', ['TSK']);
    final freshTsk = _c('Enterprise', 'TSK Mensuplarına %30', ['TSK']);
    final freshTeacher = _c('Kiğılı', 'Öğretmenlere Özel', ['Öğretmen']);
    final union = _c('Türkiye Kamu-Sen', 'Kamu-Sen Üyelerine Özel', ['Kamu Personeli']);
    final seen = {ProUpdateNotifier.campaignKey(old)};
    final fresh = ProUpdateNotifier.newCampaignsFor(
      CampaignAudience.military,
      seen,
      [old, freshTsk, freshTeacher, union],
    );
    expect(fresh, [freshTsk]);
  });
}
