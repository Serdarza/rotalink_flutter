import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/facility_tariff.dart';
import 'package:rotalink_flutter/utils/stay_cost_calculator.dart';

void main() {
  final tariff = FacilityTariff.tryParse({
    'birim': 'gecelik',
    'kategoriler': [
      {'id': 'kamu', 'ad': 'Kamu'},
      {'id': 'sivil', 'ad': 'Sivil'},
    ],
    'tablolar': [
      {
        'satirlar': [
          {'ad': 'Tek Kişilik Oda', 'kisi': 1, 'birim': 'kişi başı', 'fiyatlar': {'kamu': 1000, 'sivil': 1500}},
          {'ad': 'Üç Kişilik Oda', 'kisi': 3, 'fiyatlar': {'kamu': 2500, 'sivil': 'Arayınız'}},
          {'ad': 'Ek Yatak', 'fiyatlar': {'kamu': 400, 'sivil': 600}},
          {'ad': 'Sabah Kahvaltısı', 'fiyatlar': {'kamu': 200, 'sivil': 300}},
          {'ad': 'Single Room aylık', 'birim': 'aylık', 'fiyatlar': {'sivil': 20000}},
        ],
      },
    ],
    'indirimler': ['0-3 yaş ücretsiz', 'Şehit yakınlarına indirim'],
    'ek_ucretler': ['Her konaklanan gece için %2 oranında konaklama vergisi alınır.'],
  })!;

  test('ek yatak, kahvaltı ve aylık satırlar konaklama tipi sayılmaz', () {
    final kamu = StayCostCalculator.roomOptions(tariff, 'kamu');
    expect(kamu.map((o) => o.row.ad), ['Tek Kişilik Oda', 'Üç Kişilik Oda']);
    final sivil = StayCostCalculator.roomOptions(tariff, 'sivil');
    expect(sivil.map((o) => o.row.ad), ['Tek Kişilik Oda']);
    expect(StayCostCalculator.extraBedAmount(tariff, 'kamu'), 400);
    expect(StayCostCalculator.breakfastAmount(tariff, 'sivil'), 300);
  });

  test('birim: satır birimi açık, oda adı tahmini', () {
    final opts = StayCostCalculator.roomOptions(tariff, 'kamu');
    final single = StayCostCalculator.inferBasis(tariff, opts[0]);
    expect(single.basis, StayPriceBasis.perPerson);
    expect(single.explicit, isTrue);
    final triple = StayCostCalculator.inferBasis(tariff, opts[1]);
    expect(triple.basis, StayPriceBasis.perRoom);
    expect(triple.explicit, isFalse);
    expect(StayCostCalculator.suggestedRooms(opts[1], 4), 2);
  });

  test('notlar ve vergi oranı tarifeden okunur', () {
    expect(StayCostCalculator.childNotes(tariff), ['0-3 yaş ücretsiz']);
    expect(StayCostCalculator.lodgingTaxRate(tariff), closeTo(0.02, 1e-9));
    expect(StayCostCalculator.breakfastIncluded(tariff, null), isNull);
  });

  test('kişi başı toplam: yarım ücretli çocuk, ek yatak, kahvaltı, vergi', () {
    final r = StayCostCalculator.compute(const StayCostInput(
      nightlyAmount: 1000,
      basis: StayPriceBasis.perPerson,
      nights: 3,
      adults: 2,
      children: 1,
      childFactor: 0.5,
      extraBeds: 1,
      extraBedAmount: 400,
      breakfastPerPerson: 200,
      taxRate: 0.02,
    ));
    expect(r.lodging, 7500);
    expect(r.extraBeds, 1200);
    expect(r.breakfast, 1800);
    expect(r.tax, closeTo(174, 1e-9));
    expect(r.total, closeTo(10674, 1e-9));
  });

  test('oda başı toplam kişi sayısından bağımsız', () {
    final r = StayCostCalculator.compute(const StayCostInput(
      nightlyAmount: 2500,
      basis: StayPriceBasis.perRoom,
      nights: 2,
      adults: 3,
      children: 2,
      rooms: 2,
    ));
    expect(r.total, 10000);
  });

  test('adında "yatak" geçen aile odası oda başı sayılır', () {
    final t = FacilityTariff.tryParse({
      'satirlar': [
        {'ad': '1 Duble + 2 Tek Yataklı Oda (3 Kişi)', 'fiyatlar': {'sivil': 6200}},
        {'ad': 'Kişi Başı Yatak Ücreti', 'fiyatlar': {'sivil': 900}},
      ],
    })!;
    final opts = StayCostCalculator.roomOptions(t, 'sivil');
    expect(StayCostCalculator.inferBasis(t, opts[0]).basis, StayPriceBasis.perRoom);
    final bed = StayCostCalculator.inferBasis(t, opts[1]);
    expect(bed.basis, StayPriceBasis.perPerson);
    expect(bed.explicit, isTrue);
  });

  test('kahvaltı dahil bilgisi', () {
    final t = FacilityTariff.tryParse({
      'satirlar': [
        {'ad': 'Oda', 'fiyatlar': {'sivil': 1000}},
      ],
      'dahil': ['Kahvaltı', 'KDV', 'Konaklama vergisi'],
    })!;
    expect(StayCostCalculator.breakfastIncluded(t, null), isTrue);
    expect(StayCostCalculator.lodgingTaxRate(t), isNull);
  });
}
