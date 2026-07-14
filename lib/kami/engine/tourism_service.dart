import '../../data/firebase_rota_repository.dart';
import '../../models/gezi_yemek_item.dart';
import 'city_resolver.dart';

/// Gezilecek yerler — yalnızca RTDB `geziler`.
class KamiTourismService {
  const KamiTourismService();

  List<GeziYemekItem> byCity(RotaDataState data, String city, {int limit = 12}) {
    final list = data.gezi
        .where((g) => KamiCityResolver.sameCity(g.il, city))
        .toList();
    if (list.length <= limit) return list;
    return list.sublist(0, limit);
  }
}
