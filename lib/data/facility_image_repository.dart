import '../models/misafirhane.dart';

/// Konaklama tesis fotoğrafları kapatıldı (Bunny / bakım maliyeti).
///
/// Eski `tesisler_gorseller.json` eşlemesi kullanılmaz; UI resim göstermez.
class FacilityImageRepository {
  FacilityImageRepository._();

  static final FacilityImageRepository instance = FacilityImageRepository._();

  int get count => 0;

  Future<void> ensureLocalDataReady() async {}

  List<String> lookup(String il, String isim) => const [];

  Misafirhane resolveFacility(Misafirhane m) => m;
}
