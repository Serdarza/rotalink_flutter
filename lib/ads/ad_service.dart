import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_unit_ids.dart';

/// Kotlin `MyApplication.setupFamilyFriendlyAds` + `MainActivity` reklam akışı.
///
/// - [initialize]: `MobileAds.initialize` + G içerik derecesi.
/// - [scheduleLaunchInterstitialPattern]: Açılış anından itibaren **1 dk** sonra
///   ilk geçiş reklamı; ardından her **3 dakikada** bir tekrar.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static const bool adsEnabled = true;

  /// İlk gösterim zamanı (saniye): 1 dk.
  static const List<int> _offsetsInCycleSec = [60];

  /// Döngü uzunluğu: her tekrarda bu kadar saniye eklenir (3 dk).
  static const int _cycleLengthSec = 180;

  InterstitialAd? _interstitial;
  Timer? _launchTimer;

  /// Ana ekran [scheduleLaunchInterstitialPattern] çağırdığında sıfırlanır.
  DateTime? _interstitialSessionStart;
  int _interstitialEventIndex = 0;

  Future<void> initialize() async {
    if (!adsEnabled || kIsWeb) return;
    await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        maxAdContentRating: MaxAdContentRating.g,
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.yes,
        tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.yes,
      ),
    );
  }

  void cancelLaunchInterstitialTimer() {
    _launchTimer?.cancel();
    _launchTimer = null;
  }

  Future<void> scheduleLaunchInterstitialPattern() async {
    if (!adsEnabled || kIsWeb) return;
    cancelLaunchInterstitialTimer();

    _interstitialSessionStart = DateTime.now();
    _interstitialEventIndex = 0;

    await preloadInterstitial();
    _scheduleNextInterstitialInChain();
  }

  void _scheduleNextInterstitialInChain() {
    final start = _interstitialSessionStart;
    if (start == null) return;

    const maxSkip = 500;
    var skips = 0;
    while (skips < maxSkip) {
      final cycle = _interstitialEventIndex ~/ _offsetsInCycleSec.length;
      final slot = _interstitialEventIndex % _offsetsInCycleSec.length;
      final targetSec = cycle * _cycleLengthSec + _offsetsInCycleSec[slot];
      final elapsed = DateTime.now().difference(start).inSeconds;
      final waitSec = targetSec - elapsed;
      if (waitSec >= 1) {
        _launchTimer = Timer(Duration(seconds: waitSec), () {
          _tryShowLaunchInterstitial();
          _interstitialEventIndex++;
          _scheduleNextInterstitialInChain();
        });
        return;
      }
      _interstitialEventIndex++;
      skips++;
    }
  }

  void _tryShowLaunchInterstitial() {
    if (!adsEnabled || kIsWeb) return;
    final ad = _interstitial;
    if (ad != null) {
      ad.show();
    } else {
      unawaited(preloadInterstitial());
    }
  }

  Future<void> preloadInterstitial() async {
    if (!adsEnabled || kIsWeb) return;
    final done = Completer<void>();

    InterstitialAd.load(
      adUnitId: AdUnitIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial?.dispose();
          _interstitial = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (InterstitialAd dismissed) {
              dismissed.dispose();
              _interstitial = null;
              unawaited(preloadInterstitial());
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd failed, AdError err) {
              failed.dispose();
              _interstitial = null;
              unawaited(preloadInterstitial());
            },
          );
          if (!done.isCompleted) done.complete();
        },
        onAdFailedToLoad: (_) {
          _interstitial = null;
          if (!done.isCompleted) done.complete();
        },
      ),
    );

    return done.future.timeout(const Duration(seconds: 12), onTimeout: () {
      if (!done.isCompleted) done.complete();
    });
  }

  /// Hazırsa geçiş reklamını gösterir; değilse önceden yükleyip gösterir.
  Future<void> showInterstitialIfReady() async {
    if (!adsEnabled || kIsWeb) return;
    if (_interstitial != null) {
      _interstitial!.show();
    } else {
      await preloadInterstitial();
      _interstitial?.show();
    }
  }

  void disposeInterstitial() {
    _interstitial?.dispose();
    _interstitial = null;
  }
}
