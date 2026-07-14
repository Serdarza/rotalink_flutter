import '../../data/firebase_rota_repository.dart';
import '../../models/gezi_yemek_item.dart';
import 'city_resolver.dart';

/// Yöresel yemek sorguları — yalnızca RTDB `yemekler`.
class KamiFoodService {
  const KamiFoodService();

  List<GeziYemekItem> byCity(RotaDataState data, String city, {int limit = 12}) {
    final list = data.yemek
        .where((y) => KamiCityResolver.sameCity(y.il, city))
        .toList();
    if (list.length <= limit) return list;
    return list.sublist(0, limit);
  }
}
