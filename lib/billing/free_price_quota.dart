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

  static const int limit = 3;
  static const String _keyFacilities = 'rotalink_free_price_facilities';
  static const String _keyExhausted = 'rotalink_free_price_exhausted';

  /// Ücretsiz açılmış tesislerin [Misafirhane.stableFacilityId] değerleri.
  final ValueNotifier<List<String>> unlockedIds =
      ValueNotifier<List<String>>(const []);

  bool _exhausted = false;
  bool _claiming = false;
  Future<void>? _loading;

  int get remaining =>
      _exhausted ? 0 : (limit - unlockedIds.value.length).clamp(0, limit);

  bool contains(String facilityId) => unlockedIds.value.contains(facilityId);

  Future<void> initialize() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _exhausted = prefs.getBool(_keyExhausted) ?? false;
      unlockedIds.value = List.unmodifiable(
        prefs.getStringList(_keyFacilities) ?? const <String>[],
      );
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
