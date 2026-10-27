import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Equal-width detail shortcuts share one accessible visual treatment.
class FacilityDetailAction extends StatelessWidget {
  const FacilityDetailAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.color = AppColors.primary,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72, minWidth: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 0.17 : 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textStrongOf(context),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
