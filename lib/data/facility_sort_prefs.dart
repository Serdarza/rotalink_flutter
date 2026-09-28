import 'package:shared_preferences/shared_preferences.dart';

import '../utils/best_value_facility.dart';

/// Pro kullanıcının arama listesindeki fiyat sıralaması tercihi.
abstract final class FacilitySortPrefs {
  static const _kByPrice = 'rotalink_facility_sort_by_price';
  static const _kBasis = 'rotalink_facility_sort_price_basis';

  static Future<({bool byPrice, BestValueBasis basis})> load() async {
    final p = await SharedPreferences.getInstance();
    final basis = BestValueBasis.values.asNameMap()[p.getString(_kBasis)] ??
        BestValueBasis.sivil;
    return (byPrice: p.getBool(_kByPrice) ?? false, basis: basis);
  }

  static Future<void> save({required bool byPrice, required BestValueBasis basis}) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kByPrice, byPrice);
    await p.setString(_kBasis, basis.name);
  }
}
