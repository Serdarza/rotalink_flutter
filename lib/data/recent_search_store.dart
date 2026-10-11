import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/search_normalize.dart';

class RecentSearchEntry {
  const RecentSearchEntry({required this.query, required this.at});

  final String query;
  final DateTime at;

  String get dateLabel {
    final day = at.day.toString().padLeft(2, '0');
    final month = at.month.toString().padLeft(2, '0');
    return '$day.$month.${at.year}';
  }
}

/// Ana sayfada gösterilen son metin aramaları (en fazla 3, en yeni üstte).
class RecentSearchStore {
  RecentSearchStore._();
  static final RecentSearchStore instance = RecentSearchStore._();

  static const _key = 'rotalink_recent_searches_v2';
  static const _legacyKey = 'rotalink_recent_searches';
  static const maxItems = 3;

  final ValueNotifier<List<RecentSearchEntry>> items = ValueNotifier(const []);
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      items.value = _decode(raw);
    } else {
      final legacy = prefs.getStringList(_legacyKey) ?? const [];
      final now = DateTime.now();
      items.value = [
        for (final query in legacy.take(maxItems))
          if (query.trim().isNotEmpty)
            RecentSearchEntry(query: query.trim(), at: now),
      ];
      if (items.value.isNotEmpty) {
        await prefs.setString(_key, _encode(items.value));
      }
    }
    _loaded = true;
  }

  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    await ensureLoaded();
    final key = normalizeForSearch(trimmed);
    if (key.isEmpty) return;
    final next = [
      RecentSearchEntry(query: trimmed, at: DateTime.now()),
      ...items.value.where((e) => normalizeForSearch(e.query) != key),
    ];
    items.value = next.take(maxItems).toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(items.value));
  }

  static String _encode(List<RecentSearchEntry> entries) {
    return jsonEncode([
      for (final e in entries)
        {'q': e.query, 't': e.at.millisecondsSinceEpoch},
    ]);
  }

  static List<RecentSearchEntry> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map && (item['q']?.toString().trim() ?? '').isNotEmpty)
            RecentSearchEntry(
              query: item['q'].toString().trim(),
              at: DateTime.fromMillisecondsSinceEpoch(
                item['t'] is int
                    ? item['t'] as int
                    : int.tryParse(item['t']?.toString() ?? '') ??
                        DateTime.now().millisecondsSinceEpoch,
              ),
            ),
      ].take(maxItems).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
