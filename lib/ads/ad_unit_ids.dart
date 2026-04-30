import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

abstract final class AdUnitIds {
  static bool get _ios => !kIsWeb && Platform.isIOS;

  static String get appId =>
      _ios ? 'ca-app-pub-6478556288740067~6588925851' : 'ca-app-pub-6478556288740067~6800762661';

  static String get banner =>
      _ios ? 'ca-app-pub-6478556288740067/3449514789' : 'ca-app-pub-6478556288740067/9417170109';

  static String get interstitial =>
      _ios ? 'ca-app-pub-6478556288740067/4219670970' : 'ca-app-pub-6478556288740067/7001215166';

  static String get nativeList =>
      _ios ? 'ca-app-pub-6478556288740067/1593507634' : 'ca-app-pub-6478556288740067/2117264587';
}
