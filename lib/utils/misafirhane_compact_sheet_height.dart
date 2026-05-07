import 'package:flutter/material.dart';

/// Favoriler, geçmiş ve arama (FAB) sekmeli alt sayfalar — ekran yüksekliğinin yaklaşık yarısı.
double misafirhaneCompactSheetHeight(BuildContext context) {
  final h = MediaQuery.sizeOf(context).height;
  return (h * 0.5).clamp(260.0, h);
}
