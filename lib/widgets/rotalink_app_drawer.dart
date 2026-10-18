import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/store_links.dart';
import '../l10n/app_strings.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../theme/app_colors.dart';
import 'drawer_social_section.dart';
import 'rotalink_drawer_tile.dart';

/// Yeni ana sayfa ile harita menüsünün ortak açılır menüsü.
class RotalinkAppDrawer extends StatelessWidget {
  const RotalinkAppDrawer({
    super.key,
    required this.onOpenRoute,
    required this.onOpenWeather,
  });

  final ValueChanged<String> onOpenRoute;
  final VoidCallback onOpenWeather;

  Future<void> _openWebsite(BuildContext context) async {
    Navigator.pop(context);
    final uri = Uri.parse('https://rotalink.tr/?web=1');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Web sitesi açılamadı.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    void openRoute(String route) {
      Navigator.pop(context);
      onOpenRoute(route);
    }

    return Drawer(
      width: 300,
      backgroundColor: AppColors.surfaceOf(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.appName,
                          style: TextStyle(
                            color: AppColors.textStrongOf(context),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppStrings.drawerSubtitle,
                          style: TextStyle(
                            color: AppColors.textMutedOf(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  RotalinkDrawerTile(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Rotalink Pro',
                    onTap: () => openRoute(RotalinkShellRoutes.pro),
                  ),
                  RotalinkDrawerTile(
                    icon: Icons.wb_sunny_outlined,
                    title: AppStrings.drawerWeather,
                    onTap: () {
                      Navigator.pop(context);
                      onOpenWeather();
                    },
                  ),
                  RotalinkDrawerTile(
                    icon: Icons.calendar_month_outlined,
                    title: AppStrings.drawerHolidays,
                    onTap: () => openRoute(RotalinkShellRoutes.holidays),
                  ),
                  RotalinkDrawerTile(
                    icon: Icons.send_outlined,
                    title: AppStrings.drawerSuggestion,
                    onTap: () => openRoute(RotalinkShellRoutes.suggestion),
                  ),
                  RotalinkDrawerTile(
                    icon: Icons.language_outlined,
                    title: AppStrings.drawerWebsite,
                    onTap: () => unawaited(_openWebsite(context)),
                  ),
                  RotalinkDrawerTile(
                    icon: Icons.share_outlined,
                    title: AppStrings.drawerShareApp,
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(Share.share(StoreLinks.drawerShareMessage()));
                    },
                  ),
                  const DrawerSocialSection(),
                  RotalinkDrawerTile(
                    icon: Icons.settings_outlined,
                    title: AppStrings.drawerSettings,
                    onTap: () => openRoute(RotalinkShellRoutes.settings),
                  ),
                  RotalinkDrawerTile(
                    icon: Icons.info_outline_rounded,
                    title: AppStrings.drawerAbout,
                    onTap: () => openRoute(RotalinkShellRoutes.about),
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
