import 'package:flutter/material.dart';

import '../models/kis_kesfet_place.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';

/// Kış Keşfet ekranlarının ortak görsel dilini tutar.
abstract final class KisKesfetUi {
  static const Color callGreen = Color(0xFF4CAF50);

  static String formatDate(String raw) {
    final date = DateTime.tryParse(raw.trim());
    if (date == null) return raw.trim();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year.toString().padLeft(4, '0')}';
  }

  static String descriptionFor(KisKesfetPlace place) {
    final text = place.kisaAciklama.trim();
    if (place.kategori == KisKesfetKategori.termal &&
        text.toLowerCase().contains('olarak kayıtlıdır')) {
      return '';
    }
    return text;
  }

  static Color accentOf(BuildContext context, KisKesfetKategori kategori) =>
      AppColors.isDark(context)
      ? switch (kategori) {
          KisKesfetKategori.kayak => const Color(0xFF8FCFE9),
          KisKesfetKategori.termal => const Color(0xFFF0BD97),
          KisKesfetKategori.kisGezisi => const Color(0xFFB5BFEF),
        }
      : gradientFor(kategori).first;

  static Color tintOf(BuildContext context, KisKesfetKategori kategori) =>
      accentOf(
        context,
        kategori,
      ).withValues(alpha: AppColors.isDark(context) ? 0.13 : 0.07);

  static String titleFor(KisKesfetKategori kategori) => switch (kategori) {
    KisKesfetKategori.kayak => 'Zirvelere doğru',
    KisKesfetKategori.termal => 'Sıcacık bir mola',
    KisKesfetKategori.kisGezisi => 'Kışın izinde',
  };

  static IconData iconFor(KisKesfetKategori kategori) {
    switch (kategori) {
      case KisKesfetKategori.kayak:
        return Icons.downhill_skiing;
      case KisKesfetKategori.termal:
        return Icons.hot_tub_outlined;
      case KisKesfetKategori.kisGezisi:
        return Icons.ac_unit_rounded;
    }
  }

  static List<Color> gradientFor(KisKesfetKategori kategori) {
    switch (kategori) {
      case KisKesfetKategori.kayak:
        return const [Color(0xFF163C54), Color(0xFF397C97)];
      case KisKesfetKategori.termal:
        return const [Color(0xFF794A39), Color(0xFFB37D59)];
      case KisKesfetKategori.kisGezisi:
        return const [Color(0xFF343C68), Color(0xFF697FA8)];
    }
  }

  static String subtitleFor(KisKesfetKategori kategori) {
    switch (kategori) {
      case KisKesfetKategori.kayak:
        return 'Karın ve zirvelerin keyfini çıkarın.';
      case KisKesfetKategori.termal:
        return 'Kamu ve belediye kaplıcalarını keşfedin.';
      case KisKesfetKategori.kisGezisi:
        return 'Milli parklar ve doğada kış rotaları.';
    }
  }

  static LinearGradient headerGradient(KisKesfetKategori kategori) {
    final colors = gradientFor(kategori);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
  }

  static IconData iconForFact(String baslik) {
    final key = baslik.toLowerCase();
    if (key.contains('pist')) return Icons.downhill_skiing;
    if (key.contains('rakım') || key.contains('zirve')) {
      return Icons.terrain_rounded;
    }
    if (key.contains('sezon')) return Icons.calendar_month_outlined;
    if (key.contains('mesafe') || key.contains('ulaşım')) {
      return Icons.directions_outlined;
    }
    if (key.contains('telesiyej') ||
        key.contains('mekanik') ||
        key.contains('gondol')) {
      return Icons.cable_rounded;
    }
    if (key.contains('kar') || key.contains('disiplin')) {
      return Icons.ac_unit_rounded;
    }
    if (key.contains('tesis') || key.contains('kurum')) {
      return Icons.account_balance_outlined;
    }
    return Icons.info_outline_rounded;
  }

  /// Termal kartlarda kamu / özel ayrımını net gösteren rozet renkleri.
  static Color tesisRozetFill(BuildContext context, KisKesfetPlace place) {
    if (place.isOzelTesis) return const Color(0x1FC9783A);
    if (place.isKamuTesis) return AppColors.primarySoftOf(context);
    return AraUi.primaryActionFillOf(context);
  }

  static Color tesisRozetInk(KisKesfetPlace place) {
    if (place.isOzelTesis) return const Color(0xFFB45309);
    return AppColors.primary;
  }

  static String ilOzeti(KisKesfetKategori kategori, List<KisKesfetPlace> rows) {
    if (kategori != KisKesfetKategori.termal) {
      return kategori.sayiMetni(rows.length);
    }
    final kamu = rows.where((p) => p.isKamuTesis).length;
    final ozel = rows.where((p) => p.isOzelTesis).length;
    if (kamu > 0 && ozel > 0) return '$kamu kamu · $ozel özel';
    if (ozel > 0) return ozel == 1 ? '1 özel tesis' : '$ozel özel tesis';
    return kategori.sayiMetni(rows.length);
  }
}

/// Yalnız Kış Keşfet'te kullanılan, görsel indirmeyen mevsim başlığı.
class KisKesfetHero extends StatelessWidget {
  const KisKesfetHero({
    super.key,
    required this.kategori,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final KisKesfetKategori kategori;
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: KisKesfetUi.headerGradient(kategori),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(painter: _WinterLandscape(kategori)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        KisKesfetUi.iconFor(kategori),
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          eyebrow,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                      letterSpacing: -0.8,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WinterLandscape extends CustomPainter {
  const _WinterLandscape(this.kategori);

  final KisKesfetKategori kategori;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.07);
    canvas.drawCircle(Offset(size.width * 0.95, 20), 95, paint);
    canvas.drawCircle(Offset(size.width * 0.9, 20), 65, paint);
    if (kategori == KisKesfetKategori.termal) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (var i = 0; i < 4; i++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(size.width * 0.96, size.height * 0.88),
            width: 95 + i * 54,
            height: 25 + i * 20,
          ),
          paint,
        );
      }
    } else {
      final ridge = Path()
        ..moveTo(size.width * 0.50, size.height)
        ..lineTo(size.width * 0.76, size.height * 0.37)
        ..lineTo(size.width * 0.9, size.height * 0.68)
        ..lineTo(size.width, size.height * 0.45)
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(ridge, paint);
    }
  }

  @override
  bool shouldRepaint(_WinterLandscape oldDelegate) =>
      oldDelegate.kategori != kategori;
}

class KisKesfetTag extends StatelessWidget {
  const KisKesfetTag({
    super.key,
    required this.text,
    required this.kategori,
    this.icon,
  });

  final String text;
  final KisKesfetKategori kategori;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = KisKesfetUi.accentOf(context, kategori);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: KisKesfetUi.tintOf(context, kategori),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: ink, size: 14),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: ink,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
