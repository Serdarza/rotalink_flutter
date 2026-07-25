/// Ödüllü reklam sonucu — fiyat kilidi için.
enum RewardedUnlockResult {
  /// Kullanıcı ödülü kazandı.
  earned,

  /// Reklam gösterildi ama ödül alınmadan kapatıldı.
  dismissed,

  /// Reklam yüklenemedi / gösterilemedi (ağ veya AdMob).
  unavailable,

  /// Reklamlar kapalı (web / adsEnabled=false) — kilit açılmalı.
  bypass,
}
