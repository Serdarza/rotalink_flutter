import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_unit_ids.dart';
import 'ad_service.dart';
import '../models/campaign.dart';

/// Kotlin [DiscoverActivity.NATIVE_AD_EVERY_N_CAMPAIGNS] / [MAX_NATIVE_ADS_TO_LOAD].
abstract final class DiscoverNativeMerge {
  static const int everyNCampaigns = 5;
  static const int maxAdsToLoad = 12;

  /// Tam liste uzunluğuna göre yüklenecek native sayısı (`all.size / 5`, üst sınır 12).
  static int nativeSlotsNeeded(int allCampaignCount) {
    if (allCampaignCount <= 0) return 0;
    return (allCampaignCount ~/ everyNCampaigns).clamp(0, maxAdsToLoad);
  }

  static List<Object> mergeFiltered(
    List<Campaign> filtered,
    List<NativeAd> loadedAds,
  ) {
    if (!AdService.adsEnabled || kIsWeb || loadedAds.isEmpty) {
      return List<Object>.from(filtered);
    }
    final out = <Object>[];
    var adIdx = 0;
    for (var index = 0; index < filtered.length; index++) {
      out.add(filtered[index]);
      if ((index + 1) % everyNCampaigns == 0 && adIdx < loadedAds.length) {
        out.add(loadedAds[adIdx++]);
      }
    }
    return out;
  }

  static Future<NativeAd?> loadOneNative() {
    if (kIsWeb) return Future.value();
    final c = Completer<NativeAd?>();
    late final NativeAd ad;
    ad = NativeAd(
      adUnitId: AdUnitIds.nativeList,
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (!c.isCompleted) c.complete(ad);
        },
        onAdFailedToLoad: (failed, err) {
          failed.dispose();
          if (!c.isCompleted) c.complete(null);
        },
      ),
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFFFFFFFF),
        cornerRadius: 12,
      ),
    );
    ad.load();
    return c.future;
  }

  /// Kotlin [AdMobNativeAdUtils.loadNativeAds] ile aynı: [count] paralel istek, tamamlanınca dön.
  static Future<List<NativeAd>> loadPool(int count) async {
    if (count <= 0 || kIsWeb) return const [];
    final futures = List<Future<NativeAd?>>.generate(
      count,
      (_) => loadOneNative(),
    );
    final results = await Future.wait(futures);
    return results.whereType<NativeAd>().toList();
  }
}
