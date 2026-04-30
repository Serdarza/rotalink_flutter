import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/misafirhane.dart';

/// Kotlin `saveListToPrefs("history")` / `loadListFromPrefs` + [MainActivity.addToHistory].
class HistoryRepository {
  HistoryRepository({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;

  static const String _key = 'history';
  static const int maxHistory = 5;

  Future<SharedPreferences> _sp() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<List<Misafirhane>> load() async {
    final sp = await _sp();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      var list = decoded.map((e) {
        if (e is! Map) return null;
        final m = e.map((k, v) => MapEntry(k.toString(), v));
        return Misafirhane.tryParse(m);
      }).whereType<Misafirhane>().toList();
      if (list.length > maxHistory) {
        list = list.sublist(0, maxHistory);
        await save(list);
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<Misafirhane> list) async {
    final sp = await _sp();
    final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await sp.setString(_key, encoded);
  }

  /// Kotlin [MainActivity.addToHistory]: kopyayı sil, başa ekle, fazlaysa sondan düşür.
  Future<List<Misafirhane>> recordVisit(Misafirhane m) async {
    var list = await load();
    list = list.where((x) => !x.sameFavoriteIdentity(m)).toList();
    list = [m, ...list];
    if (list.length > maxHistory) {
      list = list.sublist(0, maxHistory);
    }
    await save(list);
    return list;
  }
}
