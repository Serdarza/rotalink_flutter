/// Tesis fiyat UI metinleri (fiyat değerleri GitHub tesis JSON'undan gelir).
abstract final class FacilityPricing {
  static const note =
      'En güncel fiyat bilgisini tesisten öğrenebilirsiniz.';

  static const unavailableLabel = 'Kalamaz';

  static const sivilLabel = 'Sivil misafir';
  static const kamuLabel = 'Kamu personeli';
  static const kurumLabel = 'Kurum personeli';

  static const missingPriceTitle = 'Ücret bilgisi kayıtlı değil';
  static const missingPriceBody =
      'Güncel konaklama ücretini öğrenmek için tesisi arayabilirsiniz.';

  static const lockedTitle = 'Fiyat bilgisi kilitli';
  static const lockedBodyNoCredit =
      'Kısa bir reklam izleyerek 5 tesisin fiyat bilgisini açabilirsiniz.';
  static String lockedBodyWithCredit(int credits) =>
      'Kalan hakkınız: $credits tesis. Bu tesisin fiyatını açabilirsiniz.';

  static const unlockWithCreditButton = 'Fiyatları aç';
  static const unlockWithAdButton = 'Reklam izle — 5 tesis hakkı kazan';
  static const unlockLoading = 'Reklam hazırlanıyor…';
  static const unlockFailed =
      'Reklam şu an yüklenemedi. Lütfen biraz sonra tekrar deneyin.';
  static const unlockOfflineGrace =
      'İnternet yok. Bu tesisin fiyatı bu kez ücretsiz açıldı.';
  static const unlockAdUnavailableGrace =
      'Reklam şu an hazır değil. Bu tesisin fiyatı bu kez ücretsiz açıldı.';
  static const unlockDismissed =
      'Reklamı tamamlayınca fiyat bilgisi açılır.';
}
