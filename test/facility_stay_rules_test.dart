import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/constants/facility_stay_rules.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';

Misafirhane _m(String tip, {String isim = 'Tesis'}) => Misafirhane(
  isim: isim,
  il: 'Ankara',
  adres: '',
  telefon: '',
  latitude: 0,
  longitude: 0,
  tip: tip,
);

void main() {
  String authority(String tip) =>
      FacilityStayRules.forFacility(_m(tip)).authority;

  test('tesis tipine göre kurum eşleşir', () {
    expect(authority('Öğretmenevi'), 'Millî Eğitim Bakanlığı');
    expect(authority('Polisevi'), 'Emniyet Genel Müdürlüğü');
    expect(authority('orduevi'), 'Türk Silahlı Kuvvetleri');
    expect(authority('ORDUEVİ'), 'Türk Silahlı Kuvvetleri');
    expect(authority('Jandarma Misafirhanesi'), 'Türk Silahlı Kuvvetleri');
    expect(authority('Hakimevi'), 'Adalet Bakanlığı / Yargı');
    expect(
      authority('Üniversite Uygulama Oteli'),
      'Üniversite / MEB (eğitim amaçlı otel)',
    );
    expect(authority('Üniversite Konukevi'), 'Üniversite');
    expect(authority('Belediye Konukevi'), 'Belediye');
    expect(authority('DSİ Misafirhanesi'), 'DSİ');
    expect(authority('Karayolları Misafirhanesi'), 'Karayolları');
    expect(authority('Kamu Misafirhanesi'), 'Kamu kurumu');
  });

  test('sivil erişim rozetleri', () {
    StayAccess civil(String tip) =>
        FacilityStayRules.forFacility(_m(tip)).civilAccess;
    expect(civil('Öğretmenevi'), StayAccess.allowed);
    expect(civil('Polisevi'), StayAccess.conditional);
    expect(civil('Orduevi'), StayAccess.notAllowed);
    expect(civil('Belediye Konukevi'), StayAccess.conditional);
  });

  test('belediye konuk evinde memur kalır, herkes açık değildir', () {
    final rule = FacilityStayRules.forFacility(
      _m('Belediye Konukevi', isim: 'Eskişehir Büyükşehir Belediyesi Porsuk Konuk Evi'),
    );
    expect(rule.groups.map((g) => g.title), isNot(contains('Herkes')));
    expect(
      rule.groups.singleWhere((g) => g.title == 'Kamu personeli').access,
      StayAccess.allowed,
    );
    expect(
      rule.groups.singleWhere((g) => g.title == 'Sivil vatandaşlar').access,
      StayAccess.conditional,
    );
  });

  test('Artvin Polisevi tarifesinde sivil kalamaz', () {
    final rule = FacilityStayRules.forFacility(
      Misafirhane(
        isim: 'Artvin Polisevi',
        il: 'Artvin',
        adres: '',
        telefon: '',
        latitude: 0,
        longitude: 0,
        tip: 'Polisevi',
      ),
    );
    expect(rule.civilAccess, StayAccess.notAllowed);
    expect(
      rule.groups.singleWhere((g) => g.title == 'Sivil vatandaşlar').access,
      StayAccess.notAllowed,
    );
  });
}
