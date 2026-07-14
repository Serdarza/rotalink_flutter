import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_unit_ids.dart';

/// Geçiş (interstitial) reklam zamanlayıcısı.
///
/// Akış:
/// 1. Uygulama açılır → reklam **hemen çıkmaz**.
/// 2. GitHub `reklam_ayar.json` veya Firebase Remote Config `reklam_bekleme_suresi` (dakika) kadar beklenir.
/// 3. İlk geçiş reklamı gösterilir.
/// 4. Sonraki gösterimler aynı süre aralığıyla devam eder.
///
/// Açılışta reklam yok; süre her zaman oturum / son gösterimden ölçülür.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static const bool adsEnabled = true;
  static const int _defaultIntervalMinutes = 5;
  static const int _minIntervalMinutes = 1;
  static const int _maxIntervalMinutes = 60;
  static const Duration _loadFailRetry = Duration(minutes: 1);

  InterstitialAd? _interstitial;
  Timer? _scheduler;
  Completer<void>? _loading;

  DateTime? _sessionStartedAt;
  DateTime? _lastShownAt;
  int _intervalMinutes = _defaultIntervalMinutes;
  bool _schedulerRunning = false;
  bool _initialized = false;

  int get intervalMinutes => _intervalMinutes;

  /// Remote Config’den gelen bekleme süresi (dakika).
  void setAdCooldownMinutes(int minutes) {
    final next = minutes.clamp(_minIntervalMinutes, _maxIntervalMinutes);
    final changed = next != _intervalMinutes;
    _intervalMinutes = next;
    if (changed && _schedulerRunning) {
      // İlk reklam henüz çıkmadıysa yeni süreye göre yeniden planla.
      if (_lastShownAt == null) {
        _armScheduler(reason: 'remote_config_updated');
      }
    }
  }

  Future<void> initialize() async {
    if (!adsEnabled || kIsWeb) return;
    if (_initialized) return;
    _initialized = true;

    _sessionStartedAt ??= DateTime.now();

    await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        maxAdContentRating: MaxAdContentRating.pg,
        tagForChildDirectedTreatment: TagForChildDirectedTreatment.no,
        tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.no,
      ),
    );

    unawaited(preloadInterstitial());
    startInterstitialScheduler();
  }

  /// Zamanlayıcıyı başlatır (idempotent). Açılışta hemen reklam göstermez.
  void startInterstitialScheduler() {
    if (!adsEnabled || kIsWeb) return;
    _sessionStartedAt ??= DateTime.now();
    _schedulerRunning = true;
    _armScheduler(reason: 'start');
  }

  void _armScheduler({required String reason}) {
    if (!_schedulerRunning || !adsEnabled || kIsWeb) return;
    _scheduler?.cancel();

    final wait = _delayUntilNextShow();
    debugPrint(
      'AdService: next interstitial in ${wait.inSeconds}s '
      '(interval=${_intervalMinutes}m, reason=$reason)',
    );
    _scheduler = Timer(wait, () => unawaited(_onSchedulerTick()));
  }

  /// Sonraki gösterime kalan süre.
  /// İlk reklam: uygulama açılışından itibaren [_intervalMinutes].
  /// Sonrakiler: son gösterimden itibaren aynı süre.
  Duration _delayUntilNextShow() {
    final interval = Duration(minutes: _intervalMinutes);
    final now = DateTime.now();
    final anchor = _lastShownAt ?? _sessionStartedAt ?? now;
    final elapsed = now.difference(anchor);
    if (elapsed >= interval) {
      // Hâlâ açılış anı gibi hissettirmemek için çok kısa tampon.
      return const Duration(seconds: 3);
    }
    return interval - elapsed;
  }

  bool _canShowInterstitial() {
    final interval = Duration(minutes: _intervalMinutes);
    final now = DateTime.now();

    if (_lastShownAt == null) {
      final started = _sessionStartedAt ?? now;
      return now.difference(started) >= interval;
    }
    return now.difference(_lastShownAt!) >= interval;
  }

  Future<void> _onSchedulerTick() async {
    final shown = await showInterstitialIfReady(force: true);
    if (!shown) {
      // Yüklenemediyse aralığın tamamını beklemek yerine kısa süre sonra dene.
      unawaited(preloadInterstitial());
      _scheduler?.cancel();
      _scheduler = Timer(_loadFailRetry, () => unawaited(_onSchedulerTick()));
    }
    // Başarılı gösterimde sonraki plan onAdDismissed içinde kurulur.
  }

  Future<void> preloadInterstitial() async {
    if (!adsEnabled || kIsWeb) return;
    if (_interstitial != null) return;
    if (_loading != null) return _loading!.future;

    final done = Completer<void>();
    _loading = done;

    InterstitialAd.load(
      adUnitId: AdUnitIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial?.dispose();
          _interstitial = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (_) {
              _lastShownAt = DateTime.now();
            },
            onAdDismissedFullScreenContent: (InterstitialAd dismissed) {
              dismissed.dispose();
              if (identical(_interstitial, dismissed)) {
                _interstitial = null;
              }
              unawaited(preloadInterstitial());
              _armScheduler(reason: 'ad_dismissed');
            },
            onAdFailedToShowFullScreenContent:
                (InterstitialAd failed, AdError err) {
              failed.dispose();
              if (identical(_interstitial, failed)) {
                _interstitial = null;
              }
              unawaited(preloadInterstitial());
              _armScheduler(reason: 'ad_failed_to_show');
            },
          );
          if (!done.isCompleted) done.complete();
          _loading = null;
        },
        onAdFailedToLoad: (err) {
          _interstitial = null;
          if (!done.isCompleted) done.complete();
          _loading = null;
          debugPrint('AdService: interstitial load failed: $err');
        },
      ),
    );

    return done.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        if (!done.isCompleted) done.complete();
        _loading = null;
      },
    );
  }

  /// Hazırsa gösterir. [force] yalnızca zamanlayıcı için; yine de süre dolmuş olmalı.
  /// Dönüş: reklam gerçekten gösterime verildi mi.
  Future<bool> showInterstitialIfReady({bool force = false}) async {
    if (!adsEnabled || kIsWeb) return false;

    if (!_canShowInterstitial()) {
      if (!force) return false;
      // force + süre dolmamışsa (clock sapması) yine gösterme
      return false;
    }

    if (_interstitial == null) {
      await preloadInterstitial();
    }
    final ad = _interstitial;
    if (ad == null) return false;

    ad.show();
    // onAdShowedFullScreenContent lastShownAt’ı yazar; yedek:
    _lastShownAt ??= DateTime.now();
    return true;
  }

  /// Harita vb. ekran kapanırken yalnızca yüklenmiş reklam nesnesini temizler.
  /// Zamanlayıcı çalışmaya devam eder.
  void disposeInterstitial() {
    _interstitial?.dispose();
    _interstitial = null;
  }

  /// Uygulama kapanırken veya test için zamanlayıcıyı tamamen durdurur.
  void stopScheduler() {
    _scheduler?.cancel();
    _scheduler = null;
    _schedulerRunning = false;
  }
}
