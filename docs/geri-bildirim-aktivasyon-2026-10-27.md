# Geri bildirim aktivasyonu — 27.10.2026

## Doğrulanan neden

Flutter'daki ortak geri bildirim servisi `https://admin.rotalink.tr/public/feedback` adresine gönderiyor. Canlı sürüm bu adreste HTTP 405 dönüyordu. Geri bildirim sunucu kodu yerelde hazırdı, ancak canlı Worker'da gerekli iki gizli ayar ve etkinleştirme bayrağı yoktu.

## Tamamlananlar

- Kullanıcı ayrı Firebase hesabını, anahtarın Cloudflare'a aktarılmasını, admin yayınını ve tek etiketli deneme kaydını açıkça onayladı.
- `rotalink-admin-feedback@rotalink-d738c.iam.gserviceaccount.com` oluşturuldu.
- `projects/rotalink-d738c/roles/rotalinkFeedbackWriter`: yalnızca `datastore.entities.create/get/list/update` izinleri. IAM rolü hesaba atandı ve kaydedildi. FCM hesabı değiştirilmedi.
- Bir JSON anahtarı oluşturuldu: `rotalink-d738c-b516d694589e.json`. İçeriği kaynak koduna veya sohbet çıktısına yazılmadı. İndirmenin yerel dosya konumu henüz bulunamadı; kullanıcıdan yalnızca dosya yolu istendi. İkinci anahtar oluşturma girişimi otomatik denetimde reddedildi ve iptal edildi; ikinci anahtar oluşmadı.
- Mevcut yetkilerle Cloudflare OAuth oturumu yenilendi.
- D1 yedeği Windows DPAPI ile şifreli saklandı: kardeş admin projesinde `checks/backups/admin-before-feedback-20261027.dpapi`.
- Yalnızca `0009_feedback_limits.sql` canlı D1'e uygulandı. Mevcut içerik tabloları değiştirilmedi.
- `feedback_reports` için üç bileşik indeks oluşturuldu: status/createdAt, type/createdAt, status/type/createdAt. Üçünde de createdAt ve otomatik __name__ azalan. Son görülen durum: Building.
- Yerel üretim yapılandırmasına `FEEDBACK_ENABLED: "true"` eklendi; henüz dağıtılmadı.
- Flutter hata mesajları bağlantı kurulmamışsa doğru açıklama gösterir ve form verilerini korur.

## Kontroller

- Flutter geri bildirim servisi ve ilgili arayüz: 7 test geçti.
- Değişen Flutter dosyalarının analizi: sorun yok.
- Admin: 169 test geçti, 4 emülatör testi bu çalıştırmada atlandı.
- Admin üretim derlemesi başarılı.

## Kalan adımlar

1. İndirilen mevcut anahtar dosyasının yolunu kullanıcıdan al; proje/hesap/anahtar kimliğini içeriği loglamadan doğrula.
2. Mevcut anahtarı `FEEDBACK_SERVICE_ACCOUNT_JSON`, rastgele HMAC değerini `FEEDBACK_RATE_LIMIT_SECRET` gizli ayarlarına güvenli stdin ile aktar.
3. Üç Firestore indeksinin hazır olmasını doğrula.
4. Mevcut diğer üretim bayraklarını koruyarak admin Worker'ını yayınla.
5. Onaylanan tek etiketli deneme kaydını gönder; aynı ID ile tekrar denemede çoğalmadığını ve yetkili panelde göründüğünü doğrula.

## Sonuç — canlı aktivasyon tamamlandı

Yukarıdaki bekleyen adımlar tamamlandı. İndirme sorunu nedeniyle oluşturulan iki kullanılmamış anahtar iptal edildi. Son anahtar yerelde üretildi; Google'a yalnızca açık sertifika yüklendi. Özel anahtar DPAPI ile şifreli saklandı ve Cloudflare'a güvenli stdin aktarımıyla ulaştırıldı. Üç indeks Ready durumunda.

- Canlı Worker: `dd93fffd-7c3d-458a-93e8-ca61d0e7f934`.
- Tek deneme ID: `d07b65f2174e874109f7db7d3b675e5a4c65cc7f4db4fee04e06adca8f5c27d3`.
- Ortak gönderim adresi HTTP 201 accepted döndü. Aynı ID ile tekrar denendi; panelde tek kayıt kaldı.
- Yetkili admin ekranında kayıt görüldü, not eklendi ve Çözüldü durumu kaydedildi. Tür ve durum filtreleri çalıştı.
- Yetkisiz admin okuması 401, anonim doğrudan Firestore okuması 403, boş form 400 ile reddedildi.
- Son sertifika 27.10.2027 tarihinden önce yenilenmelidir. Ayrıntı ve şifreli yedek yolları kardeş admin projesinin `docs/feedback-activation.md` dosyasında.

Telefonun kendisindeki kullanıcı etkileşimi uzaktan sınanmadı; mevcut Flutter formlarının kullandığı canlı API ve yönetici ekranı doğrulandı. APK ve uygulama önizlemesi oluşturulmadı. FCM, mevcut veri kaynakları ve DNS değiştirilmedi.
