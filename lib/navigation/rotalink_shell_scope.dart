import 'package:flutter/material.dart';

import '../onboarding/app_onboarding_controller.dart';
import '../widgets/rotalink_glass_bottom_nav.dart';

/// Alt menülü kabuk içindeki sayfalar için gezinme yardımcıları.
class RotalinkShellScope extends InheritedWidget {
  const RotalinkShellScope({
    super.key,
    required this.goHome,
    required this.selectTab,
    required this.onboarding,
    required super.child,
  });

  final VoidCallback goHome;
  final void Function(RotalinkBottomNavItem tab) selectTab;
  final AppOnboardingController onboarding;

  static RotalinkShellScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RotalinkShellScope>();
  }

  static bool isInShell(BuildContext context) => maybeOf(context) != null;

  /// Kaydırılabilir içerik alt boşluğu — kabuk menüsünün altına taşmayı önler.
  static double scrollBottomPadding(BuildContext context) {
    if (isInShell(context)) {
      return 20;
    }
    return 20 + MediaQuery.viewPaddingOf(context).bottom;
  }

  @override
  bool updateShouldNotify(RotalinkShellScope oldWidget) =>
      oldWidget.onboarding != onboarding;
}
