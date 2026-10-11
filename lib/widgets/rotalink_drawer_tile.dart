import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Açılır menü satırı — tüm maddelerde aynı yazı ve boşluk.
class RotalinkDrawerTile extends StatelessWidget {
  const RotalinkDrawerTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;

  static TextStyle titleStyle(BuildContext context) => TextStyle(
        color: AppColors.textStrongOf(context),
        fontFamily: 'Roboto',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0,
      );

  @override
  Widget build(BuildContext context) {
    final style = titleStyle(context);
    return ListTile(
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, color: AppColors.primary),
      titleTextStyle: style,
      title: Text(title, style: style),
      trailing: trailing ??
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textMutedOf(context),
          ),
      onTap: onTap,
    );
  }
}
