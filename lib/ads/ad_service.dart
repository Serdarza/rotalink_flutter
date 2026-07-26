import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../billing/pro_service.dart';
import 'ad_unit_ids.dart';
import 'discover_native_ad_pool.dart';
import 'rewarded_unlock_result.dart';

/// Geçiş (interstitial) reklam zamanlayıcısı.
///
/// Android ve iOS aynı akışı kullanır (unit ID’ler platforma göre ayrıdır):
/// banner, native (her 5 içerikte 1, en fazla 12), interstitial, rewarded.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static const bool adsEnabled = true;
  static const int _defaultIntervalMinutes = 5;
  static const int _minIntervalMinutes = 1;
  static const int _maxIntervalMinutes = 60;
  static const Duration _loadFailRetry = Duration(minutes: 1);

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  Timer? _scheduler;
  Completer<void>? _loading;
  Completer<void>? _rewardedLoading;

  DateTime? _sessionStartedAt;
  DateTime? _lastShownAt;
  DateTime? _suppressUntil;
  int _intervalMinutes = _defaultIntervalMinutes;
  bool _schedulerRunning = false;
  bool _initialized = false;
  bool _sdkReady = false;
  Completer<void>? _sdkReadyCompleter;
  bool _isForeground = true;
  bool _awaitingReturnFromExternal = false;
  /// Ödüllü reklam açıkken geçiş üstüne binmesin.
  bool _rewardedShowing = false;

  /// [MobileAds.initialize] tamamlanana kadar bekler.
  /// Native / banner yüklemeleri SDK hazır olmadan tetiklenmesin.
  Future<void> whenSdkReady() async {
    if (!adsEnabled || kIsWeb) return;
    if (_sdkReady) return;
    _sdkReadyCompleter ??= Completer<void>();
    // main bootstrap gecikirse yükleme yine de SDK'yı başlatsın.
    if (!_initialized) {
      unawaited(() async {
        try {
          await initialize();
        } catch (_) {}
      }());
    }
    try {
      await _sdkReadyCompleter!.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      _markSdkReady();
    }
  }

  void _markSdkReady() {
    _sdkReady = true;
    final c = _sdkReadyCompleter ??= Completer<void>();
    if (!c.isCompleted) c.complete();
  }

  /// Maps / telefon / tarayıcı gibi dış uygulamaya çıkmadan önce çağır.
  /// Geri dönüşte geçiş reklamı hemen basılmaz; kullanıcı uygulamaya döner.
  void notifyLeavingToExternalApp() {
    _awaitingReturnFromExternal = true;
    _isForeground = false;
    debugPrint('AdService: external leave — interstitial suppressed on return');
  }

  /// [WidgetsBindingObserver] üzerinden bağla.
  void onAppLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isForeground = true;
        if (_awaitingReturnFromExternal) {
          _awaitingReturnFromExternal = false;
          // Harita vb. dönüşünde reklam şoku olmasın
          _suppressUntil =
              DateTime.now().add(const Duration(seconds: 90));
          debugPrint('AdService: returned from external — suppress 90s');
        }
        if (_schedulerRunning) {
          _armScheduler(reason: 'app_resumed');
        }
        break;
      case AppLifecycleState.inactive:
        // Geçiş reklamı gösterilirken de inactive olur; dokunma.
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _isForeground = false;
        break;
    }
  }

  /// Pro (reklamsız) abonelik etkinse hiçbir reklam gösterilmez.
  bool get _proActive => ProService.instance.isAdFree;

  /// Abonelik satın alındığında / bittiğinde reklam planını günceller.
  void onProStatusChanged() {
    if (!_proActive) {
      if (_initialized) {
        unawaited(preloadInterstitial());
        unawaited(preloadRewarded());
        startInterstitialScheduler();
      }
      return;
    }
    stopScheduler();
    disposeInterstitial();
    disposeRewarded();
    DiscoverNativeAdPool.instance.disposeAll();
    debugPrint('AdService: Pro etkin — tüm reklamlar kapatıldı');
  }

  bool get _isSuppressed {
    final until = _suppressUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _suppressUntil = null;
    return false;
  }

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
    if (!adsEnabled || kIsWeb) {
      _markSdkReady();
      return;
    }
    if (_initialized) {
      await whenSdkReady();
      return;
    }
    _initialized = true;
    _sdkReadyCompleter ??= Completer<void>();
    _sessionStartedAt ??= DateTime.now();

    try {
      // İçerik derecesi (G/PG/…) yalnızca AdMob panelinden — uygulama güncellemesi gerekmez.
      await MobileAds.instance.initialize();
      _markSdkReady();
    } catch (e) {
      // Sonraki açılışta yeniden denenebilsin; bekleyen yüklemeler takılı kalmasın.
      _initialized = false;
      _markSdkReady();
      debugPrint('AdService: MobileAds init hatası: $e');
      rethrow;
    }

    if (_proActive) {
      debugPrint('AdService: Pro etkin — reklam ön yüklemesi atlandı');
      return;
    }

    unawaited(preloadInterstitial());
    unawaited(preloadRewarded());
    startInterstitialScheduler();
  }

  /// Zamanlayıcıyı başlatır (idempotent). Açılışta hemen reklam göstermez.
  void startInterstitialScheduler() {
    if (!adsEnabled || kIsWeb || _proActive) return;
    _sessionStartedAt ??= DateTime.now();
    _schedulerRunning = true;
    _armScheduler(reason: 'start');
  }

  void _armScheduler({required String reason}) {
    if (!_schedulerRunning || !adsEnabled || kIsWeb || _proActive) return;
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
    var wait = elapsed >= interval
        ? const Duration(seconds: 3)
        : interval - elapsed;

    final until = _suppressUntil;
    if (until != null && until.isAfter(now)) {
      final suppressLeft = until.difference(now);
      if (suppressLeft > wait) wait = suppressLeft;
    }
    return wait;
  }

  bool _canShowInterstitial() {
    if (_proActive) return false;
    if (!_isForeground || _isSuppressed || _rewardedShowing) return false;

    final interval = Duration(minutes: _intervalMinutes);
    final now = DateTime.now();

    if (_lastShownAt == null) {
      final started = _sessionStartedAt ?? now;
      return now.difference(started) >= interval;
    }
    return now.difference(_lastShownAt!) >= interval;
  }

  Future<void> _onSchedulerTick() async {
    // Arka plan / dış uygulama / ödüllü reklam: geçiş üstüne binmesin.
    if (!_isForeground || _isSuppressed || _rewardedShowing) {
      _armScheduler(reason: 'deferred_not_ready');
      return;
    }

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
    if (!adsEnabled || kIsWeb || _proActive) return;
    if (_interstitial != null) return;
    if (_loading != null) return _loading!.future;

    await whenSdkReady();
    if (_proActive || _interstitial != null) return;
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
    if (!adsEnabled || kIsWeb || _proActive) return false;
    if (!_isForeground || _isSuppressed || _rewardedShowing) return false;

    if (!_canShowInterstitial()) {
      if (!force) return false;
      // force + süre dolmamışsa (clock sapması) yine gösterme
      return false;
    }

    if (_interstitial == null) {
      await preloadInterstitial();
    }
    if (!_isForeground || _isSuppressed || _rewardedShowing) return false;

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

  // ─── Ödüllü (Rewarded) — fiyat kilidi ──────────────────────────────────────

  Future<void> preloadRewarded() async {
    if (!adsEnabled || kIsWeb || _proActive) return;
    if (_rewarded != null) return;
    if (_rewardedLoading != null) return _rewardedLoading!.future;

    await whenSdkReady();
    if (_proActive || _rewarded != null) return;
    if (_rewardedLoading != null) return _rewardedLoading!.future;

    final done = Completer<void>();
    _rewardedLoading = done;

    RewardedAd.load(
      adUnitId: AdUnitIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded?.dispose();
          _rewarded = ad;
          if (!done.isCompleted) done.complete();
          _rewardedLoading = null;
        },
        onAdFailedToLoad: (err) {
          _rewarded = null;
          if (!done.isCompleted) done.complete();
          _rewardedLoading = null;
          debugPrint('AdService: rewarded load failed: $err');
        },
      ),
    );

    return done.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        if (!done.isCompleted) done.complete();
        _rewardedLoading = null;
      },
    );
  }

  /// Fiyat kilidi için ödüllü reklam.
  ///
  /// Ödüllü açıkken geçiş basılmaz; bittikten sonra GitHub
  /// `reklam_bekleme_suresi` kadar beklenir.
  Future<RewardedUnlockResult> showRewardedForPriceUnlock() async {
    // Pro aboneler için fiyat kilidi yok.
    if (!adsEnabled || kIsWeb || _proActive) return RewardedUnlockResult.bypass;

    if (_rewarded == null) {
      await preloadRewarded();
    }
    final ad = _rewarded;
    if (ad == null) return RewardedUnlockResult.unavailable;

    final result = Completer<RewardedUnlockResult>();
    var earned = false;
    var failedToShow = false;
    _rewardedShowing = true;
    _scheduler?.cancel();

    void finishRewarded(RewardedUnlockResult value) {
      _rewardedShowing = false;
      _lastShownAt = DateTime.now();
      unawaited(preloadRewarded());
      _armScheduler(reason: 'rewarded_finished');
      if (!result.isCompleted) result.complete(value);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (RewardedAd dismissed) {
        dismissed.dispose();
        if (identical(_rewarded, dismissed)) {
          _rewarded = null;
        }
        if (failedToShow) {
          finishRewarded(RewardedUnlockResult.unavailable);
        } else if (earned) {
          finishRewarded(RewardedUnlockResult.earned);
        } else {
          finishRewarded(RewardedUnlockResult.dismissed);
        }
      },
      onAdFailedToShowFullScreenContent: (RewardedAd failed, AdError err) {
        failed.dispose();
        if (identical(_rewarded, failed)) {
          _rewarded = null;
        }
        debugPrint('AdService: rewarded failed to show: $err');
        failedToShow = true;
        finishRewarded(RewardedUnlockResult.unavailable);
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (AdWithoutView _, RewardItem reward) {
          earned = true;
        },
      );
    } catch (e) {
      debugPrint('AdService: rewarded show threw: $e');
      finishRewarded(RewardedUnlockResult.unavailable);
    }

    return result.future;
  }

  void disposeRewarded() {
    _rewarded?.dispose();
    _rewarded = null;
  }

  /// Uygulama kapanırken veya test için zamanlayıcıyı tamamen durdurur.
  void stopScheduler() {
    _scheduler?.cancel();
    _scheduler = null;
    _schedulerRunning = false;
  }
}
