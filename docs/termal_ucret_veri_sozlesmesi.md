# Termal ücret verisi

Ücretler mevcut `assets/data/kis_kesfet.json` dosyasında ilgili termal kaydının
`ucretBilgisi` alanındadır. Diğer tesis alanları ve kayak kayıtları değişmez.
Alan isteğe bağlıdır; eski GitHub yayınları okunmaya devam eder.

- `sonKontrol`: Gerçek araştırma tarihi, ISO `YYYY-MM-DD`. Tesisin genel
  `sonDogrulama` alanından bağımsızdır; arayüzde `dd.MM.yyyy` gösterilir.
- `arastirmaYili`: Araştırmanın hedef yılıdır, tarifenin o yıl geçerli olduğuna
  dair tek başına kanıt değildir.
- `aciklama`: Kullanıcıya gösterilen, resmî tarifedeki hizmet ve kullanım
  koşulları. Araştırma süreci veya bulunamayan fiyatlarla ilgili metin içermez.
- `arastirmaNotu`: Tarife yılı belirsizliği, kaynağın çelişkisi veya fiyat
  bulunamama nedeni gibi araştırma notları; arayüzde gösterilmez.
- `kaynaklar`: İncelenen resmî tesis/kurum sayfaları. Eski ruhsat/tanıtım sayfası
  ücret kanıtı değildir; sayısal tarife bulunamadıysa `kalemler` boştur.
- `kalemler`: `tur`, `ad`, sayısal `tutar` (TL), `birim`, `kaynakUrl`, `kosul`,
  `baslangic`, isteğe bağlı `gecerlilikBitis` alanlarından oluşur.
- `tur`: `giris`, `havuz`, `aileBanyosu` veya `konaklama`.
- `baslangic`: Kartta kullanılabilecek tam hizmet bedellerinde `true`.
  Çocuk, mensup indirimi, ek yatak, ilave kişi ve yalnız konaklayanlara sunulan
  ücretler bu karşılaştırmaya katılmaz. Başvuruya bağlı ücretsiz sosyal hizmette
  koşul mutlaka kartta gösterilir. En düşük uygun ücret kendi türü ve birimiyle
  sunulur; kişi/oda/gece fiyatları birbirine dönüştürülmez.
- `gecerlilikBitis`: ISO tarih; süresi biten kalem arayüzde gösterilmez.

24.10.2026 araştırmasında Yalova konaklama tarifesinde 2026 yılı, Eynal apart
tarifesinde 30.12.2026 son geçerlilik tarihi açıktır. Diğer yayımlanmış fiyatlarda
yıl/yürürlük tarihi belirtilmiyorsa bu belirsizlik araştırma notunda korunur; bu fiyatlar
ayrıca doğrulanmış bir **2026 tarifesi** olarak etiketlenmez. Bingöl'ün çelişen
havuz tarifeleri ve Aziziye sitesindeki `0,00 TL` yer tutucu fiyat kabul edilmez.

Eksik ücret türleri ve ücret bulunamayan tesislerin ücret bölümleri arayüzde
gösterilmez. Ücret bulunamaması hizmetin bulunmadığı veya ücretsiz olduğu
anlamına gelmez. Kaynaklar ve kalemlerin kanıt bağlantıları veride saklanır;
arayüzde yalnız detay sayfasının sonundaki “Resmî kaynak” düğmesi gösterilir.

## GitHub uyumluluğu

`KisKesfetRepository.mergeById` ücret alanı eksik veya kontrol tarihi daha eski
uzak kayıtta yerel ücret araştırmasını korur; diğer uzak tesis bilgileri normal
şekilde güncellenir. Yeni tarihli geçerli tarife kabul edilir. Yeni tarihli ve
açıkça boş `kalemler: []` kaydı bir ücret bilgisinin artık doğrulanamadığını
ifade ederek eski fiyatları kaldırabilir. Bozuk tarih/tutar/kaynak şeması geçerli
tarife sayılmaz.

Veri reposundaki mevcut tarayıcı yalnız `sonDogrulama` alanını güncelliyor ve
birleştirici ek JSON alanlarını koruyor. Bu çalışma iş akışı dosyalarını,
zamanlamalarını ve fiyat/misafirhane verisini değiştirmez. GitHub'a ücretler
yayınlanırken aynı `ucretBilgisi` alanı hem `kis_kesfet/data/termal.json` içindeki
tesis kayıtlarına hem üretilen `kis_kesfet/data/kis_kesfet.json` dosyasına
aktarılmalıdır; tarayıcının genel tesis kontrolü ücret araştırma tarihini
otomatik olarak ilerletmemelidir.
