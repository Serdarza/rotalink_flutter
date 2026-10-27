# Arama sonuçları ekranı — 27.10.2026

Arama sonuçlarının görünümü yenilendi. APK üretilmedi veya telefona kurulmadı. Canlı sunucu, JSON kayıtları, Firebase kuralları ve GitHub Actions değiştirilmedi.

## Yapılanlar

- Tek yüzeyli 56 dp arama; doğru sabit ipucu, temizle ve mikrofon bağlantıları korunur.
- Kategori sekmeleri arama altında, gerçek sayılar ve mevcut Daha menüsüyle çalışır.
- Dinamik il/kategori başlığı, gerçek sonuç sayısı ve Liste/Harita geçişi sekmelerin altındadır.
- Konaklamada Filtrele, İlçe, Sıralama tek alandadır. Normal genişlikte üç kontrol birlikte, dar ekran/büyük yazıda yatay kaydırılarak görünür.
- Türler, il/ilçe, mevcut bütçe ve fiyat kategorisi alt panelde korunur. Filtreleri Temizle ve Sonuçları Göster eklendi.
- Önerilen, gelen varsayılan sırayı korur. Bana en yakın gerçek kullanıcı konumu gerektirir. Artan/azalan fiyat sıralaması mevcut PRO kontrolünü kullanır; fiyatı olmayanlar ayrı ve sonda kalır. Eşit fiyatlarda kaynak sırası korunur.
- Normal tesis kartları kompakt; yeşil Fiyat Bilgisi, konum ve mevcut detay bağlantısıyla çalışır.
- Konum yoksa veya mesafe hesaplanamıyorsa mesafe satırı gizlidir. Gerçek mesafe Konumunuzdan / Kuş uçuşu açıklaması taşır.
- Mevcut doğrulanmış en uygun fiyat seçimi ve erişim kontrolü korunarak PRO kartı turkuaz/altın görünümüne getirildi. Kilitte gerçek ad/fiyat widget veya semantik metne verilmez.
- Diğer kategorilerde konaklama fiyat/tür kontrolleri gösterilmez; mevcut uygun il/ilçe ve içerik bağlantıları korunur.

## Değişen dosyalar

- lib/widgets/main_map_search_chrome.dart
- lib/widgets/custom_search_bar.dart
- lib/screens/main_map_screen.dart
- lib/widgets/facility_location_filter_bar.dart
- lib/widgets/misafirhane_search_results_sheet.dart
- lib/widgets/search_results_ui.dart (yeni ortak sunum bileşenleri)
- lib/widgets/best_value_pro_card.dart
- lib/utils/best_value_facility.dart (mevcut fiyat bölücüsüne isteğe bağlı azalan yön; varsayılan değişmez)
- test/search_results_ui_test.dart (yeni)

## Doğrulama

25 test geçti: arama sonuç panelinde Düzce örnek verisiyle tür/ilçe seçimi ve temizleme, yakınlık için konum gerekliliği, gerçek konumla yakınlık sırası ve Önerilen'e dönüş, Liste/Harita, Gezi/Yemek geçişleri; mevcut arama algoritması ve alt navigasyon köprüsü; ana ekran kategori/keşif/arama ve tesis detay regresyonları. Normal ve PRO kartlarda 320/390/600 dp, açık/koyu tema ve iki kat metin ölçeği kontrol edildi.

PRICE_PREVIEW=true ile ayrıca 1 gerçek PRO kilit testi geçti. Testlerde ağ/Firebase hizmetleri canlı çağrılarla doğrulanmadı; test ortamındaki core/no-app ve HTTP 400 kayıtları beklenen dış servis yokluğu mesajlarıdır. Gerçek cihazda mikrofon, OS izin pencereleri ve harita uygulaması açılışı ayrıca kontrol edilmelidir. Yeni paket veya ek Firestore sorgusu eklenmedi.

`flutter analyze --no-pub` proje genelinde çalıştırıldı: hata yok. Çıktıda 14 bulgu vardı (13 bilgi, 1 önceki uyarı); yeni kontrol satırındaki süslü parantez bilgi bulgusu düzeltildi. Kalan bulgular mevcut BuildContext/null-aware/biçim konuları ve `_SearchHighlightFlash.totalMs` parametresiyle ilgilidir. Değişen dokuz dosyanın hedefli analizinde de hata yok: 10 bulgu (9 bilgi, 1 önceki uyarı). Bu analiz çalışmaya başladıktan sonra bildirilen yeni `if (scroll)` biçim bulgusu süslü parantez eklenerek düzeltildi; işlem yalnız biçimseldir. Analiz uyarılar nedeniyle sıfır çıkış kodu vermedi; proje tamamen uyarısız olarak raporlanmaz. `git diff --check` temiz.

Bu rapor yalnızca arama sonuçları yenilemesinin teslimidir. Önceki ayrı Firestore geri bildirim servisinin canlı yetkilendirilmesi bu iş kapsamında açılmadı.


## Son tercih: dört tür ve sabit yakınlık sırası

Kullanıcının son isteği önceki sıralama/bütçe arayüzünün yerine geçer. Filtre panelindeki türler artık yalnızca Tümü, Orduevi, Öğretmenevi, Polisevi sırasındadır. İl/ilçe seçimi korunur. Sıralama seçici ve paneldeki fiyat/bütçe sıralama kontrolleri kaldırıldı. Liste, konum izni ve gerçek kullanıcı konumu varsa daima yakınlığa göre sıralanır; konum yoksa kaynak sırası korunur, mesafe üretilmez. Eksik/geçersiz tesis koordinatları konumlu kayıtların sonuna düşer; eşitlikte kaynak sırası korunur. Eski kayıtlı fiyat sırası ayarı artık bu ekranı değiştirmez. PRO öneri kartı ve diğer fiyat erişim kuralları korunur.

12 test geçti; bunlara dört türün tam listesi, ilçe/tür filtreleri, eski fiyat tercihi varken otomatik konum sırasının güncellenmesi, izinsiz/eksik konumda mesafenin gizlenmesi ve kategori/harita geçişleri dahildir. Codex yan panelinde Düzce aramasıyla dört seçenek ve Sıralama kontrolünün yokluğu doğrulandı. APK üretilmedi.


## İl seçimi ve çarpıyla ana sayfaya dönüş

Konaklama sonuçlarının kompakt filtre alanına İlçe'nin solunda İl seçimi eklendi. Mevcut il listesi ve `onSelectIl` arama bağlantısı yeniden kullanılır; il seçilince mevcut şehir araması çalışır. Birden çok il gösterilirken İl seçimi etkin, İlçe seçimi il belirlenene kadar kapalıdır.

Arama sonuçlarında ve Ara başlangıç ekranında çarpıya basılması metni temizleyip mevcut ana sayfa dönüşünü çağırır. Bu işlem `onClearPressed` ile yalnızca çarpı dokunuşuna bağlıdır: klavyeyle metni silme veya programatik temizleme yeni bir sayfa geçişi başlatmaz. Ana sayfa geçişi mevcut shell `goHome` üzerinden sonuçları/filtreleri sıfırlar.

16 test geçti: il seçiminin ilçe solunda olması, mevcut il seçici callback'i, çarpı ve klavye silmesi ayrımı, Ara ekranında ana sayfa callback'i, arama/navigasyon ve ana ekran arama/form regresyonları. APK veya önizleme oluşturulmadı.
