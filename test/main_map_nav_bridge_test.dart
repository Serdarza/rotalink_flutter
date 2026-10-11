import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/navigation/main_map_nav_bridge.dart';

void main() {
  test('dispose clears every dashboard and map navigation callback', () {
    final bridge = MainMapNavBridge();
    bridge.resetToHome = () {};
    bridge.openCategory = (_, _) async {};
    bridge.openSearchQuery = (_, _) async {};
    bridge.openMenu = () {};
    bridge.openWeather = (_) async {};
    bridge.openEmergency = (_) async {};
    bridge.hasActiveOverlay = () => true;
    bridge.onExternalSurfaceChanged = (_) {};
    bridge.handleSystemBack = () async {};
    bridge.applyRoutePlan = (_) async {};

    bridge.dispose();

    expect(bridge.resetToHome, isNull);
    expect(bridge.openCategory, isNull);
    expect(bridge.openSearchQuery, isNull);
    expect(bridge.openMenu, isNull);
    expect(bridge.openWeather, isNull);
    expect(bridge.openEmergency, isNull);
    expect(bridge.hasActiveOverlay, isNull);
    expect(bridge.onExternalSurfaceChanged, isNull);
    expect(bridge.handleSystemBack, isNull);
    expect(bridge.applyRoutePlan, isNull);
  });
}
