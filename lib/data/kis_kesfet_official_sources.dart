/// Rehber bağlantılarının yerine 24.10.2026 tarihinde kontrol edilen tesis veya
/// ilgili kamu kurumu sayfaları. GitHub'daki eski kayıtlar için de uygulanır.
abstract final class KisKesfetOfficialSources {
  static const thermalSources = <String, String>{
    'termal-afyon-afbel': 'https://www.afbeltermal.com/',
    'termal-afyon-gazligol': 'https://www.ihsaniye.gov.tr/termal-turizm',
    'termal-afyon-heybeli':
        'https://www.bolvadin.gov.tr/heybeli-kizil-kirse-kaplicasi',
    'termal-ankara-ayas-tbb':
        'https://www.barobirlik.org.tr/Haberler/turkiye-barolar-birligi-ayas-termal-yasam-merkezi-hizmete-girmistir-66928',
    'termal-ankara-soguksu':
        'https://kizilcahamam.bel.tr/TesisDetayi/SOGUKSU-OTEL/22',
    'termal-ankara-sifa': 'https://www.ankara.bel.tr/tesis/sifa-termal-tesisi',
    'termal-ankara-haymana-merkez':
        'https://www.haymana.bel.tr/tarihi-merkez/tarihi-haymana-kaplica-tesisleri/140',
    'termal-balikesir-eman': 'https://www.sindirgi.bel.tr/News/Detail/1454',
    'termal-bursa-gemlik':
        'https://www.burfas.com.tr/faaliyetlerimiz/gemlik-termal',
    'termal-izmir-balcova': 'https://www.balcovatermal.com/',
    'termal-kutahya-yoncali':
        'https://yoncali.meb.k12.tr/icerikler/yoncaliuygulamaoteliacildi_4206398.html',
  };

  static String resolveThermal(String id, String source) {
    final host = Uri.tryParse(source)?.host.toLowerCase() ?? '';
    if (host == 'kamutesisleri.com' || host.endsWith('.kamutesisleri.com')) {
      return thermalSources[id] ?? source;
    }
    // Uzaktan gelen yeni tesis/kurum bağlantılarını koru.
    return source;
  }
}
