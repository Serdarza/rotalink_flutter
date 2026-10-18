import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'system_ui.dart';

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
    dividerColor: AppColors.border,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        color: AppColors.textStrong,
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: TextStyle(
        color: AppColors.textStrong,
        fontSize: 20,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        color: AppColors.textStrong,
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: AppColors.textStrong,
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        color: AppColors.textStrong,
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        color: AppColors.textMuted,
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textStrong,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: RotalinkSystemUi.darkIcons,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: AppColors.textStrong,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.searchBarBg,
      hintStyle: const TextStyle(color: AppColors.searchBarHint, fontSize: 16),
      labelStyle: const TextStyle(color: AppColors.textMuted),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionHandleColor: AppColors.primary,
      selectionColor: AppColors.primary.withValues(alpha: 0.28),
    ),
  );
}

ThemeData buildRotalinkDarkTheme() {
  final scheme = ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: AppColors.white,
    secondary: AppColors.purple500,
    onSecondary: AppColors.white,
    surface: AppColors.darkCanvas,
    onSurface: AppColors.darkTextStrong,
    onSurfaceVariant: AppColors.darkTextMuted,
    surfaceContainerLowest: AppColors.darkCanvas,
    surfaceContainerLow: AppColors.darkSurface,
    surfaceContainer: AppColors.darkSurface,
    surfaceContainerHigh: const Color(0xFF243033),
    surfaceContainerHighest: const Color(0xFF2C3C40),
    outline: AppColors.darkBorder,
    outlineVariant: AppColors.darkBorder,
    error: AppColors.emergencyLabel,
    onError: AppColors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: AppColors.darkCanvas,
    dividerColor: AppColors.darkBorder,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        color: AppColors.darkTextStrong,
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: TextStyle(
        color: AppColors.darkTextStrong,
        fontSize: 20,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        color: AppColors.darkTextStrong,
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: AppColors.darkTextStrong,
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        color: AppColors.darkTextStrong,
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        color: AppColors.darkTextMuted,
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.darkTextStrong,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: RotalinkSystemUi.lightIcons,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: AppColors.darkTextStrong,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.darkSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface,
      hintStyle: const TextStyle(color: AppColors.darkTextMuted, fontSize: 16),
      labelStyle: const TextStyle(color: AppColors.darkTextMuted),
      floatingLabelStyle: const TextStyle(color: AppColors.purple200),
      prefixIconColor: AppColors.darkTextMuted,
      suffixIconColor: AppColors.darkTextMuted,
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    navigationDrawerTheme: const NavigationDrawerThemeData(
      backgroundColor: AppColors.darkSurface,
      indicatorColor: AppColors.darkPrimarySoft,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.darkTextMuted,
      backgroundColor: AppColors.darkSurface,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.darkTextMuted),
    listTileTheme: const ListTileThemeData(
      textColor: AppColors.darkTextStrong,
      iconColor: AppColors.darkTextMuted,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.darkSurface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.darkSurface,
      modalBackgroundColor: AppColors.darkSurface,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.darkSurface,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: AppColors.darkTextStrong),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(color: AppColors.darkTextStrong),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.darkBorder),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.darkPrimarySoft,
      labelStyle: const TextStyle(color: AppColors.darkTextStrong),
      side: const BorderSide(color: AppColors.darkBorder),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      textColor: AppColors.darkTextStrong,
      collapsedTextColor: AppColors.darkTextStrong,
      iconColor: AppColors.darkTextMuted,
      collapsedIconColor: AppColors.darkTextMuted,
    ),
    checkboxTheme: CheckboxThemeData(
      checkColor: const WidgetStatePropertyAll(AppColors.white),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.darkBorder,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.darkTextMuted,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.darkTextMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary.withValues(alpha: 0.45)
            : AppColors.darkBorder,
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.primary,
      thumbColor: AppColors.primary,
      inactiveTrackColor: AppColors.darkBorder,
    ),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: AppColors.darkSurface,
    ),
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: AppColors.darkSurface,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionHandleColor: AppColors.primary,
      selectionColor: AppColors.primary.withValues(alpha: 0.35),
    ),
    tooltipTheme: const TooltipThemeData(
      textStyle: TextStyle(color: AppColors.darkTextStrong),
    ),
  );
}
