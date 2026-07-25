import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../billing/pro_service.dart';
import 'ad_service.dart';
import 'discover_native_merge.dart';

/// Keşfet native reklamları — sekme her açıldığında yeniden yüklenmesin.
class DiscoverNativeAdPool {
  DiscoverNativeAdPool._() {
    // Pro etkinleşince havuz anında boşaltılır; yeni yükleme yapılmaz.
    ProService.instance.isPro.addListener(() {
      if (ProService.instance.isAdFree) disposeAll();
    });
  }

  static final DiscoverNativeAdPool instance = DiscoverNativeAdPool._();

  final List<NativeAd> _ads = [];
  int _campaignCount = 0;
  Future<List<NativeAd>>? _loadFuture;

  bool get _proActive => ProService.instance.isAdFree;

  List<NativeAd> snapshot(int campaignCount) {
    if (_proActive) return const [];
    final needed = DiscoverNativeMerge.nativeSlotsNeeded(campaignCount);
    if (needed <= 0 || _campaignCount != campaignCount || _ads.isEmpty) {
      return const [];
    }
    return List<NativeAd>.from(_ads.take(needed));
  }

  bool hasAdsFor(int campaignCount) {
    if (_proActive) return true; // Pro'da yükleme beklenmez.
    final needed = DiscoverNativeMerge.nativeSlotsNeeded(campaignCount);
    return needed > 0 &&
        _campaignCount == campaignCount &&
        _ads.length >= needed;
  }

  void disposeAll() {
    for (final ad in _ads) {
      ad.dispose();
    }
    _ads.clear();
    _campaignCount = 0;
  }

  Future<List<NativeAd>> ensureAds(int campaignCount) async {
    if (!AdService.adsEnabled || kIsWeb || campaignCount <= 0 || _proActive) {
      return const [];
    }

    final needed = DiscoverNativeMerge.nativeSlotsNeeded(campaignCount);
    if (needed <= 0) return const [];

    if (_campaignCount == campaignCount && _ads.length >= needed) {
      return List<NativeAd>.from(_ads.take(needed));
    }

    return _loadFuture ??= _load(needed, campaignCount);
  }

  Future<List<NativeAd>> _load(int needed, int campaignCount) async {
    try {
      for (final ad in _ads) {
        ad.dispose();
      }
      _ads.clear();

      final loaded = await DiscoverNativeMerge.loadPool(needed);
      _ads.addAll(loaded);
      _campaignCount = campaignCount;
      return List<NativeAd>.from(_ads);
    } finally {
      _loadFuture = null;
    }
  }
}
