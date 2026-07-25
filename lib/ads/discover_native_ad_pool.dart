import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../billing/pro_service.dart';
import 'ad_service.dart';
import 'discover_native_merge.dart';

/// Keşfet native reklamları — sekme her açıldığında yeniden yüklenmesin.
///
/// Önemli: [NativeAd.dispose] asla [AdWidget] hâlâ ağaçtayken senkron
/// çağrılmaz; aksi halde Keşfet kaydırırken native crash olur.
class DiscoverNativeAdPool {
  DiscoverNativeAdPool._() {
    // Pro etkinleşince havuz boşaltılır; yeni yükleme yapılmaz.
    ProService.instance.isPro.addListener(() {
      if (ProService.instance.isAdFree) disposeAll();
    });
  }

  static final DiscoverNativeAdPool instance = DiscoverNativeAdPool._();

  final List<NativeAd> _ads = [];
  Future<List<NativeAd>>? _loadFuture;

  bool get _proActive => ProService.instance.isAdFree;

  List<NativeAd> snapshot(int campaignCount) {
    if (_proActive) return const [];
    final needed = DiscoverNativeMerge.nativeSlotsNeeded(campaignCount);
    if (needed <= 0 || _ads.isEmpty) {
      return const [];
    }
    return List<NativeAd>.from(_ads.take(needed));
  }

  bool hasAdsFor(int campaignCount) {
    if (_proActive) return true; // Pro'da yükleme beklenmez.
    final needed = DiscoverNativeMerge.nativeSlotsNeeded(campaignCount);
    return needed > 0 && _ads.length >= needed;
  }

  void disposeAll() {
    final dying = List<NativeAd>.from(_ads);
    _ads.clear();
    _loadFuture = null;
    _scheduleDispose(dying);
  }

  Future<List<NativeAd>> ensureAds(int campaignCount) async {
    if (!AdService.adsEnabled || kIsWeb || campaignCount <= 0 || _proActive) {
      return const [];
    }

    final needed = DiscoverNativeMerge.nativeSlotsNeeded(campaignCount);
    if (needed <= 0) return const [];

    // Yeterli reklam varsa yeniden yükleme/dispose yapma — scroll crash önler.
    if (_ads.length >= needed) {
      return List<NativeAd>.from(_ads.take(needed));
    }

    return _loadFuture ??= _load(needed);
  }

  Future<List<NativeAd>> _load(int needed) async {
    final previous = List<NativeAd>.from(_ads);
    try {
      final loaded = await DiscoverNativeMerge.loadPool(needed);
      if (_proActive) {
        _scheduleDispose(loaded);
        _scheduleDispose(previous);
        _ads.clear();
        return const [];
      }
      _ads
        ..clear()
        ..addAll(loaded);
      // Eski reklamları UI bırakana kadar beklet.
      _scheduleDispose(previous);
      return List<NativeAd>.from(_ads);
    } finally {
      _loadFuture = null;
    }
  }

  void _scheduleDispose(List<NativeAd> ads) {
    if (ads.isEmpty) return;
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      for (final ad in ads) {
        try {
          ad.dispose();
        } catch (_) {}
      }
    });
  }
}
