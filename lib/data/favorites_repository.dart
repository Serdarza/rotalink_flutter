import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/misafirhane.dart';

/// Kotlin `encryptedPrefs` + `saveListToPrefs("favorites")` / `loadListFromPrefs`.
class FavoritesRepository {
  FavoritesRepository({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;

  static const String _key = 'favorites';
  static const int maxFavorites = 5;

  Future<SharedPreferences> _sp() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<List<Misafirhane>> load() async {
    final sp = await _sp();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      var parsed = list.map((e) {
        if (e is! Map) return null;
        final m = e.map((k, v) => MapEntry(k.toString(), v));
        return Misafirhane.tryParse(m);
      }).whereType<Misafirhane>().toList();
      if (parsed.length > maxFavorites) {
        parsed = parsed.sublist(parsed.length - maxFavorites);
        await save(parsed);
      }
      return parsed;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<Misafirhane> list) async {
    final sp = await _sp();
    final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await sp.setString(_key, encoded);
  }

  /// Kotlin [MisafirhaneAdapter] kalp: yoksa ekle; varsa çıkar; sonra `while (size > 5) removeAt(0)`.
  Future<List<Misafirhane>> toggle(Misafirhane m) async {
    var list = await load();
    final exists = list.any((x) => x.sameFavoriteIdentity(m));
    if (exists) {
      list = list.where((x) => !x.sameFavoriteIdentity(m)).toList();
    } else {
      list = [...list, m];
      while (list.length > maxFavorites) {
        list = list.sublist(1);
      }
    }
    await save(list);
    return list;
  }
}
