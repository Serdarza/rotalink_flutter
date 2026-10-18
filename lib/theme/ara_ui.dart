import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Ara ekranı (arama kutusu, filtre çipleri, sekmeler, kart eylemleri) için
/// küçük ortak görsel token seti.
///
/// Kural: dolu turkuaz yalnızca bir gruptaki **seçili** öğede kullanılır;
/// ikincil eylemler beyaz yüzey + ince çerçeve, ana eylem açık turkuaz yüzey.
abstract final class AraUi {
  // ── Birincil / aktif ──────────────────────────────────────────────────────
  static const Color activeFill = AppColors.primary;
  static const Color activeForeground = Colors.white;

  // ── Pasif (açık yüzey, harita / liste zemini) ────────────────────────────
  static const Color inactiveFill = Colors.white;
  static const Color inactiveBorder = Color(0xFFD9E2E4);
  static const Color inactiveForeground = Color(0xFF2B3A40);

  /// Sekme / segment kapsayıcı yüzeyi (çok açık gri-turkuaz).
  static const Color trackFill = Color(0xFFEEF3F4);

  /// Başlık altı arama + filtre bölgesinin zemini (beyaz arama kutusu öne çıksın).
  static const Color chromeFill = Color(0xFFE3EDEF);

  /// Liste zemini; beyaz kartlar bunun üzerinde ayrışır.
  static const Color canvas = Color(0xFFEDF2F3);

  /// Ana ekranların ortak sayfa zemini (koyu temada mevcut koyu zemin).
  static Color pageOf(BuildContext context) =>
      AppColors.isDark(context) ? AppColors.darkCanvas : canvas;

  static Color inactiveFillOf(BuildContext context) =>
      AppColors.isDark(context) ? AppColors.darkSurface : inactiveFill;

  static Color inactiveBorderOf(BuildContext context) =>
      AppColors.isDark(context) ? AppColors.darkBorder : inactiveBorder;

  static Color inactiveForegroundOf(BuildContext context) =>
      AppColors.isDark(context) ? AppColors.darkTextStrong : inactiveForeground;

  static Color trackFillOf(BuildContext context) =>
      AppColors.isDark(context) ? const Color(0xFF243033) : trackFill;

  static Color chromeFillOf(BuildContext context) =>
      AppColors.isDark(context) ? AppColors.darkCanvas : chromeFill;

  static Color cardBorderOf(BuildContext context) =>
      AppColors.isDark(context) ? AppColors.darkBorder : cardBorder;

  static Color secondaryActionFillOf(BuildContext context) =>
      AppColors.isDark(context) ? AppColors.darkSurface : secondaryActionFill;

  static Color secondaryActionBorderOf(BuildContext context) =>
      AppColors.isDark(context) ? AppColors.darkBorder : secondaryActionBorder;

  static Color primaryActionFillOf(BuildContext context) =>
      AppColors.primarySoftOf(context);

  static Color mutedTextOf(BuildContext context) =>
      AppColors.isDark(context) ? AppColors.darkTextMuted : mutedText;

  static Color subtleTextOf(BuildContext context) =>
      AppColors.isDark(context) ? const Color(0xFF8AA0A6) : subtleText;

  /// Kart sınırı.
  static const Color cardBorder = Color(0xFFDCE5E7);

  // ── İkincil / ana kart eylemleri ──────────────────────────────────────────
  static const Color secondaryActionFill = Color(0xFFF0F4F5);
  static const Color secondaryActionBorder = Color(0xFFD3DEE0);
  static const Color primaryActionFill = AppColors.primarySoft;
  static final Color primaryActionBorder = AppColors.primary.withValues(
    alpha: 0.35,
  );

  // ── Metin ─────────────────────────────────────────────────────────────────
  static const Color mutedText = Color(0xFF5F6F75);
  static const Color subtleText = Color(0xFF7D8C92);

  /// Seçili favori kalbi.
  static const Color favorite = Color(0xFFD6455D);

  /// Minimum dokunma yüksekliği (eylem düğmeleri).
  static const double actionHeight = 44;

  // ── Kategori tonları (yalnız küçük ikon alanı) ───────────────────────────
  static const AraTone stay = AraTone(AppColors.primary, Color(0xFFE4F3F4));
  static const AraTone gezi = AraTone(Color(0xFF2E7D32), Color(0xFFE8F5E9));
  static const AraTone yemek = AraTone(Color(0xFFC9482B), Color(0xFFFDEBE5));
  static const AraTone tesis = AraTone(Color(0xFF2F4B7C), Color(0xFFE8EEF7));
  static const AraTone hediyelik = AraTone(
    Color(0xFF9A6410),
    Color(0xFFFFF3DC),
  );
  static const AraTone kamp = AraTone(Color(0xFF4C7A34), Color(0xFFEDF4E6));
}

/// İkon rengi + açık zemin çifti.
class AraTone {
  const AraTone(this.fg, this.bg);

  final Color fg;
  final Color bg;
}
