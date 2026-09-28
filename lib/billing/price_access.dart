import 'package:flutter/foundation.dart' show kDebugMode;

import 'pro_service.dart';

/// Konaklama fiyatlarının açık olup olmadığı — tüm fiyat arayüzleri buna bakar.
abstract final class PriceAccess {
  /// `--dart-define=PRICE_PREVIEW=true` ile debug'da da kilitli önizleme görülür.
  static const _forcePreview = bool.fromEnvironment('PRICE_PREVIEW');

  /// Debug derlemede (flutter run) geliştirici testi için açık; mağaza
  /// (release) derlemesinde `kDebugMode` sabit false olduğundan kilit aynen kalır.
  static bool get unlocked =>
      (kDebugMode && !_forcePreview) || ProService.instance.isAdFree;
}
