import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_unit_ids.dart';

/// Kotlin `activity_main` altındaki `AdView` (BANNER, `9417170109`).
class RotalinkBannerAd extends StatefulWidget {
  const RotalinkBannerAd({super.key, this.adsEnabled = true});

  final bool adsEnabled;

  @override
  State<RotalinkBannerAd> createState() => _RotalinkBannerAdState();
}

class _RotalinkBannerAdState extends State<RotalinkBannerAd> {
  BannerAd? _banner;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!widget.adsEnabled || kIsWeb) return;
    _banner = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          if (mounted) setState(() => _failed = true);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.adsEnabled || kIsWeb) {
      return const SizedBox.shrink();
    }
    if (_failed || _banner == null) {
      return const SizedBox.shrink();
    }
    if (!_loaded) {
      return const SizedBox(
        height: 52,
        width: double.infinity,
        child: ColoredBox(
          color: Color(0xFFF5F5F5),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    return Material(
      elevation: 2,
      color: Colors.white,
      child: SizedBox(
        height: _banner!.size.height.toDouble(),
        width: double.infinity,
        child: Center(child: AdWidget(ad: _banner!)),
      ),
    );
  }
}
