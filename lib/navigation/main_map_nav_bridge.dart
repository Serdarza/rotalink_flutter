import 'package:flutter/material.dart';

import '../data/firebase_rota_repository.dart';
import '../models/route_plan_outcome.dart';
import '../models/misafirhane.dart';

/// [MainMapScreen] ↔ [RotalinkMainShell] köprüsü (alt menü eylemleri).
class MainMapNavBridge {
  VoidCallback? resetToHome;
  Future<void> Function(BuildContext context)? openFavorites;
  Future<void> Function(BuildContext context, RotaDataState? data)? openSearch;
  Future<void> Function(BuildContext context, String query)? openSearchQuery;
  Future<void> Function(BuildContext context, int tabIndex)? openCategory;
  Future<void> Function(BuildContext context, Misafirhane facility)?
  openFacility;
  Misafirhane? Function()? feedbackFacility;
  bool Function()? isFacilityDetailOpen;
  VoidCallback? onDetailVisibilityChanged;
  Future<void> Function()? openRoutePlan;
  Future<void> Function(RoutePlanOutcome outcome)? applyRoutePlan;
  VoidCallback? openMenu;
  Future<void> Function(BuildContext context)? openWeather;
  Future<void> Function(BuildContext context)? openEmergency;
  bool Function()? hasActiveOverlay;
  ValueChanged<bool>? onExternalSurfaceChanged;
  VoidCallback? onRoutePlanningDismissed;
  Future<void> Function()? handleSystemBack;

  void dispose() {
    resetToHome = null;
    openFavorites = null;
    openSearch = null;
    openSearchQuery = null;
    openCategory = null;
    openFacility = null;
    feedbackFacility = null;
    isFacilityDetailOpen = null;
    onDetailVisibilityChanged = null;
    openRoutePlan = null;
    applyRoutePlan = null;
    openMenu = null;
    openWeather = null;
    openEmergency = null;
    hasActiveOverlay = null;
    onExternalSurfaceChanged = null;
    onRoutePlanningDismissed = null;
    handleSystemBack = null;
  }
}
