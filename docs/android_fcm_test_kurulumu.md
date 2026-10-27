# Android FCM test derlemesi

Tek telefon testinin Flutter tarafı `device_test_messaging.dart`, `device_test_service.dart` ve `device_test_screen.dart` dosyalarındadır. Genel kullanıcı konu aboneliği eklenmez. Sunucu gönderimi ayrıca admin projesindeki `DEVICE_TEST_FCM_ENABLED` bayrağına bağlıdır.

Windows'ta `flutter pub get` masaüstü symlink izni nedeniyle hata verirse başarılı bir Android eklenti üretimi yapılmış varsayılmamalıdır. Hatalı pub get sonrasında `--no-pub` ile derleme, eski Android `GeneratedPluginRegistrant` dosyasını koruyabilir; Dart birim testleri bu yerel eklenti eksikliğini göstermez.

Android derlemesi için masaüstü üretimini yalnızca ilgili PowerShell sürecinde atlayarak yeniden oluşturun:

```powershell
$env:FLUTTER_WINDOWS='false'
$env:FLUTTER_MACOS='false'
$env:FLUTTER_LINUX='false'
flutter pub get --offline
```

Bu ortam değişkenleri bilgisayarın veya Flutter SDK'nın kalıcı ayarlarını değiştirmez. Komutu ayrı bir terminal sürecinde çalıştırın. Paketler önbellekte yoksa normal `flutter pub get` kullanılır. Çıkış kodu sıfır olmalı ve Android'in otomatik eklenti dosyasında `FlutterFirebaseMessagingPlugin` bulunmalıdır. Üretilen dosyayı elle düzenlemeyin.

Ardından `flutter build apk --debug --no-pub` çalıştırın. Verileri koruyan cihaz güncellemesi için `adb install --no-streaming -r build/app/outputs/flutter-apk/app-debug.apk` kullanılabilir. Uygulamayı kaldırıp tekrar yükleme veri kaybına yol açabileceğinden bu testte kullanılmaz.

Gerçek cihaz kontrolü: Ayarlar → Yönetici testi → Bildirim bağlantısını yenile. Admin tarafında telefonun FCM kimliği yalnızca hazır/bekliyor bilgisiyle kontrol edilir; ham FCM tokenı veya özel anahtar günlükte/sohbette gösterilmez. Firebase `validate_only=true` doğrulaması gerçek bildirim gönderimi sayılmaz; cihaz teslimi ayrıca doğrulanmalıdır.

26.10.2026: Hizmet hesabının rolü kullanıcı tarafından `Firebase Cloud Messaging API Admin` olarak kaydedildikten sonra FCM HTTP v1 `validate_only=true` kontrolü 200 döndü. Bu kontrol telefonun FCM kaydını veya teslimi kanıtlamaz. Gerçek bildirim gönderilmedi.

Yönetici test ekranında Firebase başlatma, otomatik kayıt, APNs ve token alma aşamalarının hataları artık ayrı tanı kodlarıyla gösterilir. Yalnızca sabit hata kodları kullanılır; orijinal hata metni, anahtar ve token günlükte veya arayüzde gösterilmez. Telefonun sunucuya kaydı ayrı bir hata mesajıyla belirtilir. Bu değişiklikle birlikte `test/admin_device_test.dart` içindeki 15 test geçti.

Gerçek telefondan alınan kod `token: FIS_AUTH_ERROR` oldu. Ana Android yapılandırmasındaki istemci API anahtarı, geçersiz tanı kurulumu ve geçersiz yetkiyle yapılan FIS kontrolünde `API_KEY_INVALID` döndürdü (gerçek token/kurulum oluşturulmadı). Firebase konsolundan güncel Android yapılandırması istenirken Firebase otomatik olarak yeni bir istemci anahtarı oluşturdu. Bu anahtar gizli sunucu hizmet hesabı anahtarı değildir; yalnızca Firebase istemci kimliğidir.

Yeni yapılandırma `android/app/src/debug/google-services.json` dosyasına eklendi. Gradle debug kaynaklarında yeni anahtarın kullanıldığı doğrulandı; ana `android/app/google-services.json` ve release yapılandırması değiştirilmedi. Debug APK derlendi ve verileri koruyan güncellemeyle telefona yüklendi. Kullanıcı, yeni anahtarın Android paket adı ve test SHA-1 imzası kısıtlamasını Cloud Console üzerinden kaydetti. API listesinde `Android apps, 25 APIs` durumu görüldü. Places anahtarı korunuyor. Telefon kaydı ve ilk gerçek teslim ayrıca doğrulanmalıdır.

Release için ana yapılandırmadaki geçersiz eski anahtarın güncellenmesi ayrı entegrasyon işidir. Yalnızca debug imzasına kısıtlı bu dosya release için kopyalanmamalıdır; dağıtım imzalarına uygun resmî yapılandırma kullanılmalıdır.

Son kontrol: Kullanıcı telefonda “Bildirim bağlantısı yenilendi” mesajını gördü. Canlı Telefon Testleri ekranında eşleştirilmiş Android cihazın FCM belirteci `Hazır`, sunucu anahtarı `Hazır`, tek telefon gönderim izni `Açık` olarak doğrulandı. “Rotalink bildirim testi” taslağı ve tek Android cihaz seçilerek son onay penceresi açıldı. Gerçek gönderim düğmesine basılmadı; kullanıcı arka plan testi için bu ekrandan devam edecek. Bildirimin telefona teslimi henüz doğrulanmadı.

Bildirim logosu düzeltmesi: Opaque uygulama simgesinin Android küçük bildirim simgesi olarak kullanılması beyaz dolu bir şekil oluşturuyordu. Mevcut Rotalink logosunun beyaz ön planından şeffaf zeminli `ic_stat_rotalink.xml` vektör kaynağı üretildi. Manifestte arka plan FCM bildirimleri için varsayılan ikon ve marka rengi tanımlandı. Yerel test, kampanya, duyuru ve tatil bildirimleri aynı küçük simgeyi, büyük simge olarak mevcut renkli `app_logo` kaynağını kullanır. Dinamik logo kaynağı release resource shrinking için keep dosyasına alındı. Bildirim içerikleri, hedefleri, kanalları ve zamanlama mantığı değiştirilmedi. İlgili iki Dart dosyasının analizi temiz, seçili 47 test başarılı; debug APK derlemesi başarılı. Yeni simge yeni gelen bildirimlerle doğrulanmalıdır.

Son görünüm tercihi: Kullanıcı sağdaki büyük renkli logonun kaldırılmasını istedi. Yerel test, kampanya, duyuru ve tatil bildirimlerindeki `largeIcon` kaldırıldı; soldaki `ic_stat_rotalink` korunuyor. Büyük resimli bildirimlerin içerik görseli desteği değişmedi. Kaynak koruma dosyası artık yalnızca küçük simgeyi içeriyor.

## Görselli test bildirimi: metin ve kırpma düzeltmesi

Android `BigPictureStyle`, uzun açıklamayı sınırlı metin satırlarında gösteriyor ve dikey görselleri kırpabiliyor. Güncel Android 12+ debug test APK'sı, desteklediği düzeni `/device-test/fcm` isteğinde `notificationRenderer: 2` olarak bildirir. Yerel köprü hazır değilse, iOS'ta veya eski APK'da sürüm 1 korunur.

Debug kaynak setindeki `AdminTestMessagingService`, yalnızca eşleştirilmiş ve süresi dolmamış test oturumuna ait sürüm 2 verilerini gösterir. Genel kullanıcı servisi release manifestine eklenmez. Ön ve arka planda tek bildirim üretilir. Metin sarılır, kalan alan ölçülür ve görsel `fitCenter` ile tamamı görünerek sığdırılır. Yerleşim sistemin genişletilmiş bildirim alanına uyar; kompakt/başlık bildiriminin alanını Android belirler. Görsel alınamazsa boş alan yerine normal uzun metin şablonu kullanılır. Sağda ayrıca logo gösterilmez.

Görsel indirmesi yalnızca admin.rotalink.tr üzerindeki eşleştirme süresiyle korunan test görsellerinden yapılır; yönlendirme izlenmez, JPEG/PNG ve 1 MB sınırı korunur. Oturum köprüsü yalnızca kayıt kimliği ve bitiş tarihini saklar; FCM/bearer anahtarlarını kopyalamaz. Dokunma yükü mevcut Flutter bildirim callback'ini kullanır, hedef ve eşleşme tekrar doğrulanır; soğuk açılışta alındı olayının yazılmasını beklemek gerekmez.

Admin projesinde `0008_device_notification_renderer.sql` tek, varsayılanı 1 olan bir sütun ekler. Yalnızca Android olup sürüm 2 bildiren test telefonuna data-only yük gönderilir. Diğer telefonlar ve iOS aynı eski yükü alır. Genel bildirim gönderim yolu, LIVE_WRITES_ENABLED ve DNS değişmez. Bu not yazılırken migration yalnızca yerel test veritabanına uygulanmıştır; canlı yükleme ayrıca onay bekler.

Doğrulama: Android debug derlemesi başarılı; telefon verileri korunarak APK güncellendi. Native test servisi kurulu, yalnızca güncel ve süresi dolmamış eşleştirme kaydıyla yapılandırılmış. Üç ilgili Dart dosyası için analiz temiz, 17 Flutter testi geçti. Admin derlemesi ve 145 test başarılı; yerel HTTP/D1/R2 üzerinde 27 senaryo geçti. Gerçek yeni FCM yükü ve görselin telefondaki son görünümü, canlı test sunucusu güncellemesi ardından kullanıcı onayıyla denenecek; henüz yeni bir gerçek bildirim gönderilmedi.

Kullanıcı canlı test güncellemesini onayladı. Şifreli test tablosu yedeği doğrulandı, 0008 canlıya uygulandı ve Worker e27ac24c-b8a3-4c2a-8419-dbb9159f74bd yüklendi. Telefon yeniden açıldı; sunucuda Android cihazın `notification_renderer=2`, `fcm_ready=1` kaydı doğrulandı. Genel gönderim/yazım kilidi kapalı, cron boş. Beş ek yerel D1 yetenek kontrolü başarılı. Yeni görselli gerçek gönderim henüz yapılmadı; telefondaki nihai görünüm kullanıcının paneldeki son gönderim onayından sonra doğrulanacak.
