import 'package:flutter/material.dart';
import 'firebase_analytics_service.dart';

/// Navigator ile ekran geçişlerini izleyen ve Firebase Analytics'e bildiren observer
class AnalyticsObserver extends RouteObserver<PageRoute<dynamic>> {
  final FirebaseAnalyticsService _analyticsService;

  AnalyticsObserver(this._analyticsService);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _sendScreenView(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _sendScreenView(newRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _sendScreenView(previousRoute);
    }
  }

  /// Geçerli rotanın ekran adını alır ve Analytics'e bildirir
  Future<void> _sendScreenView(Route<dynamic> route) async {
    final String? screenName = _getScreenName(route);
    if (screenName != null) {
      await _analyticsService.setCurrentScreen(
        screenName: screenName,
        screenClass: screenName,
      );
    }
  }

  /// Route'tan ekran adını çıkartır
  /// Route settings.name varsa onu kullanır, yoksa route'un tip adını döner.
  String? _getScreenName(Route<dynamic> route) {
    return route.settings.name ?? route.runtimeType.toString();
  }
}
