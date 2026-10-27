# Resmî tatillerin panelden yönetimi

Admin projesi: `../rotalink-admin`. Kaynak: HTTPS üzerinden `https://admin.rotalink.tr/public/holidays`.

Panelde ekleme, düzenleme, pasife alma ve onaylı geri alınabilir kaldırma önce taslağa kaydedilir. Uygulama yalnızca yayımlanan tam listeyi okur. Bir kayıt kaldırıldığında gömülü listeyle birleştirilerek yeniden oluşturulmaz. Bilinçli boş yayın da geçerlidir.

Sözleşme: `schemaVersion: 1`, `published: true`, pozitif tamsayı `revision`, `items` listesi. Kayıtlarda `id`, `name`, `startDate`, `endDate`, `kind`, `detail`, `sourceUrl`, `active` alanları bulunur. Tarihler `YYYY-MM-DD`; türler `milli`, `dini`, `idari`. Yayımlanmamış, hatalı veya eski sürüm yanıtları son geçerli listeyi değiştirmez.

Veri deposu SharedPreferences önbelleği kullanır. İlk açılış ağ isteğini beklemez. Ağ verisi yokken son geçerli yayın, o da yoksa mevcut 25 gömülü kayıt kullanılır. Ekran açılışı ve uygulamanın mevcut resume akışı arka planda yeniler; başarılı okumalar arasında beş dakika vardır. Tatil ekranını aşağı çekmek zorunlu yenileme yapar.

Tatil listesi değiştiğinde yalnızca 910000–910999 kimlik aralığındaki tatil hatırlatıcıları iptal edilip yeniden planlanır. Diğer kampanya/duyuru bildirimleri korunur. Hatırlatıcı tercihi ve mevcut yedi gün önce 09:00 davranışı korunur. iOS sınırına yer bırakmak için en fazla 48 tatil hatırlatıcısı planlanır. Uygulama açılmadan çevrimdışı telefondaki eski hatırlatıcılar uzaktan iptal edilemez.

Mevcut gömülü tarihler bu geliştirme kapsamında yeniden araştırılmadı. Admin geçişi bunları taslak olarak aktarır, otomatik yayımlamaz. Mevcut GitHub JSON/Actions, Firebase ve diğer ekranların kaynakları değişmez.

Bu bağlantı yeni Flutter sürümünün dağıtılmasını gerektirir. Daha önce kurulu APK/iOS sürümleri kendi gömülü listesini kullanmaya devam eder. Mağazaya yükleme ve gerçek cihaz bildirim testi bu çalışma kapsamında yapılmadı.

25.10.2026 cihaz denemesi: güncel debug APK bağlı Android 15 telefona `adb install -r` ile başarıyla güncellendi. İlk kurulum zamanı korundu, bildirim izni açık kaldı. MainActivity başarıyla açıldı; yeni uygulama işleminde Flutter/AndroidRuntime hata kaydı görülmedi. Bu yalnızca kullanıcının test telefonundaki kurulumdur; mağaza yayını veya gerçek FCM teslim testi değildir. Panelde ilk tatil yayını hâlâ yapılmadığı için gömülü liste kullanılmaya devam eder.

Doğrulama: 15 tatil veri deposu testi ve 8 mevcut duyuru/ana sayfa testi başarılı (23/23). Değişen tatil dosyaları için hedefli Dart analizi temizdir. Genel Flutter analizindeki diğer dosyalara ait 16 mevcut bulgu bu çalışma kapsamında değiştirilmedi.
