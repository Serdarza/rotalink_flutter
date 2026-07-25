import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

/// Uygulamayla birlikte gelen gömülü yedek veritabanı.
///
/// İlk kurulumda uzak (GitHub) master JSON bozuk veya erişilemez olduğunda
/// arama ekranının boş kalmaması için kullanılır. Sürüm yükseltmelerinde
/// `assets/data/master_database_updated.json` güncel tutulmalıdır.
abstract final class RotaBundledData {
  static const assetPath = 'assets/data/master_database_updated.json';

  static String? _cache;

  /// Gömülü JSON metnini döner (bir kez okunup bellekte tutulur).
  static Future<String?> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final text = await rootBundle.loadString(assetPath);
      if (text.trim().isEmpty) return null;
      return _cache = text;
    } catch (e) {
      debugPrint('[RotaBundledData] gömülü veri okunamadı: $e');
      return null;
    }
  }
}
