import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_service.dart';
import '../ads/ad_unit_ids.dart';
import '../billing/pro_service.dart';

/// Kotlin `activity_main` altındaki `AdView` (BANNER, `9417170109`).
///
/// Pro abonelikte banner hiç yüklenmez; abonelik oturum içinde
/// etkinleşirse mevcut banner anında kaldırılır.
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
  int _loadAttempts = 0;

  bool get _adsAllowed =>
      widget.adsEnabled && !kIsWeb && !ProService.instance.isAdFree;

  @override
  void initState() {
    super.initState();
    ProService.instance.isPro.addListener(_onProChanged);
    unawaited(_loadIfAllowed());
  }

  Future<void> _loadIfAllowed() async {
    if (!_adsAllowed || _banner != null) return;
    await AdService.instance.whenSdkReady();
    if (!mounted || !_adsAllowed || _banner != null) return;

    _loadAttempts++;
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
          if (!mounted) return;
          _banner = null;
          // İlk başarısızlıktan sonra bir kez daha dene (SDK / ağ gecikmesi).
          if (_loadAttempts < 2 && _adsAllowed) {
            Future<void>.delayed(const Duration(seconds: 2), () {
              if (mounted && _adsAllowed && _banner == null) {
                unawaited(_loadIfAllowed());
              }
            });
            return;
          }
          setState(() => _failed = true);
        },
      ),
    )..load();
  }

  void _onProChanged() {
    if (!mounted) return;
    if (ProService.instance.isAdFree) {
      _banner?.dispose();
      _banner = null;
      _loaded = false;
      _failed = false;
      setState(() {});
    } else {
      _failed = false;
      _loadAttempts = 0;
      unawaited(_loadIfAllowed());
      setState(() {});
    }
  }

  @override
  void dispose() {
    ProService.instance.isPro.removeListener(_onProChanged);
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_adsAllowed) {
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
