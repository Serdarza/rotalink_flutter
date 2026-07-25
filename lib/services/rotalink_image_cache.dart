import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Konaklama / gezi / yemek görselleri — tek paylaşılan disk önbelleği.
abstract final class RotalinkImageCache {
  /// v4: Pexels `fm=jpg` + AVIF Accept yasak (decode hatası).
  static const cacheKey = 'rotalink_media_v4';

  static final CacheManager manager = CacheManager(
    Config(
      cacheKey,
      stalePeriod: const Duration(days: 180),
      maxNrOfCacheObjects: 12000,
    ),
  );

  static const int diskCacheMaxEdge = 1280;

  /// Flutter'ın güvenilir decode ettiği türler — avif/webp istemiyoruz.
  static const Map<String, String> httpHeaders = {
    'User-Agent': 'RotalinkFlutter/1.0 (https://rotalink.tr)',
    'Accept': 'image/jpeg,image/png,*/*;q=0.1',
  };

  static Map<String, String> headersForUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.contains('pexels.com')) {
      return {
        ...httpHeaders,
        'Referer': 'https://www.pexels.com/',
      };
    }
    if (host.contains('wikimedia.org') || host.contains('wikipedia.org')) {
      return {
        ...httpHeaders,
        // Wikimedia bot politikası: tanımlı UA ister.
        'User-Agent':
            'RotalinkFlutter/1.0 (https://rotalink.tr; gezi-gorsel)',
      };
    }
    return httpHeaders;
  }

  /// Pexels imgix: `fm=jpg` ile AVIF/WebP müzakeresini kapatır.
  static String normalizeUrl(String raw) {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return trimmed;
    if (!uri.host.toLowerCase().contains('pexels.com')) return trimmed;

    final q = Map<String, String>.from(uri.queryParameters);
    q['fm'] = 'jpg';
    q.putIfAbsent('auto', () => 'compress');
    q.putIfAbsent('cs', () => 'tinysrgb');
    // Çok büyük dosya indirmeyi sınırla.
    q['w'] = q['w'] ?? '960';
    return uri.replace(queryParameters: q).toString();
  }
}
