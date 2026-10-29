import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'free_pass_device_guard.dart';

/// Pro olmayan kullanıcı cihaz başına [limit] tesisin fiyatını ücretsiz açar.
///
/// Açılan tesisler kalıcıdır; hak sayısı cihaza bağlı olarak sunucuda
/// tutulur, uygulama silinip yeniden yüklense de yenilenmez.
class FreePriceQuota {
  FreePriceQuota._();
  static final FreePriceQuota instance = FreePriceQuota._();

  static int _serverLimit = 1;
  static int get limit => _serverLimit;

  /// Admin panelindeki ücretsiz fiyat hakkı. Uygulama güncellemesi gerekmez.
  void applyServerLimit(int value) {
    if (value < 0 || value > 100) return;
    _serverLimit = value;
    if (_exhausted && unlockedIds.value.length < value) {
      _exhausted = false;
      unawaited(_save((prefs) => prefs.setBool(_keyExhausted, false)));
    }
    unlockedIds.value = List.unmodifiable(unlockedIds.value);
  }
  static const String _keyFacilities = 'rotalink_free_price_facilities';
  static const String _keyExhausted = 'rotalink_free_price_exhausted';

  /// Ücretsiz açılmış tesislerin [Misafirhane.stableFacilityId] değerleri.
  final ValueNotifier<List<String>> unlockedIds =
      ValueNotifier<List<String>>(const []);

  bool _exhausted = false;
  bool _claiming = false;
  Future<void>? _loading;

  int get remaining {
    final left = (limit - unlockedIds.value.length).clamp(0, limit);
    if (_exhausted && unlockedIds.value.length >= limit) return 0;
    return left;
  }

  bool contains(String facilityId) => unlockedIds.value.contains(facilityId);

  Future<void> initialize() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _exhausted = prefs.getBool(_keyExhausted) ?? false;
      unlockedIds.value = List.unmodifiable(
        prefs.getStringList(_keyFacilities) ?? const <String>[],
      );
      if (_exhausted && unlockedIds.value.length < limit) {
        _exhausted = false;
      }
    } catch (e) {
      debugPrint('[Pro] ücretsiz fiyat hakları okunamadı: $e');
    }
  }

  /// Tesisin fiyatını ücretsiz hakla açar; sonucu kullanıcıya gösterilecek
  /// hata metni olarak döner (başarıda null).
  Future<String?> unlock(String facilityId) async {
    await initialize();
    if (contains(facilityId)) return null;
    if (remaining == 0) return 'Ücretsiz $limit tesis hakkınızı kullandınız.';
    if (_claiming) return 'İşlem sürüyor, lütfen bekleyin.';
    _claiming = true;
    try {
      final claim = await FreePassDeviceGuard.claimPriceSlot(
        fromSlot: unlockedIds.value.length + 1,
        maxSlots: limit,
      );
      switch (claim) {
        case FreePassClaim.granted:
          final ids = [...unlockedIds.value, facilityId];
          unlockedIds.value = List.unmodifiable(ids);
          await _save((p) => p.setStringList(_keyFacilities, ids));
          return null;
        case FreePassClaim.alreadyUsed:
          _exhausted = true;
          unlockedIds.value = List.unmodifiable(unlockedIds.value);
          await _save((p) => p.setBool(_keyExhausted, true));
          return 'Bu cihazda ücretsiz $limit tesis hakkı daha önce kullanıldı.';
        case FreePassClaim.unavailable:
          return 'Fiyat açılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      }
    } finally {
      _claiming = false;
    }
  }

  Future<void> _save(Future<bool> Function(SharedPreferences p) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (e) {
      debugPrint('[Pro] ücretsiz fiyat hakkı kaydedilemedi: $e');
    }
  }
}
