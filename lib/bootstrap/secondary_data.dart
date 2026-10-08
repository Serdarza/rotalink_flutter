import 'dart:async';

import '../ads/ad_service.dart';
import '../ads/discover_native_ad_pool.dart';
import '../billing/pro_service.dart';
import '../data/campaign_repository.dart';
import '../data/facility_address_repository.dart';
import '../data/facility_price_repository.dart';
import '../data/gezi_yemek_repository.dart';
import '../data/kamp_repository.dart';
import '../data/sosyal_menu_repository.dart';

/// Fiyat, adres, gezi ve kampanya verisi; ana ekranı bekletmeden yüklenir.
Future<void> warmSecondaryData() async {
  await Future.wait<void>([
    CampaignRepository.instance.ensureLocalDataReady(),
    FacilityPriceRepository.instance.ensureLocalDataReady(),
    FacilityAddressRepository.instance.ensureLocalDataReady(),
    GeziYemekRepository.instance.ensureLocalDataReady(),
    SosyalMenuRepository.instance.ensureLocalDataReady(),
    KampRepository.instance.ensureLoaded(),
  ]);
  final campaignCount = CampaignRepository.instance.currentCampaigns.length;
  if (campaignCount > 0 && !ProService.instance.isAdFree) {
    // AdMob SDK hazır olmadan istek atılmasın (Android/iOS).
    await AdService.instance.whenSdkReady();
    if (!ProService.instance.isAdFree) {
      unawaited(DiscoverNativeAdPool.instance.ensureAds(campaignCount));
    }
  }
}
