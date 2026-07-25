import '../models/facility_price_entry.dart';

/// Oturum içi fiyat görüntüleme hakları.
///
/// 1 ödüllü reklam → [creditsPerReward] tesis hakkı.
/// Bir tesis bir kez açılınca oturum boyunca açık kalır (tekrar hak harcanmaz).
abstract final class PriceUnlockStore {
  static const int creditsPerReward = 5;

  static int _credits = 0;
  static final Set<String> _unlocked = {};

  static int get credits => _credits;

  static String keyFor(String il, String isim) =>
      FacilityPriceEntry.matchKey(il, isim);

  static bool isUnlocked(String il, String isim) =>
      _unlocked.contains(keyFor(il, isim));

  /// Hak varsa 1 düşürüp tesisi açar. Zaten açıksa dokunmaz.
  static bool unlockWithCredit(String il, String isim) {
    final key = keyFor(il, isim);
    if (_unlocked.contains(key)) return true;
    if (_credits <= 0) return false;
    _credits -= 1;
    _unlocked.add(key);
    return true;
  }

  /// Ödüllü reklam sonrası +5 hak.
  static void grantRewardCredits() {
    _credits += creditsPerReward;
  }

  /// Reklam sonrası hak ekle ve bu tesisi aç (1 hak harcar).
  static bool grantRewardAndUnlock(String il, String isim) {
    grantRewardCredits();
    return unlockWithCredit(il, isim);
  }

  /// Reklam yüklenemedi / internet yok — yalnızca bu tesisi ücretsiz aç.
  /// Ek hak vermez (ad-bypass abuse sınırlı kalsın).
  static void graceUnlockFacility(String il, String isim) {
    _unlocked.add(keyFor(il, isim));
  }

  static void clearSession() {
    _credits = 0;
    _unlocked.clear();
  }
}
