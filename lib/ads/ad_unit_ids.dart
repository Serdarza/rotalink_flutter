import 'dart:io' show Platform;

/// Android ve iOS için ayrı AdMob reklam birimi kimlikleri.
abstract final class AdUnitIds {
  // ─── Android ──────────────────────────────────────────────────────────────
  static const String _androidAppId       = 'ca-app-pub-6478556288740067~6800762661';
  static const String _androidBanner      = 'ca-app-pub-6478556288740067/9417170109';
  static const String _androidInterstitial= 'ca-app-pub-6478556288740067/7001215166';
  static const String _androidNativeList  = 'ca-app-pub-6478556288740067/2117264587';

  // ─── iOS ──────────────────────────────────────────────────────────────────
  static const String _iosAppId           = 'ca-app-pub-6478556288740067~6588925851';
  static const String _iosBanner          = 'ca-app-pub-6478556288740067/3449514789';
  static const String _iosInterstitial    = 'ca-app-pub-6478556288740067/4219670970';
  static const String _iosNativeList      = 'ca-app-pub-6478556288740067/1593507634';

  // ─── Aktif platform ───────────────────────────────────────────────────────
  static String get appId        => Platform.isIOS ? _iosAppId        : _androidAppId;
  static String get banner       => Platform.isIOS ? _iosBanner       : _androidBanner;
  static String get interstitial => Platform.isIOS ? _iosInterstitial : _androidInterstitial;
  static String get nativeList   => Platform.isIOS ? _iosNativeList   : _androidNativeList;
}
