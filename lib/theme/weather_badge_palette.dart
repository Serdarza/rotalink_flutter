import 'package:flutter/material.dart';
import 'app_colors.dart';

// Shared with the home weather chip; changing the layout never changes colors.
List<Color> weatherBadgeGradient(String icon) {
  if (icon.startsWith('01')) {
    return const [Color(0xFFFFB347), Color(0xFFFF8C42), Color(0xFFE85D04)];
  }
  if (icon.startsWith('02') || icon.startsWith('03') || icon.startsWith('04')) {
    return const [Color(0xFF90A4AE), Color(0xFF607D8B), Color(0xFF455A64)];
  }
  if (icon.startsWith('09') || icon.startsWith('10')) {
    return const [Color(0xFF4FC3F7), Color(0xFF0288D1), Color(0xFF01579B)];
  }
  if (icon.startsWith('11')) {
    return const [Color(0xFF5C6BC0), Color(0xFF3949AB), Color(0xFF283593)];
  }
  if (icon.startsWith('13')) {
    return const [Color(0xFFB3E5FC), Color(0xFF81D4FA), Color(0xFF4FC3F7)];
  }
  if (icon.startsWith('50')) {
    return const [Color(0xFFB0BEC5), Color(0xFF78909C), Color(0xFF546E7A)];
  }
  return [
    AppColors.drawerHeaderGradientStart,
    AppColors.drawerHeaderGradientEnd,
    AppColors.purple500.withValues(alpha: 0.9),
  ];
}
