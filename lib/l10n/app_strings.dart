/// `res/values/strings.xml` + `activity_main.xml` / `drawer_menu` içi sabit metinler.
abstract final class AppStrings {
  static const String appName = 'Rotalink';
  static const String splashTagline = 'Akıllı Seyahat Rehberiniz';
  static const String defaultNotificationChannelId = 'rotalink_notifications';
  static const String discoverLoadingTitle = 'Kampanyalar yükleniyor';
  static const String discoverLoadingSubtitle = 'Birkaç saniye içinde hazır olacak';
  static const String campaignDetailCta = 'Detayları Gör';
  static const String share = 'Paylaş';
  static const String discoverSearchHint = 'İl, kurum veya kampanya ara';
  static const String campaignOpenLink = 'Bağlantıyı aç';
  static const String campaignGoToDetails = 'Kampanya Detaylarına Git';
  static const String campaignGoToDetailsSub = 'Tam içerik harici bağlantıda açılır';

  static const String searchCityHint = 'Şehir veya misafirhane arayın';
  static const String searchNoResults = 'Sonuç bulunamadı.';
  static const String menuOpen = 'Menüyü Aç';
  static const String clearSearch = 'Clear search';
  static const String ilDataLoading = 'İl verileri güncelleniyor…';
  static const String fabMisafirhaneList = 'Misafirhane Listesini Aç';
  static const String fabEmergency = 'Acil — SOS ve sağlık';
  static const String emergencyLabel = 'ACİL';
  static const String bottomHistory = 'Geçmiş';
  static const String bottomFavorites = 'Favorilerim';
  static const String favoritesEmpty = 'Favori listeniz boş.';
  static const String bottomRoutePlan = 'Rota Planla';

  static const String routePlanTitle = 'Rota Planı Oluştur';
  static const String routePlanStartCity = 'Başlangıç şehri';
  static const String routePlanStartHint = 'Örn: Düzce';
  static const String routePlanStopsTitle = 'Duraklar ve gün sayısı';
  static const String routePlanStopCityHint = 'Durak şehri';
  static const String routePlanDaysHint = 'Konaklama (gece)';
  static const String routePlanSuggestionsTitle = 'Günlük plan — öneriler';
  static const String routePlanCuratorHint =
      'Her şehir için 1 misafirhane, 2 yemek, 3 gezi önerisi; + / listelerden özelleştirin.';
  static const String routePlanPreviewMapTitle = 'Rota önizleme (OSM)';
  static const String routePlanStickySummary = 'Rota özeti';
  static const String routePlanShareRoute = 'Paylaş';
  static const String routePlanNavGoogle = 'Google';
  static const String routePlanNavYandex = 'Yandex';
  static const String routePlanNavApple = 'Apple';
  static const String routePlanShowOnMainMap = 'Ana haritada göster';
  static const String routePlanPreviewNeedTwoCities =
      'Önizleme için başlangıç ve en az bir hedef şehir seçin.';
  static const String routePlanPreviewNeedCoords =
      'Rota çizimi için şehirlerde koordinatlı tesis gerekli.';
  static const String routePlanAddMisafirhane = 'Misafirhane';
  static const String routePlanAddGezi = 'Gezi';
  static const String routePlanAddYemek = 'Yemek';
  static const String routePlanRemove = 'Kaldır';
  static const String routePlanAdd = 'Ekle';
  static const String routePlanStepNavNoMisafirhane =
      'Bu rotada haritada açılacak misafirhane yok. Konaklama ekleyin.';
  static const String routePlanPickNeedCity = 'Önce bu durağın ilini seçin.';
  static const String routePlanNoDataForIl = 'Bu il için kayıt bulunamadı.';
  static const String routePlanStartNoOvernight = 'Başlangıç · konaklama yok';
  static const String routePlanDayShort = 'Gün';
  static const String routePlanAddStop = 'Durak ekle';
  static const String routePlanCalculate = 'Rotayı hesapla ve önerileri göster';
  static const String routePlanInvalidStart = 'Lütfen geçerli bir başlangıç şehri giriniz.';
  static const String routePlanInvalidStop = 'Geçersiz durak şehri; listeden seçin.';
  static const String routePlanNeedTarget = 'Lütfen en az bir hedef şehir giriniz.';
  static const String routePlanSavedTitle = 'Kaydedilmiş rotalar';
  static const String routePlanNew = 'Yeni rota';
  static const String routePlanDelete = 'Sil';
  static const String routePlanSaveTitle = 'Rotayı kaydet';
  static const String routePlanSaveNameHint = 'Rota adı';
  static const String routePlanSaveEmptyName = 'Lütfen rota ismi girin.';
  static const String routePlanSaveSuccess = 'Rota kaydedildi.';
  static const String routePlanSummaryTitle = 'Rota özeti';
  static const String routePlanSelectIl = 'İl seçin';
  static const String routePlanSearchIlHint = 'İl ara…';
  static const String routePlanTimelineStart = 'Başlangıç';
  static const String routePlanTimelineStop = 'Durak';
  static const String routePlanTimelineEnd = 'Varış';
  static const String routePlanTimelineWaypoint = 'Ara durak';
  static const String routePlanTotalDistance = 'Toplam mesafe';
  static const String routePlanTotalDuration = 'Tahmini sürüş süresi';
  static const String routePlanOsrmNote = 'Araç rotası (OSRM) — trafik dahil değildir.';
  static const String routePlanDaysLabel = 'gün';
  static const String routePlanKonak = 'Konaklama';
  static const String routePlanGezi = 'Gezi';
  static const String routePlanYemek = 'Yemek';
  static const String routePlanClearRoute = 'Rota temizle';
  static const String routePlanNoSuggestions = 'Bu durak için öneri yok.';
  static const String routePlanPreviewTitle = 'Rota hazır';
  static const String routePlanShowOnMap = 'Haritada göster';
  static const String routePlanStartNavigation = 'Navigasyonu başlat';
  static const String routePlanGoogleFullDirections = 'Tüm güzergâh (Google)';
  static const String routePlanPreviewEdit = 'Düzenlemeye dön';
  static const String routePlanSelectedIlChip = 'Seçili il';
  static const String routePlanSearchIlLabel = 'İl ara';
  static const String routePlanPreviewNoMetrics =
      'Canlı mesafe hesabına ulaşılamadı; haritada rota yine de çizilecek.';
  static const String routePlanInsufficientLocations = 'Rota için yeterli konum bulunamadı.';
  static const String bottomDiscover = 'Keşfet';
  static const String bottomIlanlar = 'İlanlar';
  static const String ilanlarSearchHint = 'İlan veya kurum ara…';
  static const String ilanlarEmpty = 'Henüz aktif ilan bulunmuyor.';
  static const String ilanlarNoResult = 'Aramanıza uygun ilan bulunamadı.';
  static const String ilanlarLoadError = 'İlanlar yüklenemedi. Önbellek gösteriliyor.';
  static const String drawerSubtitle = 'Akıllı Seyahat Rehberiniz';
  static const String drawerVersionPrefix = 'Sürüm: ';

  static const String drawerWeather = 'Bölgesel Hava Durumu';
  static const String drawerHolidays = '2026 Resmi Tatiller';
  static const String drawerSuggestion = 'Öneri Gönder';
  static const String drawerWebsite = 'Web Sitemize Git';
  static const String drawerShareApp = 'Uygulamayı Paylaş';
  static const String drawerAbout = 'Hakkımızda';

  static const String myLocationTooltip = 'Konumum';
  static const String mapDataLoading = 'Veri yükleniyor…';
  static const String locationPermissionNeeded = 'Konum izni gerekli.';
  static const String locationServicesOffSnack =
      'Konum hizmetleri kapalı. Lütfen cihaz ayarlarından GPS\'i açın.';
  static const String locationFailedPrefix = 'Konum alınamadı: ';
  static const String featureSoon = 'Bu bölüm yakında eklenecek.';

  static const String suggestionTitle = 'Önerinizi Bize İletin';
  static const String suggestionSubtitle =
      'Her türlü öneri, istek veya geri bildiriminizi buradan iletebilirsiniz.';
  static const String suggestionNameHint = 'Ad Soyad (isteğe bağlı)';
  static const String suggestionEmailHint = 'E-posta adresiniz';
  static const String suggestionBodyHint = 'Öneriniz';
  static const String suggestionSend = 'Gönder';
  static const String suggestionValidationToast =
      'Lütfen e-posta ve öneri alanlarını doldurun.';
  static const String suggestionThanksTitle = 'Teşekkürler!';
  static const String suggestionThanksMessage =
      'Öneriniz için teşekkür ederiz. Geri bildiriminiz bizim için çok değerli.';
  static const String suggestionOk = 'Tamam';
  static const String suggestionMailFailed = 'E-posta uygulaması açılamadı.';
}
