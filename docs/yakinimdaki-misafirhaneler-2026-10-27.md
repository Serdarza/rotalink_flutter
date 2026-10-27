# Yakınımdaki Misafirhaneler — 27.10.2026

- Her açılışta mevcut listeyi temizleyip GPS bekleme kaldırıldı. İzin kontrolünden sonra en çok 2 dakikalık ve doğruluğu en çok 1 km olan son konumla ilk liste gösterilebilir; yeni konum arka planda alınır. Önbellek yalnızca bellektedir, veritabanına yazılmaz.
- Son konum OS üzerinden en fazla 600 ms beklenerek alınır. GPS isteği 8 saniyeyle sınırlıdır. Servis/izin kontrolü 3 saniye, kullanıcı izin penceresi 30 saniye ile sınırlandırılır. Cevapsız istekler arayüzü kalıcı olarak kilitlemez.
- Tarayıcı eklentisinin sınırsız bekleyen izin isteği yerine süreli konum isteği kullanıldı; izin sırasında alınan taze konum yeniden GPS beklenmeden kullanılır.
- Güncelleme başarısızsa yakın zamanda alınmış geçerli sonuçlar korunur ve kullanıcıya bunun son konum olduğu belirtilir. Eski, geçersiz veya aşırı belirsiz konum ilk liste için kullanılmaz.
- Adres/ilçe eşleştirme mevcut FacilityAddressRepository üzerinden arka planda hazırlanır; eşzamanlı adres yüklemeleri tek istek paylaşır. Veri yüklenirken yanlışlıkla boş sonuç mesajı gösterilmez.
- Yeni NearbyGuesthouseCard: tesis simgesi, okunaklı ad, il/ilçe, tür etiketi ve kuş uçuşu mesafe. İlçe yoksa mevcut adres çözümleyicisinin açık ilçe eşleştirmesi kullanılır; bulunamayan ilçe uydurulmaz. Eksik koordinatlar mesafesiz ve listenin sonunda kalır.
- Aynı ilde yakından uzağa listeleme, tesis detayına geçiş, konum kapalı popup/ayar dönüşü ve filtreler korunur. Mevcut il bulma yöntemi yakın il merkezi yaklaşımıdır; il sınırında kesin idari sınır doğrulaması sağlamaz.
- Arama panelinden ayrılırken devam eden geocode işinin kapanmış widget ref'ini okuması mounted kontrolüyle engellendi.

23 test geçti (konum/izin/GPS zaman aşımı, geçerli son konumla anlık liste, hatada listeyi koruma, Haversine ve sıralama, il/ilçe, büyük yazı/tema, arama ve navigasyon regresyonları). Konum/arayüz/adres değişikliklerinin beş dosyalık analizi temiz. Gerçek cihazın GPS süresi ve sinyal kalitesi bu testlerden ölçülmez.

Değişen dosyalar: lib/services/nearby_location_access.dart, lib/screens/nearby_guesthouses_screen.dart, lib/widgets/nearby_guesthouse_card.dart (yeni), lib/data/facility_address_repository.dart, lib/widgets/misafirhane_search_results_sheet.dart, test/nearby_guesthouses_screen_test.dart.

APK üretilmedi, üretim verisi veya Firebase yetkisi değiştirilmedi; ücretli servis/paket eklenmedi.


## Son görünüm tercihi — arama kartları ve PRO önerisi

Önceki özel yakınlık kartının yerine arama sonuçlarıyla aynı `SearchFacilityResultCard` bileşeni kullanılır: simge, ad, il/ilçe, yeşil Fiyat Bilgisi etiketi, gerçek kuş uçuşu mesafe ve detay oku. Önceden Haversine ile hesaplanan mesafe ortak bileşene aktarılır; yeniden farklı yöntemle hesaplanmaz. İlçe eşleştirmesi korunur; olmayan mesafe satırı gizlenir.

Aynı ilde ve mevcut tür filtresinde gösterilen tesisler arasında mevcut `pickBestValueFacility` kullanılarak doğrulanmış, karşılaştırılabilir en uygun tek kişi/gece fiyatı seçilir. Mevcut turkuaz/altın `BestValueProCard` normal listenin üstünde gösterilir. Sivil/kamu kıyaslama, resmî kaynak/tesis doğrulama ve PRO erişim kuralları aynen korunur. Uygun fiyat yoksa kart gösterilmez. Normal tesis listesi yakından uzağa kalır; PRO kartı fiyat önerisi olarak ayrı üst sıradadır. Fiyatlar mevcut önbellekten arka planda hazırlanır; eşzamanlı yüklemeler tek isteği paylaşır.

24 test ve ayrıca PRICE_PREVIEW=true ile 1 kilitli PRO testi geçti. Test; daha ucuz başka ildeki tesisi ve doğrulanmamış fiyatı seçmediğini, en uygun tesise giden callback'i, yeşil fiyat göstergesini, mesafe sırasını ve arama kartlarıyla ortak bileşeni doğrular. Bu son istek kapsamında APK derlenmedi, web önizleme açılmadı veya yenilenmedi.
