import 'package:flutter/material.dart';

/// Favoriler ve arama (FAB) sekmeli alt sayfalar — ekran yüksekliğinin yaklaşık yarısı.
double misafirhaneCompactSheetHeight(BuildContext context) {
  final h = MediaQuery.sizeOf(context).height;
  return (h * 0.5).clamp(260.0, h);
}

/// Konaklama detay kartı — alt menünün üstünde kalacak yükseklik.
double misafirhaneCompactDetailSheetHeight(BuildContext context) {
  final h = MediaQuery.sizeOf(context).height;
  final bottomNav = 64.0 + MediaQuery.paddingOf(context).bottom;
  // Detay tüm kullanılabilir gövdeyi kullanır; alt navigasyon korunur.
  return (h - bottomNav).clamp(0.0, h);
}
