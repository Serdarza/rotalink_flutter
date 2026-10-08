/// rotalink.tr web adresleriyle aynı slug kuralı (web: `slugifyCity`).
///
/// Türkçe harfler küçültmeden önce Latin karşılığına çevrilir; aksi halde
/// "İ" küçültülünce görünmez birleşik nokta (U+0307) üretir.
String rotalinkSlug(String value) {
  final buf = StringBuffer();
  for (final rune in value.trim().runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_trMap[ch] ?? ch);
  }
  return buf
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'[âàáä]'), 'a')
      .replaceAll(RegExp(r'[êèéë]'), 'e')
      .replaceAll(RegExp(r'[îìíï]'), 'i')
      .replaceAll(RegExp(r'[ôòóõ]'), 'o')
      .replaceAll(RegExp(r'[ûùú]'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

const Map<String, String> _trMap = {
  'ç': 'c', 'Ç': 'c',
  'ğ': 'g', 'Ğ': 'g',
  'ı': 'i', 'I': 'i', 'İ': 'i',
  'ö': 'o', 'Ö': 'o',
  'ş': 's', 'Ş': 's',
  'ü': 'u', 'Ü': 'u',
};

/// Web paylaşım linki: `https://rotalink.tr/tesis/<il>/<tesis>/`.
String facilityWebUrl({required String il, required String isim}) =>
    'https://rotalink.tr/tesis/${rotalinkSlug(il)}/${rotalinkSlug(isim)}/';

enum DeepLinkKind { home, city, facility, holidays }

/// Web'deki butonun uygulama karşılığı: `?eylem=ara` arar, `?eylem=konum` haritayı açar.
enum DeepLinkAction {
  none,
  call,
  map;

  static DeepLinkAction parse(String? raw) {
    switch (raw) {
      case 'ara':
        return DeepLinkAction.call;
      case 'konum':
        return DeepLinkAction.map;
      default:
        return DeepLinkAction.none;
    }
  }
}

/// rotalink.tr / `rotalink://open` linkinden çıkarılan uygulama hedefi.
class DeepLinkTarget {
  const DeepLinkTarget._(
    this.kind,
    this.path, {
    this.citySlug,
    this.facilitySlug,
    this.action = DeepLinkAction.none,
    this.mapQuery,
  });

  final DeepLinkKind kind;

  /// Analytics için normalize yol (ör. `/tesis/kayseri/kayseri-ogretmenevi`).
  final String path;
  final String? citySlug;
  final String? facilitySlug;
  final DeepLinkAction action;

  /// `eylem=konum` ile gelen serbest arama (gezi / yemek). Tesis bulunursa kullanılmaz.
  final String? mapQuery;

  static const Set<String> webHosts = {'rotalink.tr', 'www.rotalink.tr'};
  static const String appScheme = 'rotalink';

  /// Tek segmentli yollar şehir sayılmaz (web sayfaları).
  static const Set<String> _reservedSingleSegments = {
    'indir', 'iletisim', 'blog', 'kampanyalar', 'favoriler', 'hakkimizda',
    'sik-sorulan-sorular', 'gizlilik-politikasi', 'kullanim-sartlari',
    'cerez-politikasi', 'sehir', 'tesis',
  };

  /// Rotalink'e ait değilse null.
  static DeepLinkTarget? fromUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https' || scheme == 'http') {
      if (!webHosts.contains(uri.host.toLowerCase())) return null;
      return fromPath(_pathWithQuery(uri.path, uri));
    }
    if (scheme == appScheme) {
      final host = uri.host.toLowerCase();
      // rotalink://open/sehir/kayseri  veya  rotalink://sehir/kayseri
      final path = (host.isEmpty || host == 'open') ? uri.path : '/$host${uri.path}';
      return fromPath(_pathWithQuery(path, uri));
    }
    return null;
  }

  static String _pathWithQuery(String path, Uri uri) {
    if (!uri.hasQuery) return path;
    return '$path?${uri.query}';
  }

  static DeepLinkTarget fromPath(String rawPath) {
    String? eylem;
    String? mapQuery;
    final qMark = rawPath.indexOf('?');
    if (qMark >= 0) {
      final query = rawPath.substring(qMark + 1).split('#').first;
      try {
        final params = Uri.splitQueryString(query);
        eylem = params['eylem'];
        final q = params['q']?.trim();
        if (q != null && q.isNotEmpty) mapQuery = q;
      } catch (_) {}
    }
    var pathOnly = qMark >= 0 ? rawPath.substring(0, qMark) : rawPath;
    final hash = pathOnly.indexOf('#');
    if (hash >= 0) pathOnly = pathOnly.substring(0, hash);
    final segs = pathOnly
        .split('/')
        .where((s) => s.isNotEmpty)
        .map((s) {
          try {
            return Uri.decodeComponent(s);
          } catch (_) {
            return s;
          }
        })
        .map(rotalinkSlug)
        .where((s) => s.isNotEmpty)
        .toList();

    final action = DeepLinkAction.parse(eylem);
    if (segs.length >= 2 && segs[0] == 'sehir') {
      return DeepLinkTarget._(
        DeepLinkKind.city,
        '/sehir/${segs[1]}',
        citySlug: segs[1],
        action: action,
        mapQuery: mapQuery,
      );
    }
    if (segs.length >= 2 && segs[0] == 'tesis') {
      if (segs.length >= 3) {
        return DeepLinkTarget._(
          DeepLinkKind.facility,
          '/tesis/${segs[1]}/${segs[2]}',
          citySlug: segs[1],
          facilitySlug: segs[2],
          action: action,
          mapQuery: mapQuery,
        );
      }
      return DeepLinkTarget._(
        DeepLinkKind.city,
        '/sehir/${segs[1]}',
        citySlug: segs[1],
        action: action,
        mapQuery: mapQuery,
      );
    }
    if (segs.length == 1 && segs[0] == 'resmi-tatiller') {
      return const DeepLinkTarget._(DeepLinkKind.holidays, '/resmi-tatiller');
    }
    if (segs.length == 1 && !_reservedSingleSegments.contains(segs[0])) {
      return DeepLinkTarget._(
        DeepLinkKind.city,
        '/${segs[0]}',
        citySlug: segs[0],
        action: action,
        mapQuery: mapQuery,
      );
    }
    return DeepLinkTarget._(DeepLinkKind.home, '/', action: action, mapQuery: mapQuery);
  }

  @override
  String toString() => 'DeepLinkTarget($kind, $path)';
}
