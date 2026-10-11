import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/social_links.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import 'rotalink_drawer_tile.dart';

/// Hamburger menü — açılır «Sosyal Medya Hesaplarımız» sekmesi.
class DrawerSocialSection extends StatefulWidget {
  const DrawerSocialSection({super.key});

  @override
  State<DrawerSocialSection> createState() => _DrawerSocialSectionState();
}

class _DrawerSocialSectionState extends State<DrawerSocialSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RotalinkDrawerTile(
          icon: Icons.campaign_outlined,
          title: AppStrings.drawerSocialMedia,
          trailing: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            color: AppColors.textMutedOf(context),
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                _SocialLinkTile(
                  iconAsset: SocialLinks.instagramIcon,
                  title: AppStrings.drawerSocialInstagram,
                  subtitle: AppStrings.drawerSocialInstagramHandle,
                  onTap: () => _openSocialLink(context, SocialLinks.instagram),
                ),
                const SizedBox(height: 8),
                _SocialLinkTile(
                  iconAsset: SocialLinks.facebookIcon,
                  title: AppStrings.drawerSocialFacebook,
                  subtitle: AppStrings.drawerSocialFacebookHandle,
                  onTap: () => _openSocialLink(context, SocialLinks.facebook),
                ),
              ],
            ),
          ),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Future<void> _openSocialLink(BuildContext context, String url) async {
    Navigator.pop(context);
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        _showError(context);
      }
    } catch (_) {
      if (context.mounted) _showError(context);
    }
  }

  void _showError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.drawerSocialOpenFailed)),
    );
  }
}

class _SocialLinkTile extends StatelessWidget {
  const _SocialLinkTile({
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String iconAsset;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoftOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  iconAsset,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.textStrongOf(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textMutedOf(context),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
