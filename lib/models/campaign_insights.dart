import 'package:flutter/material.dart';

import 'campaign.dart';

/// Keşfet filtresindeki kamu personeli grupları.
enum CampaignAudience {
  teacher('Öğretmen', Icons.school_outlined),
  health('Sağlık', Icons.nightlight_outlined),
  police('Emniyet', Icons.local_police_outlined),
  military('TSK', Icons.military_tech_outlined),
  gendarmerie('Jandarma', Icons.shield_outlined),
  academic('Akademisyen', Icons.account_balance_outlined),
  municipal('Belediye', Icons.location_city_outlined),
  publicGeneral('Tüm Kamu', Icons.badge_outlined);

  const CampaignAudience(this.label, this.icon);

  final String label;
  final IconData icon;

  static CampaignAudience? byName(String? name) {
    for (final a in values) {
      if (a.name == name) return a;
    }
    return null;
  }
}

/// Kampanya kartı/filtre için metinden türetilen bilgiler (veri şemasına alan eklemez).
class CampaignInsights {
  CampaignInsights._({
    required this.audiences,
    required this.maxDiscountPercent,
    required this.endDate,
    required this.createdAt,
  });

  /// Kampanyanın hitap ettiği gruplar. [CampaignAudience.publicGeneral] tüm kamu personelini kapsar.
  final Set<CampaignAudience> audiences;
  final int? maxDiscountPercent;

  /// Bitiş günü (yerel tarih, saatsiz).
  final DateTime? endDate;
  final DateTime? createdAt;

  static final Expando<CampaignInsights> _cache = Expando<CampaignInsights>();

  static CampaignInsights of(Campaign c) =>
      _cache[c] ??= CampaignInsights._fromCampaign(c);

  /// Bu gruba seçilen kullanıcı kampanyayı görmeli mi? Genel kamu kampanyaları her grupta görünür.
  bool matches(CampaignAudience a) =>
      audiences.contains(a) ||
      audiences.contains(CampaignAudience.publicGeneral);

  bool isNew(DateTime now) {
    final t = createdAt;
    if (t == null) return false;
    final diff = now.difference(t.toLocal());
    return !diff.isNegative && diff.inDays < 7;
  }

  /// Bitişe kalan gün (bugün = 0). Tarih yoksa null.
  int? daysLeft(DateTime now) {
    final end = endDate;
    if (end == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return end.difference(today).inDays;
  }

  factory CampaignInsights._fromCampaign(Campaign c) {
    final text = '${c.title}\n${c.summary}';
    return CampaignInsights._(
      audiences: _audiences(c),
      maxDiscountPercent: _maxDiscount(text),
      endDate: _endDate(text),
      createdAt: c.createdAt,
    );
  }

  // ---------------------------------------------------------------- kitle

  static const Map<String, CampaignAudience> _tagMap = {
    'ogretmen': CampaignAudience.teacher,
    'saglik calisani': CampaignAudience.health,
    'hekim': CampaignAudience.health,
    'hemsire': CampaignAudience.health,
    'emniyet': CampaignAudience.police,
    'tsk': CampaignAudience.military,
    'jandarma': CampaignAudience.gendarmerie,
    'sahil guvenlik': CampaignAudience.gendarmerie,
    'akademisyen': CampaignAudience.academic,
    'belediye personeli': CampaignAudience.municipal,
    'kamu personeli': CampaignAudience.publicGeneral,
    'memur': CampaignAudience.publicGeneral,
    'kamu iscisi': CampaignAudience.publicGeneral,
  };

  static final Map<CampaignAudience, RegExp> _textPatterns = {
    CampaignAudience.teacher: RegExp(
      r'ogretmen|meb (personel|calisan|mensup)|milli egitim bakanligi(na bagli| personel)|egitim (calisan|personel)',
    ),
    CampaignAudience.health: RegExp(
      r'saglik (calisan|personel|mensup)|saglik bakanligi(nin)? (personel|calisan)|hekimlere|doktorlara|hemsire|tabip odasi',
    ),
    CampaignAudience.police: RegExp(
      r'\bpolis|emniyet (mensup|personel|teskilat|calisan)',
    ),
    CampaignAudience.military: RegExp(
      r'\btsk\b|silahli kuvvet|\basker|\bsubay|astsubay|msb (personel|calisan)|milli savunma bakanligi|\boyak\b',
    ),
    CampaignAudience.gendarmerie: RegExp(r'jandarma|sahil guvenlik'),
    CampaignAudience.academic: RegExp(
      r'akademisyen|ogretim (uye|gorevli|eleman)|universite (personel|calisan)',
    ),
    CampaignAudience.municipal: RegExp(
      r'belediye(si|leri)? (personel|calisan)|\bibb (personel|calisan)|zabita',
    ),
    CampaignAudience.publicGeneral: RegExp(
      r'kamu (personel|calisan|gorevli)|devlet memur|\bmemurlar|kamu isci',
    ),
  };

  static Set<CampaignAudience> _audiences(Campaign c) {
    final fromTags = <CampaignAudience>{};
    for (final t in c.tags) {
      final a = _tagMap[foldTr(t)];
      if (a != null) fromTags.add(a);
    }
    // Otomatik kayıtlarda etiketler kaynaktan doğrulanmış kitleyi taşır; "diş hekimi" gibi
    // hizmet adlarının kitle sanılmaması için metne yalnızca etiket yoksa bakılır.
    if (fromTags.isNotEmpty) return fromTags;

    final title = foldTr(c.title);
    final fromTitle = {
      for (final e in _textPatterns.entries)
        if (e.value.hasMatch(title)) e.key,
    };
    if (fromTitle.isNotEmpty) return fromTitle;
    final body = foldTr(c.summary);
    return {
      for (final e in _textPatterns.entries)
        if (e.value.hasMatch(body)) e.key,
    };
  }

  // ---------------------------------------------------------------- indirim

  static final RegExp _pctBefore = RegExp(r'%\s?(\d{1,3})(?![\d\w])');
  static final RegExp _pctAfter = RegExp(r'(?<![\w.,])(\d{1,3})\s?%(?!\w)');

  static int? _maxDiscount(String text) {
    int? best;
    for (final re in [_pctBefore, _pctAfter]) {
      for (final m in re.allMatches(text)) {
        final v = int.tryParse(m.group(1)!);
        if (v != null && v > 0 && v <= 100 && (best == null || v > best)) {
          best = v;
        }
      }
    }
    return best;
  }

  // ---------------------------------------------------------------- bitiş

  static const _months = {
    'ocak': 1,
    'subat': 2,
    'mart': 3,
    'nisan': 4,
    'mayis': 5,
    'haziran': 6,
    'temmuz': 7,
    'agustos': 8,
    'eylul': 9,
    'ekim': 10,
    'kasim': 11,
    'aralik': 12,
  };
  static final RegExp _numericDate = RegExp(
    r'\b(\d{1,2})[./](\d{1,2})[./](\d{4})\b',
  );
  static final RegExp _namedDate = RegExp(
    r'\b(\d{1,2})\s+(ocak|subat|mart|nisan|mayis|haziran|temmuz|agustos|eylul|ekim|kasim|aralik)\s+(\d{4})\b',
  );
  static final RegExp _endContext = RegExp(
    r'kadar|son gun|bitis|arasinda|gecerli|sona er',
  );

  /// Metinde bitiş bağlamı varsa geçen en geç tarih (ör. "31.12.2026 tarihine kadar").
  static DateTime? _endDate(String text) {
    final t = foldTr(text);
    if (!_endContext.hasMatch(t)) return null;
    DateTime? best;
    void consider(int d, int m, int y) {
      if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) return;
      final dt = DateTime(y, m, d);
      if (dt.month != m) return;
      if (best == null || dt.isAfter(best!)) best = dt;
    }

    for (final m in _numericDate.allMatches(t)) {
      consider(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }
    for (final m in _namedDate.allMatches(t)) {
      consider(
        int.parse(m.group(1)!),
        _months[m.group(2)!]!,
        int.parse(m.group(3)!),
      );
    }
    return best;
  }
}

/// Türkçe küçük harf + ASCII katlama ("Öğretmen" → "ogretmen").
String foldTr(String s) {
  const map = {
    'İ': 'i',
    'I': 'i',
    'ı': 'i',
    'Ç': 'c',
    'ç': 'c',
    'Ğ': 'g',
    'ğ': 'g',
    'Ö': 'o',
    'ö': 'o',
    'Ş': 's',
    'ş': 's',
    'Ü': 'u',
    'ü': 'u',
    'Â': 'a',
    'â': 'a',
    'Î': 'i',
    'î': 'i',
  };
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(map[ch] ?? ch.toLowerCase());
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
