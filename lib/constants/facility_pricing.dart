/// Tesis fiyat UI metinleri (fiyat değerleri GitHub tesis JSON'undan gelir).
abstract final class FacilityPricing {
  static const note =
      'En güncel fiyat bilgisini tesisten öğrenebilirsiniz.';

  static const unavailableLabel = 'Kalamaz';

  static const currentPricesTitle = 'Güncel fiyatlar';
  static const detailedTariffTitle = 'Detaylı tarife';
  static const showDetailedTariff = 'Detaylı tarifeyi göster';
  static const hideDetailedTariff = 'Detaylı tarifeyi gizle';
  static const showDetailedPrices = 'Detaylı fiyatları görüntüle';
  static const previewBadge = 'ÖNİZLEME';
  static const proIncludesTitle = 'Pro ile bu tesiste görecekleriniz';

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

  static const bestValueTitle = 'Bu aramada en uygun konaklama';
  static String bestValueTitleIl(String il) => '$il için en uygun konaklama';
  static const bestValueSingleTitle = 'Fiyatı görülebilen konaklama';
  static const bestValueUnit = 'tek kişi / gece';
  static String bestValueCompared(int n) =>
      'Fiyatı resmî kaynaktan doğrulanmış $n tesis arasında';
  static const bestValueCta = 'Pro ile en uygun fiyatı gör';
  static const bestValueOpen = 'Tesisi incele';
}
