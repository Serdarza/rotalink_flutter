import '../models/facility_price_entry.dart';

/// Oturum içi fiyat görüntüleme.
///
/// 1 ödüllü reklam → yalnızca izlenen tesis açılır.
/// Pro veya grace (reklam yok / offline) da tek tesis açar.
/// Bir tesis bir kez açılınca oturum boyunca açık kalır.
abstract final class PriceUnlockStore {
  static final Set<String> _unlocked = {};

  static String keyFor(String il, String isim) =>
      FacilityPriceEntry.matchKey(il, isim);

  static bool isUnlocked(String il, String isim) =>
      _unlocked.contains(keyFor(il, isim));

  /// Ödüllü reklam (veya bypass) sonrası bu tesisi aç.
  static void unlockFacility(String il, String isim) {
    _unlocked.add(keyFor(il, isim));
  }

  /// Reklam yüklenemedi / internet yok — yalnızca bu tesisi ücretsiz aç.
  static void graceUnlockFacility(String il, String isim) {
    unlockFacility(il, isim);
  }

  static void clearSession() {
    _unlocked.clear();
  }
}
