import 'package:flutter/material.dart';

import 'app_colors.dart';

/// `themes.xml` + `colors.xml` — Material 3 üzerinde marka renkleri.
ThemeData buildRotalinkTheme() {
  final scheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: AppColors.white,
    secondary: AppColors.purple500,
    onSecondary: AppColors.white,
    surface: AppColors.backgroundMain,
    onSurface: AppColors.textPrimary,
    error: AppColors.emergencyLabel,
    onError: AppColors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: AppColors.backgroundMain,
    appBarTheme: const AppBarTheme(
      elevation: 6,
      centerTitle: false,
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.white,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: AppColors.white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 8,
      color: AppColors.searchBarBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.searchBarBg,
      hintStyle: const TextStyle(color: AppColors.searchBarHint, fontSize: 16),
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    ),
    navigationDrawerTheme: const NavigationDrawerThemeData(
      indicatorColor: AppColors.selectedBackground,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.primary,
      backgroundColor: AppColors.white,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
