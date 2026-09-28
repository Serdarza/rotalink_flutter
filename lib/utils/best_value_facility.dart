import '../data/facility_price_repository.dart';
import '../models/facility_tariff.dart';
import '../models/misafirhane.dart';
import 'search_normalize.dart';

/// Hangi fiyat kategorisi üzerinden kıyaslandı.
enum BestValueBasis { sivil, kamu }

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
  final repo = FacilityPriceRepository.instance;
  final sivil = <(Misafirhane, double)>[];
  final kamu = <(Misafirhane, double)>[];
  final iller = <String>{};

  for (final m in facilities) {
    iller.add(normalizeForSearch(m.il));
    final tariff = repo.lookup(m.il, m.isim)?.tarife;
    if (tariff == null || tariff.dogrulama?.isConfirmed != true) continue;
    final s = _singleNightPrice(tariff, _sivilCategory);
    if (s != null) sivil.add((m, s));
    final k = _singleNightPrice(tariff, _kamuCategory);
    if (k != null) kamu.add((m, k));
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

/// Tarifedeki tek kişi / bir gece için en düşük tutar (seçilen kategori).
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
