import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../onboarding/app_onboarding_controller.dart';
import '../theme/app_colors.dart';

enum RotalinkBottomNavItem { home, favorites, search, route, discover }

/// Tam genişlik alt gezinme çubuğu — banner ile hizalı, düz profesyonel görünüm.
class RotalinkGlassBottomNav extends StatelessWidget {
  const RotalinkGlassBottomNav({
    super.key,
    required this.selected,
    required this.onHome,
    required this.onFavorites,
    required this.onSearch,
    required this.onRoutePlan,
    required this.onDiscover,
    this.navTargetKeys = const {},
  });

  final RotalinkBottomNavItem selected;
  final VoidCallback onHome;
  final VoidCallback onFavorites;
  final VoidCallback onSearch;
  final VoidCallback onRoutePlan;
  final VoidCallback onDiscover;
  final Map<OnboardingTarget, GlobalKey> navTargetKeys;

  static const _barHeight = 64.0;
  static const _iconSize = 24.0;
  /// Material 3 [NavigationBar] etiket boyutu (12sp).
  static const _labelFontSize = 12.0;

  /// Alt menü + sistem gezinme çubuğu için sheet/liste alt boşluğu.
  static double totalHeight(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return _barHeight + bottomInset;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border(
              top: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
          ),
          child: SizedBox(
            height: _barHeight,
            child: Row(
              children: [
                _NavSlot(
                  selected: selected == RotalinkBottomNavItem.home,
                  icon: Icons.home_rounded,
                  label: AppStrings.bottomHome,
                  onTap: onHome,
                ),
                _NavSlot(
                  selected: selected == RotalinkBottomNavItem.favorites,
                  icon: Icons.favorite_rounded,
                  label: AppStrings.bottomFavorites,
                  onTap: onFavorites,
                  anchorKey: navTargetKeys[OnboardingTarget.navFavorites],
                ),
                _NavSlot(
                  selected: false,
                  icon: Icons.search_rounded,
                  label: AppStrings.bottomSearch,
                  onTap: onSearch,
                  anchorKey: navTargetKeys[OnboardingTarget.navSearch],
                ),
                _NavSlot(
                  selected: selected == RotalinkBottomNavItem.route,
                  icon: Icons.alt_route_rounded,
                  label: AppStrings.bottomRoutePlan,
                  onTap: onRoutePlan,
                  anchorKey: navTargetKeys[OnboardingTarget.navRoute],
                ),
                _NavSlot(
                  selected: selected == RotalinkBottomNavItem.discover,
                  icon: Icons.card_giftcard_rounded,
                  label: AppStrings.bottomDiscover,
                  onTap: onDiscover,
                  anchorKey: navTargetKeys[OnboardingTarget.navDiscover],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  const _NavSlot({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.anchorKey,
  });

  static const _inactiveColor = Color(0xFF5A6A72);

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final GlobalKey? anchorKey;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : _inactiveColor;

    return Expanded(
      child: KeyedSubtree(
        key: anchorKey,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: selected ? AppColors.primary : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: RotalinkGlassBottomNav._iconSize),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: RotalinkGlassBottomNav._labelFontSize,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      height: 1.15,
                      letterSpacing: 0.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
