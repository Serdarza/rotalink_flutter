# Rotalink UX geliştirmeleri — çalışma durumu

Bu belge tamamlanma iddiası değildir. 26.10.2026 tarihinde son doğrulanmış durumu ve kalan işleri kaydeder.

## Hazırlanan ana ekran ve geri bildirim kapsamı

- Ana sayfa üst alanı kompaktlaştırıldı. Arama tek yüzey, 49 dp ve yalnızca “İl veya misafirhane ara...” açıklaması kullanıyor. Diğer arama motoru ve sesli arama kodu korunuyor.
- Hızlı işlemlerde yalnızca Rota kısayolu “Yakınımdaki / Misafirhaneler” oldu. Alt navigasyondaki Rota korunuyor.
- Ortak konaklama önbelleğinden Haversine ile 20/50/100 km sonuçları, tür filtresi, il/ilçe ile devam ve mevcut detay açma bağlantısı hazır. Koordinatlar kaydedilmiyor.
- Ortak Bildir bileşeni ve gönderim servisi hazır. Menü önerisi, tesis bilgi hatası ve fiyat bildirim formları aynı servisi kullanıyor. E-posta isteğe bağlı, geri dönüş izni gerekli.
- Ayrı admin projesinde sayfalı Firestore gelen kutusu, tür/durum filtreleri, yeni sayısı, yönetici notu ve izinli e-posta yanıtı bağlantısı hazır. Eski D1 manuel kayıtları ayrı bölümde korunuyor.
- Sunucu yeni kayıtları `feedback_reports` koleksiyonuna doğrulama, limit ve aynı gönderim ID'si korumasıyla yazacak. Durum/not/tarih istemciden kabul edilmiyor.

Bu kapsamın testleri: **56 Flutter testi**, **173 admin testi** geçti. Admin sayısı dört gerçek yerel Firestore emülatör testini içerir. Emülatörde anonim get/list/create/update engellendi; sunucu tarihi, tekrar gönderim, 20+1 sayfalama ve sürüm kontrolü doğrulandı. Üretim Firebase verisine test yazısı gönderilmedi.

## Hazırlanan tesis detay kapsamı

- Geri oku, logo ve Rotalink başlığı; turkuaz tesis tanıtımı ve tesis koordinatını kullanan hava rozeti.
- Adres/kuş uçuşu mesafe ve mevcut Yol Tarifi bağlantısı.
- Favori, Takvim, Yorum, Karşılaştır, Paylaş aynı mevcut işlemlere bağlı.
- Mevcut PRO kapısının arkasında dinamik fiyat grupları; detaylı tarife hesaplamadan önce geliyor.
- Kimler konaklayabilir / Nasıl kalınır kompakt açılır bölümler; mevcut metinler ve genel kural açıklaması korunuyor.
- Sabit Haritada göster / Ara eylemleri. Detayda arama/filtre üst alanı gizleniyor; listeye dönüş kodu korunuyor.
- Hesaplama algoritması değişmedi. Modal kök Navigator'da açılıyor ve alt navigasyon etkileşimini kapatıyor; toplam özeti görünür tutuluyor.

Bu kapsamın testleri: **29 test geçti** (6 yeni detay/arayüz testi ve 23 mevcut tarife, hesaplama, konaklama kuralı, ücretsiz fiyat hakkı testi). Ayrı `PRICE_PREVIEW=true` PRO kilit testi otomatik onay incelemesindeki kullanım limiti nedeniyle çalıştırılamadı. Kilit koşulları kodda korunuyor; bu ayrı kontrol tamamlandı diye raporlanmamalı.

Son tam Flutter analizinde üretim kodunda derleme hatası yoktu. 15 önceki bulgu ve yeni testte iki biçim uyarısı raporlandı. Bu iki test uyarısı düzeltildi; sonrasında tam analiz henüz yeniden çalıştırılmadı.

## Son arama sonuçları tasarımı — henüz uygulanmadı

İstek ve referans okundu. Başlıca mevcut dosyalar `main_map_search_chrome.dart`, `misafirhane_search_results_sheet.dart`, `facility_location_filter_bar.dart`, `facility_sort_bar.dart`, `best_value_pro_card.dart` olarak belirlendi. İstenen ortak sonuç başlığı / Liste-Harita / tek filtre satırı / mevcut filtreleri içeren modal / kompakt kartlar henüz uygulanmadı. Mevcut arama, fiyat sıralama ve kategori davranışları korunarak devam edilmeli.

## APK ve canlı durum

`build/releases/rotalink-ux-feedback-4.8.2.apk` ana ekran/yakın tesis/geri bildirim kapsamıyla derlendi ve imzası ile Firebase yapılandırması doğrulandı. **Son tesis detay değişikliklerini içermez; nihai APK değildir.** SHA256: `978FE895F4ACA2571CC4AFCCE95E58326DD464A9BA0AB89A68557DDA63A26ECB`.

USB telefonu son kontrolde bağlıydı; bu yeni kapsam telefona kurulmadı. Android fiziksel cihaz ve gerçek iOS denemeleri tamamlandı diye raporlanmamalı. Arama ve takvim/paylaşım/telefon dış uygulama testleri ayrıca gerekir.

Üretim admin Worker'ına bu yeni kapsam yüklenmedi. Firestore için ayrı hizmet hesabı/izin ve gizli anahtar aktarımı, yalnızca feedback indeksleri ve D1 `0009_feedback_limits` migration'ı bekliyor. Mevcut varsayılan Firestore ret kuralı feedback koleksiyonunu zaten korur; yayımlanmış kuralların yedeği `firebase/firestore.current.rules` dosyasındadır. Bu yedek otomatik dağıtım hedefi değildir.

Ayrı admin projesindeki `docs/feedback-activation.md` canlıya alma ve geri alma adımlarını içerir. Yeni sunucu yetkisi ve canlıya yükleme için kullanıcının önceki onay sınırı gözetilmelidir. FCM hesabını Firestore için kullanma; bildirim gönderme veya DNS değişikliği bu kapsamda gerekmez.

## Değişen dosyalar

Flutter:

- `lib/screens/home_dashboard_screen.dart`, `nearby_guesthouses_screen.dart`, `rotalink_main_shell.dart`, `main_map_screen.dart`, `suggestion_screen.dart`
- `lib/navigation/main_map_nav_bridge.dart`, `rotalink_shell_routes.dart`
- `lib/services/nearby_guesthouses.dart`, `nearby_location_access.dart`, `feedback_service.dart`
- `lib/widgets/custom_search_bar.dart`, `feedback_report_button.dart`, `facility_info_error_report.dart`, `facility_price_report_sheet.dart`
- `lib/widgets/facility_detail_card.dart`, `facility_detail_action.dart`, `facility_weather_badge.dart`, `facility_compare_widgets.dart`, `facility_stay_eligibility_card.dart`, `facility_overnight_price_box.dart`, `stay_cost_calculator_sheet.dart`, `misafirhane_search_results_sheet.dart`
- `lib/constants/facility_pricing.dart` (gönderim butonunun yeni yönteme uygun metni)
- `lib/utils/misafirhane_compact_sheet_height.dart`
- `firebase/firestore.current.rules`, `firebase/feedback.indexes.json`
- `test/nearby_guesthouses_test.dart`, `nearby_guesthouses_screen_test.dart`, `feedback_service_test.dart`, `home_search_feedback_ui_test.dart`, `home_discover_cards_test.dart`, `facility_detail_ui_test.dart`

Admin (`../rotalink-admin`):

- `server/types.ts`, `server/index.ts`, `server/firestore-feedback.ts`
- `shared/feedback.ts`, `shared/catalog.ts`
- `src/App.tsx`, `src/api.ts`, `src/style.css`, `src/pages/FeedbackManagement.tsx`, `LegacyFeedbackManagement.tsx`, `SettingsPage.tsx`
- `migrations/0009_feedback_limits.sql`
- `tests/feedback.test.ts`, `tests/feedback-emulator.test.ts`, `docs/feedback-activation.md`

Bu çalışmada yeni çalışma zamanı paketi, ücretli servis, tesis fotoğrafı, gerçek fiyat/veritabanı değişikliği veya GitHub Actions değişikliği eklenmedi. Yerel test için Google'ın resmî Firestore emülatörü indirildi ve resmî SHA256 değeri doğrulandı.


## Son düzeltme: Yakınımdaki Misafirhaneler

Kullanıcının son isteğiyle bu ekrandaki il/ilçe soruları ve 20/50/100 km seçimleri kaldırıldı. Açılışta GPS ve izin kontrolünden sonra mevcut `KamiDistanceService.nearestProvinceName` il eşlemesi kullanılır; belirlenen ilin tesisleri gerçek cihaz konumuna göre yakından uzağa sıralanır. Koordinatı olmayan tesisler mesafe verilmeden en sona alınır. GPS kapalıysa Konumu aç penceresi cihaz ayarlarına yönlendirir; ayarlardan dönüşte otomatik kontrol edilir. GPS izni reddedildiğinde il seçimi sorulmaz ve sahte mesafe oluşturulmaz.

İl eşlemesi mevcut uygulamadaki en yakın il merkezi yaklaşımını kullanır; kesin idari sınır tespiti değildir. Yeni servis/paket/ağ isteği eklenmedi. Bu son değişikliğin dört widget testi güncellendi, fakat önceki otomatik inceleme kullanım sınırı nedeniyle henüz yeniden çalıştırılmadı. Son düzeltme eski APK'ya dahil değildir; son doğrulama ve yeniden derleme gerekir.


## 26.10.2026 son fiyat kartı düzeltmesi — doğrulandı

Özet fiyat kartında aralıkların yalnızca minimum tutarı gösterilir. Bu yalnızca sunumdur: kaynak JSON kayıtları, ayrıntılı tarifeler ve ücret hesaplama algoritması değiştirilmez. Türkçe TL aralıkları `minimumPriceAmount` yardımcı işleviyle çözümlenir; sayısal olmayan açıklamalardan ücret üretilmez. Tutarlar kesilmeden tek satıra sığdırılır. Fiyatı Güncelle butonu daha küçük görsel çerçevede, sağ kenara hizalı ve mevcut form bağlantısıyla sunulur. Kaynak/doğrulama/tarih açıklamaları özetten kaldırıldı, detaylı tarife altına alındı. Yalnız eski fiyat alanları olan kayıtların ayrıntı penceresinde de özgün aralık ve kaynak korunur.

Son doğrulamalar:

- Fiyat özeti, detay görünümü, mevcut hesaplama ve tarife test grubu: 24 test geçti.
- Eski fiyat alanlarının kaynak ayrıntısı: 1 ek test geçti.
- `PRICE_PREVIEW=true` ile gerçek PRO kilit kontrolü: 1 test geçti. Önceki kullanım sınırı artık bu doğrulamayı engellemiyor.
- İl sormayan otomatik konum akışı ve Haversine grubu: 8 test geçti.
- Tam `flutter analyze`: yeni hata/uyarı yok; 15 önceki bulgu (14 bilgi, 1 uyarı) sürüyor.

Ek/değişen dosyalar: `lib/utils/minimum_price_amount.dart`, `lib/widgets/facility_overnight_price_box.dart`, `test/minimum_price_amount_test.dart`, `test/facility_detail_ui_test.dart`. Son konum değişikliğinin `nearby_guesthouses_screen.dart` ve karşılık gelen test dosyası da biçimlendirildi ve test edildi.

Önceki bölümlerde bekliyor yazan PRO testi ve konum testleri bu son sonuçla tamamlanmıştır. Arama sonuçları ekranı yenilemesi ve canlı Firestore yetkisi hâlâ ayrı bekleyen işlerdir; bu fiyat düzeltmesi onların tamamlandığı anlamına gelmez.


Son kişisel Android APK'sı başarıyla derlendi: `build/releases/rotalink-4.8.2-fiyat-duzeltmesi.apk`. Bu dosya tesis detay yenilemesini, minimum fiyat/taşma/kaynak düzeltmesini ve il sormayan konum akışını içerir. Önceki APK dosyası korunur. Yeni dosya ayrı teslimdir; otomatik telefona kurulmadı, mağazaya veya canlı sunucuya yayın yapılmadı.


## Son hava kutusu düzenlemesi

Tesis hava rozeti ana ekrandakiyle aynı renk paletini kullanır. Simge, derece, il ve açıklama ayrı satırlarda ortalandı; uzun derece metni tek satırda sığdırılır. Hava sorgusu, hata/eksik veri davranışı ve önbellek korunur. Yalnızca istenen Yol Tarifi butonu kaldırıldı; Haritada göster, Ara ve diğer hızlı işlemler korunur. Yapıcıların mevcut onInspect alanı çağıran ekranların API'sini bozmamak için bırakıldı.

Değişen dosyalar: `lib/theme/weather_badge_palette.dart` (ortak renkler), `lib/widgets/map_weather_chip.dart` (aynı palete yönlendirme, mevcut renkler değişmez), `lib/widgets/facility_weather_badge.dart`, `lib/widgets/facility_detail_card.dart`, `test/facility_detail_ui_test.dart`.

Hava/konaklama detayı, ana ekran kartları ve minimum fiyat test grubu: 12 test geçti. Test, hava verisinin tesis koordinatlarından geldiğini, simge/derece/metin merkezlerinin eşleştiğini ve ana ekranla aynı renk paletini kullandığını doğrular.

Hava düzenlemesine ait beş dosyanın hedefli Flutter analizi temiz: No issues found. Kişisel Android APK başarıyla derlendi ve imzası doğrulandı: build/releases/rotalink-4.8.2-hava-duzeltmesi.apk (4.8.2+86). SHA256: 0647B283D68DAA8D88E30AF47936169F096EABE1837F707F6ABCD70E93A44173. Önceki APK korunur; telefona otomatik kurulum veya sunucuya yayın yapılmadı.


## 27.10.2026 — Arama sonuçları yenilemesi

Önceki bölümlerde bekliyor olarak belirtilen arama sonuçları yenilemesinin kaynak kodu artık tamamlandı. Ayrıntılar ve test kapsamı `docs/arama-sonuclari-ui-2026-10-27.md` dosyasındadır. 25 regresyon testi ve 1 ek kilitli PRO testi geçti. Kullanıcının son talebine uygun olarak bu değişiklik için APK üretilmedi veya kurulmadı. Canlı Firestore etkinleştirmesi ayrı bekleyen iştir.
