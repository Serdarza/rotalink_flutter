import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum FreePassClaim { granted, alreadyUsed, unavailable }

enum GiftClaimKind { granted, restored, exhausted, unavailable }

/// Hediye kod kullanım sonucu; [start] hakkın başladığı an.
class GiftClaim {
  const GiftClaim(this.kind, [this.start]);

  final GiftClaimKind kind;
  final DateTime? start;
}

/// Ücretsiz fiyat haklarını ve hediye kod kullanımlarını cihaza bağlar;
/// uygulama silinip yeniden yüklense de haklar yenilenmez.
///
/// Kimlik uygulama silinince değişmeyen bir değerdir: Android'de `ANDROID_ID`
/// (aynı imza anahtarı + cihaz + kullanıcı için sabit; fabrika ayarında
/// değişir), iOS'ta Keychain'e yazılan rastgele kimlik (Keychain uygulama
/// silinince silinmez). Firestore'a yalnız SHA-256 özeti yazılır.
abstract final class FreePassDeviceGuard {
  static const _channel = MethodChannel('rotalink/device');
  static const _keychainKey = 'rotalink_free_pass_device_id';
  static const _collection = 'freePassClaims';

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<String?> _deviceId() async {
    if (Platform.isAndroid) {
      final id = await _channel.invokeMethod<String>('androidId');
      return id == null || id.isEmpty ? null : 'android:$id';
    }
    if (Platform.isIOS) {
      var id = await _storage.read(key: _keychainKey);
      if (id == null || id.isEmpty) {
        final rnd = Random.secure();
        id = base64UrlEncode(List<int>.generate(24, (_) => rnd.nextInt(256)));
        await _storage.write(key: _keychainKey, value: id);
      }
      return 'ios:$id';
    }
    return null;
  }

  static DocumentReference<Map<String, dynamic>> _docFor(String seed) {
    final hash = sha256.convert(utf8.encode(seed)).toString();
    return FirebaseFirestore.instance.collection(_collection).doc(hash);
  }

  static DocumentReference<Map<String, dynamic>> _slotDoc(String deviceId, int slot) =>
      _docFor('rotalink-free-price:$deviceId:$slot');

  static Map<String, dynamic> _claimData() => {
    'createdAt': FieldValue.serverTimestamp(),
    'platform': Platform.operatingSystem,
  };

  static DateTime? _createdAt(DocumentSnapshot<Map<String, dynamic>> snap) =>
      (snap.data()?['createdAt'] as Timestamp?)?.toDate();

  /// Hediye kodu bu cihaz adına kullanır. Kod [maxUses] kez kullanılabilir;
  /// aynı cihaz aynı kodu ikinci kez alamaz, yeniden yüklemede ilk kullanım
  /// anı [GiftClaimKind.restored] ile döner.
  static Future<GiftClaim> redeemGiftCode({
    required String codeHash,
    required int maxUses,
  }) async {
    try {
      final id = await _deviceId();
      if (id == null) return const GiftClaim(GiftClaimKind.unavailable);
      final deviceRef = _docFor('rotalink-pro-kod-cihaz:$codeHash:$id');
      const server = GetOptions(source: Source.server);
      final mine = await deviceRef.get(server);
      if (mine.exists) {
        return GiftClaim(GiftClaimKind.restored, _createdAt(mine));
      }
      const chunk = 20;
      for (var first = 1; first <= maxUses; first += chunk) {
        final last = min(maxUses, first + chunk - 1);
        final refs = [
          for (var i = first; i <= last; i++)
            _docFor('rotalink-pro-kod:$codeHash:$i'),
        ];
        final snaps = await Future.wait(refs.map((r) => r.get(server)));
        for (var k = 0; k < refs.length; k++) {
          if (snaps[k].exists) continue;
          final result = await FirebaseFirestore.instance
              .runTransaction<GiftClaim?>((tx) async {
                final d = await tx.get(deviceRef);
                if (d.exists) {
                  return GiftClaim(GiftClaimKind.restored, _createdAt(d));
                }
                if ((await tx.get(refs[k])).exists) return null;
                tx.set(refs[k], _claimData());
                tx.set(deviceRef, _claimData());
                return GiftClaim(GiftClaimKind.granted, DateTime.now());
              }, timeout: const Duration(seconds: 10));
          if (result != null) return result;
        }
      }
      return const GiftClaim(GiftClaimKind.exhausted);
    } catch (e) {
      debugPrint('[Pro] hediye kod kaydedilemedi: $e');
      return const GiftClaim(GiftClaimKind.unavailable);
    }
  }

  /// [fromSlot]..[maxSlots] arasındaki ilk boş fiyat hakkını bu cihaz adına
  /// kaydeder. Hepsi doluysa [FreePassClaim.alreadyUsed]; çevrimdışıyken veya
  /// sunucu yanıt vermezken [FreePassClaim.unavailable].
  static Future<FreePassClaim> claimPriceSlot({
    required int fromSlot,
    required int maxSlots,
  }) async {
    try {
      final id = await _deviceId();
      if (id == null) return FreePassClaim.unavailable;
      for (var slot = fromSlot; slot <= maxSlots; slot++) {
        final ref = _slotDoc(id, slot);
        final granted = await FirebaseFirestore.instance.runTransaction<bool>(
          (tx) async {
            final snap = await tx.get(ref);
            if (snap.exists) return false;
            tx.set(ref, _claimData());
            return true;
          },
          timeout: const Duration(seconds: 10),
        );
        if (granted) return FreePassClaim.granted;
      }
      return FreePassClaim.alreadyUsed;
    } on FirebaseException catch (e) {
      debugPrint('[Pro] ücretsiz fiyat hakkı kaydedilemedi: $e');
      // Firestore kuralları bu belgeye izin vermiyorsa yalnız yerel sınır uygulanır.
      return e.code == 'permission-denied'
          ? FreePassClaim.granted
          : FreePassClaim.unavailable;
    } catch (e) {
      debugPrint('[Pro] ücretsiz fiyat hakkı kaydedilemedi: $e');
      return FreePassClaim.unavailable;
    }
  }
}
