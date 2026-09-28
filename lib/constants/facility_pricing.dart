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

  static const sortDistance = 'Yakınlık';
  static const sortPrice = 'Fiyat: ucuzdan pahalıya';
  static const unverifiedPrice = 'Teyit gerekli';
  static String unpricedHeader(int n) => 'Fiyat bilgisi olmayan tesisler ($n)';
  static const sortTeaserTitle = 'Fiyata göre sıralama Pro’da';
  static String sortTeaserCount(int n) =>
      'Bu aramada $n tesisin fiyatı mevcut.';
  static const sortTeaserPerks = [
    'Fiyatı olan tesisleri ucuzdan pahalıya tek listede görün.',
    'Sivil veya kamu personeli fiyatına göre sıralayın.',
    'Her tesisin tek kişilik gecelik fiyatı listede yazsın.',
  ];

  static const budgetChip = 'Bütçe';
  static String budgetChipActive(String amount) => 'En fazla $amount';
  static const budgetSheetTitle = 'Gecelik bütçeniz';
  static const budgetSheetBody =
      'Tek kişi / gece fiyatı bu tutarı aşan tesisler listeden gizlenir. '
      'Fiyat bilgisi olmayan tesisler altta ayrıca listelenir.';
  static const budgetApply = 'Uygula';
  static const budgetClear = 'Bütçeyi kaldır';
  static String budgetHidden(int n) => 'Bütçenizi aşan $n tesis gizlendi';
  static const budgetNoneFits = 'Bu bütçeye uygun fiyatlı tesis yok.';
  static const budgetTeaserTitle = 'Bütçe filtresi Pro’da';
  static String budgetTeaserCount(int n) =>
      'Bu aramada $n tesisin fiyatı mevcut.';
  static const budgetTeaserPerks = [
    'Gecelik üst limitinizi seçin, bütçenizi aşan tesisler gizlensin.',
    'Sivil veya kamu personeli fiyatına göre filtreleyin.',
    'Fiyat sıralamasıyla birlikte kullanın.',
  ];

  static const compareAdd = 'Karşılaştırmaya ekle';
  static const compareAdded = 'Karşılaştırmada';
  static String compareOpen(int n) => 'Karşılaştır ($n)';
  static const compareClear = 'Temizle';
  static const compareFull = 'En fazla 3 tesis karşılaştırılabilir.';
  static const compareNeedTwo = 'Karşılaştırmak için bir tesis daha ekleyin.';
  static const compareTitle = 'Tesis karşılaştırma';
  static const compareCheapest = 'En uygun';
  static const compareNoPrice = 'Fiyat yok';
  static const compareRowPriceSivil = 'Sivil (tek kişi / gece)';
  static const compareRowPriceKamu = 'Kamu personeli (tek kişi / gece)';
  static const compareRowDistance = 'Uzaklık';
  static const compareRowType = 'Tesis türü';
  static const compareRowCivil = 'Sivil konaklama';
  static const compareRowLocation = 'Konum';
  static const compareRemove = 'Çıkar';
  static const compareTeaserTitle = 'Tesis karşılaştırma Pro’da';
  static const compareTeaserHeadline = '3 tesise kadar yan yana karşılaştırın.';
  static const compareTeaserPerks = [
    'Sivil ve kamu personeli fiyatlarını aynı tabloda görün.',
    'En uygun tesis otomatik işaretlensin.',
    'Uzaklık, tesis türü ve kimlerin kalabileceği tek bakışta.',
  ];
}
