import '../models/misafirhane.dart';
import '../utils/search_normalize.dart';

/// Bir grubun tesiste konaklama durumu.
enum StayAccess {
  /// Doğrudan kalabilir.
  allowed,

  /// Yer durumu, referans veya izin gibi şarta bağlı.
  conditional,

  /// Kural olarak kalamaz.
  notAllowed,
}

class StayGroup {
  const StayGroup(this.title, this.detail, this.access);

  final String title;
  final String detail;
  final StayAccess access;
}

class FacilityStayRule {
  const FacilityStayRule({
    required this.authority,
    required this.groups,
    required this.howTo,
    required this.civilAccess,
  });

  /// Bağlı olduğu kurum (ör. "Millî Eğitim Bakanlığı").
  final String authority;
  final List<StayGroup> groups;

  /// "Nasıl kalınır?" adımları.
  final List<String> howTo;

  /// Başlık rozetinde gösterilen sivil vatandaş durumu.
  final StayAccess civilAccess;
}

/// Kamu Sosyal Tesislerine İlişkin Tebliğ (2026/1) ve kurum yönetmeliklerine
/// göre tesis tipinden genel konaklama kuralı. Tesise özel istisnalar olabilir.
abstract final class FacilityStayRules {
  static const disclaimer =
      'Genel kurallardır; tesise ve doluluğa göre değişebilir. '
      'Rezervasyondan önce tesisi arayarak teyit edin.';

  static FacilityStayRule forFacility(Misafirhane m) {
    final tip = normalizeForSearch(m.tip);
    final isim = normalizeForSearch(m.isim);
    bool has(String k) => tip.contains(k) || (tip.isEmpty && isim.contains(k));
    bool hasAny(List<String> ks) => ks.any(has);

    if (has('ogretmen')) return _ogretmenevi;
    if (has('polis')) return _polisevi;
    if (hasAny(const ['ordu', 'jandarma', 'msb', 'askeri'])) return _orduevi;
    if (hasAny(const ['hakim', 'adalet', 'adliye', 'sayistay'])) {
      return _hakimevi;
    }
    if (hasAny(const ['uygulamaotel', 'okulotel', 'universiteotel'])) {
      return _uygulamaOteli;
    }
    if (hasAny(const ['hekim', 'saglik', 'hastane'])) return _hekimevi;
    if (has('universite')) return _universite;
    if (has('belediye')) return _belediye;
    if (hasAny(const [
      'sendika',
      'vakf',
      'vakif',
      'dernek',
      'birlig',
      'yol-is',
    ])) {
      return _uyelik;
    }
    return _kurumMisafirhanesi(_institutionName(m.tip));
  }

  static String? _institutionName(String tip) {
    var t = tip.trim();
    for (final suffix in const [
      'Misafirhanesi',
      'Misafirhane',
      'Sosyal Tesisleri',
      'Sosyal Tesisi',
      'Dinlenme Tesisi',
      'Kamp Misafirhanesi',
      'Konukevi',
      'Konuk Evi',
    ]) {
      if (t.endsWith(suffix)) {
        t = t.substring(0, t.length - suffix.length).trim();
        break;
      }
    }
    const generic = {'', 'kamu', 'sosyal tesis', 'konuk', 'bakanlık'};
    return generic.contains(t.toLowerCase()) ? null : t;
  }

  static const _ogretmenevi = FacilityStayRule(
    authority: 'Millî Eğitim Bakanlığı',
    civilAccess: StayAccess.allowed,
    groups: [
      StayGroup(
        'Eğitim çalışanları',
        'Görevdeki ve emekli öğretmenler, MEB personeli ile eş, çocuk, anne '
            've babaları. Öncelikli ve en indirimli tarife.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Diğer kamu personeli',
        'Memurlar ve kamu işçileri kurum kimliğiyle kamu tarifesinden kalır.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Sivil vatandaşlar',
        'Referans gerekmez. Boş yer varsa doğrudan rezervasyonla sivil '
            'tarifeden kalınır.',
        StayAccess.allowed,
      ),
    ],
    howTo: [
      'Tesisi arayıp tarih ve oda durumunu sorun.',
      'Girişte nüfus cüzdanı; indirim için kurum kimliği veya emekli kartı '
          'gösterin.',
      'Yaz ve bayram dönemlerinde erken rezervasyon yapın.',
    ],
  );

  static const _polisevi = FacilityStayRule(
    authority: 'Emniyet Genel Müdürlüğü',
    civilAccess: StayAccess.conditional,
    groups: [
      StayGroup(
        'Emniyet mensupları',
        'Görevdeki ve emekli polisler, bekçiler, emniyet sivil personeli ile '
            'anne, baba, eş, çocuk, gelin ve damatları. En düşük tarife.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Diğer kamu personeli',
        'Kurum kimliğiyle, yer durumuna göre kamu tarifesinden kalınır.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Sivil vatandaşlar',
        'Yalnızca "onaylı misafir" olarak: bir emniyet mensubunun referans '
            'dilekçesi ve kimlik fotokopisi gerekir. En yüksek tarife.',
        StayAccess.conditional,
      ),
    ],
    howTo: [
      'Mensuplar teşkilat kimliği veya sosyal tesis giriş kartıyla doğrudan '
          'başvurur.',
      'Siviller, referans olacak emniyet personelinin dilekçesi ve kurum '
          'kimlik fotokopisiyle tesis müdürlüğüne başvurur.',
      'Onay tesis yönetimine ve oda müsaitliğine bağlıdır.',
    ],
  );

  static const _orduevi = FacilityStayRule(
    authority: 'Türk Silahlı Kuvvetleri',
    civilAccess: StayAccess.notAllowed,
    groups: [
      StayGroup(
        'TSK ve Jandarma personeli',
        'Görevdeki ve emekli subay, astsubay, uzman erbaş ve sözleşmeli '
            'personel. Tesis kategorisine göre (subay / astsubay) ayrılabilir.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Hak sahibi yakınlar',
        'Eş, bakmakla yükümlü olunan çocuklar ve kayıtlı anne-babalar; '
            'giriş kartıyla.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Şehit ve gazi yakınları',
        'Şehitlerin dul ve yetimleri, vazife malulleri ve gaziler.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Diğer kamu personeli',
        'Kural olarak konaklayamaz; yalnızca garnizon izniyle istisnai durumlar.',
        StayAccess.notAllowed,
      ),
      StayGroup(
        'Sivil vatandaşlar',
        'Sivil vatandaşlar askerî tesislerde konaklayamaz.',
        StayAccess.notAllowed,
      ),
    ],
    howTo: [
      'Askerî kimlik kartı, emekli kimliği veya orduevi giriş kartı gerekir.',
      'Rezervasyon için tesisi arayıp hak sahipliğinizi belirtin.',
    ],
  );

  static const _hakimevi = FacilityStayRule(
    authority: 'Adalet Bakanlığı / Yargı',
    civilAccess: StayAccess.conditional,
    groups: [
      StayGroup(
        'Yargı mensupları',
        'Hâkim, savcı ve adalet personeli ile aileleri öncelikli ve indirimli '
            'kalır.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Diğer kamu personeli',
        'Kurum kimliğiyle, yer durumuna göre kamu tarifesinden.',
        StayAccess.conditional,
      ),
      StayGroup(
        'Sivil vatandaşlar',
        'Tesise göre değişir; çoğunda bir mensubun referansı veya yönetim '
            'onayı istenir.',
        StayAccess.conditional,
      ),
    ],
    howTo: [
      'Tesisi arayıp sivil veya kamu kabulü olup olmadığını sorun.',
      'Girişte kimlik ve varsa kurum kimliği gösterin.',
    ],
  );

  static const _hekimevi = FacilityStayRule(
    authority: 'Sağlık Bakanlığı / İl Sağlık Müdürlüğü',
    civilAccess: StayAccess.conditional,
    groups: [
      StayGroup(
        'Sağlık personeli',
        'Hekimler ve sağlık çalışanları ile yakınları öncelikli ve indirimli.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Diğer kamu personeli',
        'Geçici görevli ve diğer memurlar kurum kimliğiyle kalabilir.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Sivil vatandaşlar',
        'Boş yer varsa sivil tarifeden; hasta yakınlarına öncelik tanınabilir.',
        StayAccess.conditional,
      ),
    ],
    howTo: [
      'Tesisi arayıp oda durumunu ve sivil kabulünü sorun.',
      'Girişte kimlik; indirim için kurum kimliği gösterin.',
    ],
  );

  static const _uygulamaOteli = FacilityStayRule(
    authority: 'Üniversite / MEB (eğitim amaçlı otel)',
    civilAccess: StayAccess.allowed,
    groups: [
      StayGroup(
        'Herkes',
        'Öğrencilerin staj yaptığı, otel gibi işletilen tesislerdir; herkese '
            'açıktır.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Kurum personeli',
        'Üniversite / okul personeline indirim uygulanabilir.',
        StayAccess.allowed,
      ),
    ],
    howTo: [
      'Telefonla veya varsa web sitesinden rezervasyon yapın.',
      'Girişte nüfus cüzdanı yeterlidir.',
    ],
  );

  static const _universite = FacilityStayRule(
    authority: 'Üniversite',
    civilAccess: StayAccess.conditional,
    groups: [
      StayGroup(
        'Üniversite personeli',
        'Akademik ve idari personel, misafir akademisyenler ve aileleri '
            'öncelikli.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Diğer kamu personeli',
        'Geçici görevli ve diğer memurlar kurum kimliğiyle kalabilir.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Sivil vatandaşlar',
        'Birçok konukevi boş yer varsa sivilleri kabul eder; tesise göre '
            'değişir.',
        StayAccess.conditional,
      ),
    ],
    howTo: [
      'Konukevini arayıp sivil kabulünü ve tarifeyi sorun.',
      'Girişte kimlik; indirim için kurum kimliği gösterin.',
    ],
  );

  static const _belediye = FacilityStayRule(
    authority: 'Belediye',
    civilAccess: StayAccess.allowed,
    groups: [
      StayGroup(
        'Herkes',
        'Belediye misafirhaneleri genellikle tüm vatandaşlara açıktır.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Belediye personeli / ilçe halkı',
        'Bazı tesislerde indirim veya öncelik uygulanabilir.',
        StayAccess.allowed,
      ),
    ],
    howTo: [
      'Tesisi arayarak rezervasyon yapın.',
      'Girişte nüfus cüzdanı yeterlidir.',
    ],
  );

  static const _uyelik = FacilityStayRule(
    authority: 'Sendika / Vakıf / Dernek',
    civilAccess: StayAccess.conditional,
    groups: [
      StayGroup(
        'Üyeler',
        'Üyeler ve aileleri öncelikli ve indirimli kalır.',
        StayAccess.allowed,
      ),
      StayGroup(
        'Kamu personeli',
        'Yer durumuna göre kabul edilebilir.',
        StayAccess.conditional,
      ),
      StayGroup(
        'Sivil vatandaşlar',
        'Tesise göre değişir; boş yer varsa kabul edenler vardır.',
        StayAccess.conditional,
      ),
    ],
    howTo: [
      'Tesisi arayıp üye olmayanların kabulünü sorun.',
      'Üyeler girişte üyelik belgesi göstermelidir.',
    ],
  );

  static FacilityStayRule _kurumMisafirhanesi(String? kurum) {
    final own = kurum == null ? 'Kurum personeli' : '$kurum personeli';
    return FacilityStayRule(
      authority: kurum ?? 'Kamu kurumu',
      civilAccess: StayAccess.conditional,
      groups: [
        StayGroup(
          own,
          'Misafirhanenin bağlı olduğu kurumun çalışanları, emeklileri ve '
          'aileleri öncelikli ve en uygun fiyatla kalır.',
          StayAccess.allowed,
        ),
        const StayGroup(
          'Geçici görevli memurlar',
          'Denetim, teftiş veya kurs için gelen her kurumdan memur, '
              'görevlendirme yazısıyla tebliğdeki tavan fiyatlardan kalabilir.',
          StayAccess.allowed,
        ),
        const StayGroup(
          'Diğer kamu personeli',
          'Kurum kimliğiyle, boş yer varsa kamu tarifesinden.',
          StayAccess.allowed,
        ),
        const StayGroup(
          'Sivil vatandaşlar',
          'Birçoğu boş yer varsa sivil tarifeden kabul eder; öncelik görevli '
              'kamu personelindedir.',
          StayAccess.conditional,
        ),
      ],
      howTo: const [
        'Misafirhaneyi doğrudan arayıp yer durumunu ve sivil kabulünü sorun.',
        'Geçici görevliler görevlendirme yazısını, diğer memurlar kurum '
            'kimliğini göstermelidir.',
        'Siviller girişte nüfus cüzdanı ibraz eder.',
      ],
    );
  }
}
