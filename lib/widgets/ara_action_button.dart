import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';

/// Ara ekranındaki tüm kart eylemleri için tek ölçü ve tasarım.
///
/// [primary]: kartın ana eylemi (açık turkuaz yüzey, turkuaz çerçeve, kalın yazı).
/// Diğerleri: açık gri yüzey + ince çerçeve + koyu yazı.
class AraActionButton extends StatelessWidget {
  const AraActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final fg = primary ? AppColors.primary : AraUi.inactiveForegroundOf(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: primary ? AraUi.primaryActionFill : AraUi.secondaryActionFillOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: primary
                ? AraUi.primaryActionBorder
                : AraUi.secondaryActionBorderOf(context),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            height: AraUi.actionHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 17,
                      color: primary ? AppColors.primary : AraUi.mutedTextOf(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: primary ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Eylem düğmelerini tüm kartlarda aynı genişlik ve yükseklikte tek satırda dizer.
///
/// Satır [slots] eşit yuvaya bölünür; 3 eylemli kartta son yuva boş kalır, böylece
/// düğme ölçüsü kartlar arasında değişmez.
class AraActionRow extends StatelessWidget {
  const AraActionRow({super.key, required this.children, this.slots = 4});

  final List<Widget> children;
  final int slots;

  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = children.length > slots ? children.length : slots;
        final w = (constraints.maxWidth - _gap * (n - 1)) / n;
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              SizedBox(width: w, child: children[i]),
            ],
          ],
        );
      },
    );
  }
}
