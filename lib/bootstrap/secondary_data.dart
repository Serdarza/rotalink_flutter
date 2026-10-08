import 'dart:async';

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
}
