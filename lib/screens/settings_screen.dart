import 'package:flutter/foundation.dart';
import 'device_test_screen.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../navigation/rotalink_shell_scope.dart';
import '../services/announcement_notification_scheduler.dart';
import '../services/campaign_push_service.dart';
import '../services/app_notifications_service.dart';
import '../services/holiday_notification_scheduler.dart';
import '../theme/app_colors.dart';
import '../theme/theme_mode_prefs.dart';

/// Görünüm ve bildirim tercihleri.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _announcementsEnabled;
  bool? _campaignPushEnabled;
  bool? _holidayRemindersEnabled;
  bool? _adminNotificationsEnabled;

  @override
  void initState() {
    super.initState();
    unawaited(_loadNotifications());
  }

  Future<void> _loadNotifications() async {
    final announcements = await AnnouncementNotificationScheduler.isEnabled();
    final campaigns = await CampaignPushService.isEnabled();
    final holidays = await HolidayNotificationScheduler.isEnabled();
    final admin = await AppNotificationsService.isEnabled();
    if (!mounted) return;
    setState(() {
      _announcementsEnabled = announcements;
      _campaignPushEnabled = campaigns;
      _holidayRemindersEnabled = holidays;
      _adminNotificationsEnabled = admin;
    });
  }

  Future<void> _toggleHolidayReminders(bool value) async {
    setState(() => _holidayRemindersEnabled = value);
    final permitted = await HolidayNotificationScheduler.setEnabled(value);
    if (value && !permitted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bildirim izni kapalı. Bildirim almak için telefon ayarlarından '
            'Rotalink bildirimlerine izin verin.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleAnnouncements(bool value) async {
    setState(() => _announcementsEnabled = value);
    await AnnouncementNotificationScheduler.setEnabled(value);
  }

  Future<void> _toggleAdminNotifications(bool value) async {
    setState(() => _adminNotificationsEnabled = value);
    final permitted = await AppNotificationsService.setEnabled(value);
    if (value && !permitted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bildirim almak için telefon ayarlarından Rotalink bildirimlerine izin verin.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleCampaignPush(bool value) async {
    setState(() => _campaignPushEnabled = value);
    final permitted = await CampaignPushService.setEnabled(value);
    if (value && !permitted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bildirim izni kapalı. Bildirim almak için telefon ayarlarından '
            'Rotalink bildirimlerine izin verin.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = RotalinkShellScope.scrollBottomPadding(context);
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.drawerSettings)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
        children: [
          if (kDebugMode &&
              !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS)) ...[
            _card(
              context,
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(
                  Icons.phonelink_setup,
                  color: AppColors.primary,
                ),
                title: const Text('Yönetici testi'),
                subtitle: const Text(
                  'Pop-up ve bildirimleri yalnızca bu telefonda deneyin.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DeviceTestScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
          ],
          _sectionTitle(context, AppStrings.drawerAppearance),
          const SizedBox(height: 8),
          _card(
            context,
            padding: EdgeInsets.zero,
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeModePrefs.mode,
              builder: (context, selected, _) {
                return SwitchListTile.adaptive(
                  value: selected == ThemeMode.dark,
                  onChanged: (value) => ThemeModePrefs.setDark(value),
                  secondary: const Icon(
                    Icons.dark_mode_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text(AppStrings.drawerDarkModeTitle),
                  subtitle: Text(
                    AppStrings.drawerDarkModeSubtitle,
                    style: TextStyle(
                      color: AppColors.textMutedOf(context),
                      height: 1.35,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          _sectionTitle(context, 'Bildirimler'),
          const SizedBox(height: 8),
          _card(
            context,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _adminNotificationsEnabled ?? true,
                  onChanged: _adminNotificationsEnabled == null
                      ? null
                      : _toggleAdminNotifications,
                  secondary: const Icon(
                    Icons.notifications_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Rotalink bildirimleri'),
                  subtitle: const Text(
                    'Rotalink’ten gelen anlık duyuru ve bilgilendirmeler.',
                  ),
                ),
                Divider(height: 1, color: AppColors.borderOf(context)),
                SwitchListTile.adaptive(
                  value: _announcementsEnabled ?? true,
                  onChanged: _announcementsEnabled == null
                      ? null
                      : _toggleAnnouncements,
                  secondary: const Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Duyuru bildirimleri'),
                  subtitle: Text(
                    'Haftada en fazla bir kez, Perşembe 21:00 civarı tatil, '
                    'tesis ve kampanya önerileri.',
                    style: TextStyle(
                      color: AppColors.textMutedOf(context),
                      height: 1.35,
                    ),
                  ),
                ),
                Divider(height: 1, color: AppColors.borderOf(context)),
                SwitchListTile.adaptive(
                  value: _campaignPushEnabled ?? true,
                  onChanged: _campaignPushEnabled == null
                      ? null
                      : _toggleCampaignPush,
                  secondary: const Icon(
                    Icons.campaign_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text(CampaignPushService.settingTitle),
                  subtitle: Text(
                    CampaignPushService.settingDescription,
                    style: TextStyle(
                      color: AppColors.textMutedOf(context),
                      height: 1.35,
                    ),
                  ),
                ),
                Divider(height: 1, color: AppColors.borderOf(context)),
                SwitchListTile.adaptive(
                  value: _holidayRemindersEnabled ?? true,
                  onChanged: _holidayRemindersEnabled == null
                      ? null
                      : _toggleHolidayReminders,
                  secondary: const Icon(
                    Icons.event_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text(HolidayNotificationScheduler.settingTitle),
                  subtitle: Text(
                    HolidayNotificationScheduler.settingDescription,
                    style: TextStyle(
                      color: AppColors.textMutedOf(context),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textStrongOf(context),
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: child,
    );
  }
}
