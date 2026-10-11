import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

/// Yeni ana sayfa ile harita üst satırının ortak başlığı.
class RotalinkAppHeader extends StatelessWidget {
  const RotalinkAppHeader({
    super.key,
    required this.onMenu,
    this.onTitleTap,
    this.menuAnchorKey,
    this.trailing,
    this.overlayOnMap = false,
  });

  final VoidCallback onMenu;
  final VoidCallback? onTitleTap;
  final Key? menuAnchorKey;
  final Widget? trailing;
  final bool overlayOnMap;

  @override
  Widget build(BuildContext context) {
    final top = overlayOnMap ? MediaQuery.paddingOf(context).top : 0.0;
    final row = Padding(
      padding: EdgeInsets.fromLTRB(8, top + 4, 12, 4),
      child: Row(
        children: [
          KeyedSubtree(
            key: menuAnchorKey,
            child: Semantics(
              button: true,
              label: AppStrings.menuOpen,
              child: IconButton(
                onPressed: onMenu,
                tooltip: AppStrings.menuOpen,
                icon: const Icon(Icons.menu_rounded),
                color: AppColors.textStrongOf(context),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: 32,
              height: 32,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _Title(onTap: onTitleTap)),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    if (!overlayOnMap) return row;

    return Material(
      elevation: 0,
      color: AppColors.surfaceOf(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
        ),
        child: row,
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      AppStrings.appName,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 22),
    );
    if (onTap == null) return text;
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(onTap: onTap, child: text),
    );
  }
}
