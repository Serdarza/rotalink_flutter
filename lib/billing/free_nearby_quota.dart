import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hesapsız yakın aramanın bu ay kullanılan noktaları.
///
/// Anahtarlar harita ekranıyla ortaktır. Aynı nokta yeniden hak yemez.
abstract final class FreeNearbyQuota {
  static const monthKey = 'rotalink_free_nearby_month';
  static const cellKey = 'rotalink_free_nearby_cell';
  static const cellsKey = 'rotalink_free_nearby_cells';

  static final revision = ValueNotifier<int>(0);

  /// Sunucunun son bildirdiği kalan yakın arama. Hesap yoksa null.
  static final serverRemaining = ValueNotifier<int?>(null);

  static void rememberServer(int? remaining) {
    if (remaining == null || remaining < 0) return;
    serverRemaining.value = remaining;
  }

  static String istanbulMonth() {
    final ist = DateTime.now().toUtc().add(const Duration(hours: 3));
    final month = ist.month.toString().padLeft(2, '0');
    return '${ist.year}-$month';
  }

  static String cell(double latitude, double longitude) =>
      '${(latitude * 100).round()}:${(longitude * 100).round()}';

  static List<String> cellsThisMonth(SharedPreferences prefs) {
    if (prefs.getString(monthKey) != istanbulMonth()) return const [];
    final raw = prefs.getString(cellsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return [
            for (final item in decoded)
              if (item is String && item.isNotEmpty) item,
          ];
        }
      } catch (_) {}
    }
    final single = prefs.getString(cellKey);
    if (single != null && single.isNotEmpty) return [single];
    return const [];
  }

  static Future<int> usedCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return cellsThisMonth(prefs).length;
    } catch (_) {
      return 0;
    }
  }

  static void changed() => revision.value += 1;
}
