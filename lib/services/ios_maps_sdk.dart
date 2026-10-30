import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS Maps SDK anahtarı IPA'da yoksa [GoogleMap] oluşturmak uygulamayı çökertir.
abstract final class IosMapsSdk {
  static const _channel = MethodChannel('rotalink/maps');

  /// iOS dışında harita anahtarı native tarafta ayrı doğrulanmaz.
  static bool ready =
      !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

  static Future<void> resolve() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      ready = !kIsWeb;
      return;
    }
    try {
      ready = await _channel.invokeMethod<bool>('ready') == true;
    } catch (_) {
      ready = false;
    }
  }
}
