import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads/ad_service.dart';
import '../ads/discover_native_merge.dart';
import '../l10n/app_strings.dart';
import '../models/campaign.dart';
import '../theme/app_colors.dart';

/// Kotlin [CampaignDetailActivity] — alt bölümde native reklam.
class CampaignDetailScreen extends StatefulWidget {
  const CampaignDetailScreen({super.key, required this.campaign});

  final Campaign campaign;

  @override
  State<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends State<CampaignDetailScreen> {
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.serdarza.rotalink';

  NativeAd? _nativeAd;

  Campaign get campaign => widget.campaign;

  String get _dateText {
    final d = campaign.createdAt;
    if (d == null) return 'Tarih: -';
    final fmt = DateFormat('dd.MM.yyyy');
    return 'Tarih: ${fmt.format(d)}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadNative());
  }

  Future<void> _loadNative() async {
    if (!AdService.adsEnabled || kIsWeb) return;
    final ad = await DiscoverNativeMerge.loadOneNative();
    if (mounted) setState(() => _nativeAd = ad);
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  Future<void> _openLink() async {
    final url = campaign.linkUrl?.trim();
    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı yok.')),
        );
      }
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı açılamadı.')),
        );
      }
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı açılamadı.')),
      );
    }
  }

  Future<void> _share() async {
    final buf = StringBuffer()
      ..writeln(campaign.title.trim())
      ..writeln()
      ..writeln(campaign.summary.trim());
    final link = campaign.linkUrl?.trim();
    if (link != null && link.isNotEmpty) {
      buf.writeln();
      buf.writeln(link);
    }
    buf
      ..writeln()
      ..writeln("Rotalink uygulamasını Google Play'den indirebilirsiniz.")
      ..writeln(_playStoreUrl);
    await Share.share(
      buf.toString(),
      subject: campaign.title.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad =
        20 + MediaQuery.viewPaddingOf(context).bottom + MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      appBar: AppBar(
        title: const Text('Kampanya'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad),
          children: [
            Text(
              campaign.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (campaign.organization.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                campaign.organization,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _dateText,
              style: const TextStyle(
                color: AppColors.campaignSummaryMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              campaign.summary,
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
            if (campaign.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: campaign.tags
                    .where((t) => t.trim().isNotEmpty)
                    .map((t) => Chip(label: Text(t.trim())))
                    .toList(),
              ),
            ],
            const SizedBox(height: 28),
            if (campaign.linkUrl != null && campaign.linkUrl!.trim().isNotEmpty)
              FilledButton.icon(
                onPressed: _openLink,
                icon: const Icon(Icons.open_in_new),
                label: const Text(AppStrings.campaignOpenLink),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share),
              label: const Text(AppStrings.share),
            ),
            if (_nativeAd != null) ...[
              const SizedBox(height: 24),
              Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: AdWidget(ad: _nativeAd!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
