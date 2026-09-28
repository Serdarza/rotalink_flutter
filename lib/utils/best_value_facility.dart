import '../data/facility_price_repository.dart';
import '../models/facility_tariff.dart';
import '../models/misafirhane.dart';
import 'search_normalize.dart';

/// Hangi fiyat kategorisi üzerinden kıyaslandı.
enum BestValueBasis { sivil, kamu }

/// Tesisin tek kişi / bir gece fiyatı (seçilen kategori).
class FacilityNightPrice {
  const FacilityNightPrice({required this.amount, required this.dogrulama});

  final double amount;
  final TariffVerification? dogrulama;

  bool get confirmed => dogrulama?.isConfirmed == true;
}

/// Tarifesi olan tesis için tek kişi / bir gecelik en düşük tutar.
/// Ek yatak, çocuk, öğrenci, aylık, grup gibi satırlar ve oda başı
/// (tek kişilik olmayan) fiyatlar kıyasa girmez.
FacilityNightPrice? singleNightPriceFor(Misafirhane m, BestValueBasis basis) {
  final tariff = FacilityPriceRepository.instance.lookup(m.il, m.isim)?.tarife;
  if (tariff == null) return null;
  final amount = _singleNightPrice(
    tariff,
    basis == BestValueBasis.sivil ? _sivilCategory : _kamuCategory,
  );
  if (amount == null) return null;
  return FacilityNightPrice(amount: amount, dogrulama: tariff.dogrulama);
}

/// Fiyat sıralaması: fiyatı olanlar ucuzdan pahalıya, eşitlikte ve fiyatsızlarda
/// gelen (yakınlık) sırası korunur.
({List<(Misafirhane, FacilityNightPrice)> priced, List<Misafirhane> unpriced})
    sortFacilitiesByPrice(List<Misafirhane> facilities, BestValueBasis basis) {
  final s = splitFacilitiesByPrice(facilities, basis, sortByPrice: true);
  return (priced: s.priced, unpriced: s.unpriced);
}

/// Fiyatı olan / olmayan tesisleri ayırır; [maxAmount] verilirse bu tutarı aşan
/// fiyatlı tesisler [overBudget] sayısına düşer. [sortByPrice] kapalıysa gelen
/// sıra korunur.
({
  List<(Misafirhane, FacilityNightPrice)> priced,
  List<Misafirhane> unpriced,
  int overBudget,
}) splitFacilitiesByPrice(
  List<Misafirhane> facilities,
  BestValueBasis basis, {
  bool sortByPrice = false,
  double? maxAmount,
}) {
  final priced = <(int, Misafirhane, FacilityNightPrice)>[];
  final unpriced = <Misafirhane>[];
  var overBudget = 0;
  for (final (i, m) in facilities.indexed) {
    final p = singleNightPriceFor(m, basis);
    if (p == null) {
      unpriced.add(m);
    } else if (maxAmount != null && p.amount > maxAmount) {
      overBudget++;
    } else {
      priced.add((i, m, p));
    }
  }
  if (sortByPrice) {
    priced.sort((a, b) {
      final c = a.$3.amount.compareTo(b.$3.amount);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  }
  return (
    priced: [for (final e in priced) (e.$2, e.$3)],
    unpriced: unpriced,
    overBudget: overBudget,
  );
}

/// Seçilen kategoride tek kişi / gece fiyatlarının en düşük ve en yüksek değeri.
({double min, double max})? nightPriceRange(
  List<Misafirhane> facilities,
  BestValueBasis basis,
) {
  double? lo;
  double? hi;
  for (final m in facilities) {
    final v = singleNightPriceFor(m, basis)?.amount;
    if (v == null) continue;
    if (lo == null || v < lo) lo = v;
    if (hi == null || v > hi) hi = v;
  }
  if (lo == null || hi == null) return null;
  return (min: lo, max: hi);
}

/// Sivil veya kamu personeli için tek kişi / gece fiyatı olan tesis sayısı.
int countFacilitiesWithNightPrice(List<Misafirhane> facilities) => facilities
    .where((m) =>
        singleNightPriceFor(m, BestValueBasis.sivil) != null ||
        singleNightPriceFor(m, BestValueBasis.kamu) != null)
    .length;

/// Arama sonuçlarında "en uygun konaklama" seçimi.
class BestValuePick {
  const BestValuePick({
    required this.facility,
    required this.price,
    required this.basis,
    required this.comparedCount,
    required this.il,
  });

  final Misafirhane facility;

  /// Tek kişi, bir gece (TL).
  final double price;
  final BestValueBasis basis;

  /// Aynı ölçüte göre fiyatı kıyaslanabilen tesis sayısı.
  final int comparedCount;

  /// Sonuçlar tek ilde ise il adı; birden fazla il varsa null.
  final String? il;

  bool get isComparison => comparedCount > 1;
}

/// Yalnızca resmî kaynaktan / tesisçe doğrulanmış tarifeler arasında, tek kişi
/// bir gecelik en düşük fiyatlı tesisi seçer. Sivil fiyatı olan tesis varsa
/// yalnızca sivil fiyatlar, yoksa kamu personeli fiyatları kıyaslanır; farklı
/// kategoriler veya oda/kişi birimleri birbirine karıştırılmaz.
BestValuePick? pickBestValueFacility(List<Misafirhane> facilities) {
  final sivil = <(Misafirhane, double)>[];
  final kamu = <(Misafirhane, double)>[];
  final iller = <String>{};

  for (final m in facilities) {
    iller.add(normalizeForSearch(m.il));
    final s = singleNightPriceFor(m, BestValueBasis.sivil);
    if (s != null && s.confirmed) sivil.add((m, s.amount));
    final k = singleNightPriceFor(m, BestValueBasis.kamu);
    if (k != null && k.confirmed) kamu.add((m, k.amount));
  }

  final basis = sivil.isNotEmpty ? BestValueBasis.sivil : BestValueBasis.kamu;
  final pool = sivil.isNotEmpty ? sivil : kamu;
  if (pool.isEmpty) return null;

  var best = pool.first;
  for (final e in pool.skip(1)) {
    if (e.$2 < best.$2) best = e;
  }
  return BestValuePick(
    facility: best.$1,
    price: best.$2,
    basis: basis,
    comparedCount: pool.length,
    il: iller.length == 1 ? best.$1.il : null,
  );
}

final _excludedRow = RegExp(
  r'ek yatak|ilave|cocuk|bebek|ogrenci|kahvalti|yemek|otopark|havuz|'
  r'aylik|haftalik|saatlik|grup|toplanti|salon',
);
final _perPersonUnit = RegExp(r'kisi ?bas|kisi/gece|kisi ?gecelik|kisi ?icin');
final _singleRoom = RegExp(r'tek kisilik|1 kisilik|tek yatak|single');

bool _sivilCategory(TariffCategory c) =>
    _norm('${c.id} ${c.ad}').contains('sivil');

bool _kamuCategory(TariffCategory c) =>
    _norm('${c.id} ${c.ad}').contains('kamu');

String _norm(String s) =>
    s.trim().split(RegExp(r'\s+')).map(normalizeForSearch).join(' ');

double? _singleNightPrice(
  FacilityTariff tariff,
  bool Function(TariffCategory) isCategory,
) {
  double? best;
  for (final table in tariff.tablolar) {
    final ids = table.kategoriler.where(isCategory).map((c) => c.id).toSet();
    if (ids.isEmpty) continue;
    for (final row in table.satirlar) {
      final name = _norm(row.ad);
      if (_excludedRow.hasMatch(name)) continue;
      final unit = _norm(row.birim ?? table.birim ?? tariff.birim ?? '');
      final perPerson = _perPersonUnit.hasMatch(unit) || _perPersonUnit.hasMatch(name);
      final single = row.kisi == 1 || _singleRoom.hasMatch(name);
      if (!perPerson && !single) continue;
      for (final id in ids) {
        final v = row.fiyatlar[id]?.amount;
        if (v == null || v <= 0) continue;
        if (best == null || v < best) best = v;
      }
    }
  }
  return best;
}
