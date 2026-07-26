import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
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

  /// SDK hazır + boş/eksik sonuçta birkaç kez yeniden dener (Android/iOS).
  Future<List<NativeAd>> _load(int needed) async {
    await AdService.instance.whenSdkReady();
    final previous = List<NativeAd>.from(_ads);
    try {
      var loaded = <NativeAd>[];
      for (var attempt = 0; attempt < 3; attempt++) {
        if (_proActive) break;

        final batch = await DiscoverNativeMerge.loadPool(
          needed - loaded.length,
        );
        if (batch.isNotEmpty) {
          loaded = [...loaded, ...batch];
        }

        debugPrint(
          '[NativePool] attempt ${attempt + 1}: ${loaded.length}/$needed',
        );

        if (loaded.length >= needed) break;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 700 * (attempt + 1)),
          );
        }
      }

      if (_proActive) {
        _scheduleDispose(loaded);
        _scheduleDispose(previous);
        _ads.clear();
        return const [];
      }

      if (loaded.isNotEmpty) {
        _ads
          ..clear()
          ..addAll(loaded);
        _scheduleDispose(previous);
      }
      // Boş kaldıysa önceki (varsa) korunur; UI tamamen reklamsız kalmasın.
      return List<NativeAd>.from(_ads.take(needed));
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
