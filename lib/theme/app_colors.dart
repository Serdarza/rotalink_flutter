import 'package:flutter/material.dart';

/// `KamuMisafirhaneleri/app/src/main/res/values/colors.xml` ile eşleşen palet.
abstract final class AppColors {
  /// Yeni arayüzün nötr yüzey ve metin renkleri.
  ///
  /// Eski adlar geriye dönük olarak korunur; veri/özellik ekranlarının renk
  /// bağımlılıkları kırılmadan ekranlar kademeli olarak bu token'lara taşınır.
  static const Color canvas = Color(0xFFF6F8F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEDF4F5);
  static const Color border = Color(0xFFE1E8E9);
  static const Color textStrong = Color(0xFF15262D);
  static const Color textMuted = Color(0xFF64747A);
  static const Color primarySoft = Color(0xFFE4F3F4);
  static const Color warning = Color(0xFFF2A900);
  static const Color danger = Color(0xFFC83C43);

  static const Color searchBarBg = Color(0xFFFFFFFF);
  static const Color searchBarText = Color(0xFF222222);
  static const Color searchBarHint = Color(0xFF4A9EAF);
  static const Color backgroundMain = canvas;
  static const Color purple200 = Color(0xFF80DEEA);
  static const Color purple500 = Color(0xFF00BCD4);
  static const Color purple700 = Color(0xFF007B8F);
  static const Color teal200 = Color(0xFF80DEEA);
  static const Color teal700 = Color(0xFF007B8F);
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color selectedBackground = Color(0xFFB2EBF2);
  static const Color primary = Color(0xFF007B8F);
  static const Color mapLocationPin = Color(0xFFE53935);
  static const Color campaignBtnSecondary = Color(0xFFE0F7FA);
  static const Color discoverSkeleton = Color(0xFFE8E8E8);
  static const Color textPrimary = textStrong;
  static const Color myCustomGreen = Color(0xFF1B5E20);
  static const Color suggestionBg = Color(0xFFF5FDFE);
  static const Color suggestionTitle = Color(0xFF007B8F);
  static const Color suggestionText = Color(0xFF222222);
  static const Color suggestionFieldBg = Color(0xFFFFFFFF);
  static const Color suggestionFieldText = Color(0xFF222222);
  static const Color suggestionButtonBg = Color(0xFF007B8F);
  static const Color suggestionButtonText = Color(0xFFFFFFFF);
  static const Color campaignDiscountBadge = Color(0xFFE65100);
  static const Color campaignSummaryMuted = Color(0xFF616161);

  /// `nav_drawer_header` / `bg_teal_header_rounded.xml` gradyan uçları.
  static const Color drawerHeaderGradientStart = Color(0xFF005F6B);
  static const Color drawerHeaderGradientEnd = Color(0xFF008898);

  static const Color bottomNavHistoryTint = Color(0xFF4CAF50);
  static const Color bottomNavRouteTint = Color(0xFF2196F3);
  static const Color bottomNavDiscoverTint = Color(0xFFFF9800);
  static const Color bottomNavIlanlarTint = Color(0xFF5E35B1);
  static const Color emergencyLabel = Color(0xFFD50000);

  static const Color darkCanvas = Color(0xFF10181A);
  static const Color darkSurface = Color(0xFF1B2629);
  static const Color darkBorder = Color(0xFF2C3C40);
  static const Color darkTextStrong = Color(0xFFF2F6F7);
  static const Color darkTextMuted = Color(0xFF9AABAF);
  static const Color darkPrimarySoft = Color(0xFF163238);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color canvasOf(BuildContext context) =>
      isDark(context) ? darkCanvas : canvas;

  static Color surfaceOf(BuildContext context) =>
      isDark(context) ? darkSurface : surface;

  static Color borderOf(BuildContext context) =>
      isDark(context) ? darkBorder : border;

  static Color textStrongOf(BuildContext context) =>
      isDark(context) ? darkTextStrong : textStrong;

  static Color textMutedOf(BuildContext context) =>
      isDark(context) ? darkTextMuted : textMuted;

  static Color primarySoftOf(BuildContext context) =>
      isDark(context) ? darkPrimarySoft : primarySoft;
}
