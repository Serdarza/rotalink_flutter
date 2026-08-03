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
      'Bildiğiniz güncel ücreti bize iletebilir veya tesisi arayabilirsiniz.';

  static const reportPriceButton = 'Fiyat Bildir';
  static const reportWrongButton = 'Fiyatı Güncelle';

  static const reportSheetTitleNew = 'Fiyat Bildir';
  static const reportSheetTitleCorrection = 'Fiyatı Güncelle';
  static const reportSheetSubtitle =
      'Paylaştığınız bilgi incelenir; uygunsa uygulamada güncellenir.';
  static const reportSivilHint = 'Örn. 1.500 TL veya 1.200 – 2.000 TL';
  static const reportNoteHint = 'Kaynak, tarih veya kısa açıklama (isteğe bağlı)';
  static const reportSubmit = 'E-posta ile gönder';
  static const reportMailFailed = 'E-posta uygulaması açılamadı.';
  static const reportNeedOnePrice =
      'En az bir fiyat alanı doldurun.';
  static const reportDisclaimer =
      'Bildirimleriniz manuel incelenir; anında yayınlanmaz.';

  static const lockedTitle = 'Fiyat bilgisi Pro ile açılır';
  static const lockedBody =
      'Konaklama ücretlerini görmek için Rotalink Pro’ya geçin. '
      'Harita, arama ve tesis bilgileri ücretsiz kullanılmaya devam eder.';
  static const unlockWithProButton = 'Rotalink Pro’ya geç';
}
