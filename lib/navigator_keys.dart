import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// [MaterialApp.navigatorKey] — izin sonrası [showDialog] için güvenilir bağlam.
final GlobalKey<NavigatorState> rotalinkNavigatorKey = GlobalKey<NavigatorState>();

/// [RotalinkMainShell] gövde gezgini — alt menü her zaman görünür kalır.
final GlobalKey<NavigatorState> rotalinkShellBodyNavigatorKey =
    GlobalKey<NavigatorState>();

/// Kabuk gezginine güvenli push — overlay/IME animasyonu bittikten sonra.
Future<T?> pushOnShellNavigator<T>(Route<T> route) =>
    _pushDeferred<T>(rotalinkShellBodyNavigatorKey.currentState, route);

/// Kampanya gibi üst sayfa açıkken önce ana rotaya inmek anasayfayı gösterir.
/// Üst sayfanın yerine yeni sayfa konur.
Future<T?> pushOrReplaceOnShellNavigator<T>(Route<T> route) => _pushDeferred<T>(
  rotalinkShellBodyNavigatorKey.currentState,
  route,
  replaceIfCanPop: true,
);

/// Tam ekran sayfalar (Rota) — kabuk gezgininde overlay hatası riski olan akışlar için.
Future<T?> pushOnRootNavigator<T>(Route<T> route) =>
    _pushDeferred<T>(rotalinkNavigatorKey.currentState, route);

Future<T?> _pushDeferred<T>(
  NavigatorState? nav,
  Route<T> route, {
  bool replaceIfCanPop = false,
}) {
  final completer = Completer<T?>();
  void pushNow() {
    if (nav == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final Future<T?> opened = replaceIfCanPop && nav.canPop()
        ? nav.pushReplacement<T, void>(route)
        : nav.push<T>(route);
    opened.then((value) {
      if (!completer.isCompleted) completer.complete(value);
    });
  }

  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks) {
    pushNow();
  } else {
    WidgetsBinding.instance.addPostFrameCallback((_) => pushNow());
  }
  return completer.future;
}
