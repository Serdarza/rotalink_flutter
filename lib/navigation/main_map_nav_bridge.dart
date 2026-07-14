import 'package:flutter/material.dart';

import '../data/firebase_rota_repository.dart';

/// [MainMapScreen] ↔ [RotalinkMainShell] köprüsü (alt menü eylemleri).
class MainMapNavBridge {
  VoidCallback? resetToHome;
  Future<void> Function(BuildContext context)? openFavorites;
  Future<void> Function(BuildContext context, RotaDataState? data)? openSearch;
  Future<void> Function()? openRoutePlan;
  VoidCallback? onRoutePlanningDismissed;
  Future<void> Function()? handleSystemBack;

  void dispose() {
    resetToHome = null;
    openFavorites = null;
    openSearch = null;
    openRoutePlan = null;
    onRoutePlanningDismissed = null;
    handleSystemBack = null;
  }
}
