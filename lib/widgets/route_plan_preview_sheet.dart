import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/app_strings.dart';
import '../models/route_stop.dart';
import '../theme/app_colors.dart';
import '../utils/geo_helpers.dart';
import '../utils/maps_launch.dart';
import '../utils/route_facility_lookup.dart';

/// Rota planından çıkmadan OSRM özetini gösterir; `true` = haritaya geç.
Future<bool?> showRoutePlanPreviewSheet({
  required BuildContext context,
  required List<RouteStop> stops,
  double? distanceM,
  double? durationS,
  List<LatLng>? navigationWaypoints,
  List<String>? navigationPlaceQueries,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (ctx) {
      final pad = MediaQuery.of(ctx).padding;
      final inset = MediaQuery.of(ctx).viewInsets.bottom;
      final dm = distanceM;
      final ds = durationS;
      final cities = stops.map((s) => s.city).join(' → ');
      final placeQ = navigationPlaceQueries;

      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              clipBehavior: Clip.antiAlias,
              elevation: 12,
              shadowColor: Colors.black38,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.72,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + pad.bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        AppStrings.routePlanPreviewTitle,
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cities,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.campaignSummaryMuted,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      if (dm != null && ds != null && dm > 0 && ds > 0) ...[
                        const SizedBox(height: 20),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF007B8F), Color(0xFF5C6BC0)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.route_rounded,
                                        color: AppColors.white,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            AppStrings.routePlanTotalDistance,
                                            style: TextStyle(
                                              color: AppColors.white.withValues(alpha: 0.88),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            formatRouteDistanceMeters(dm),
                                            style: const TextStyle(
                                              color: AppColors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  AppStrings.routePlanTotalDuration,
                                  style: TextStyle(
                                    color: AppColors.white.withValues(alpha: 0.88),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formatRouteDurationSeconds(ds),
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  AppStrings.routePlanOsrmNote,
                                  style: TextStyle(
                                    color: AppColors.white.withValues(alpha: 0.78),
                                    fontSize: 11,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.suggestionBg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, color: AppColors.primary.withValues(alpha: 0.9)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  AppStrings.routePlanPreviewNoMetrics,
                                  style: TextStyle(
                                    color: AppColors.textPrimary.withValues(alpha: 0.85),
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final mis = misafirhanelerInRouteOrder(stops);
                          if (mis.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text(AppStrings.routePlanStepNavNoMisafirhane)),
                            );
                            return;
                          }
                          await openMisafirhaneStepNavigation(ctx, mis);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.primary, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.navigation_rounded, size: 22),
                        label: const Text(
                          AppStrings.routePlanStartNavigation,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      if (placeQ != null && placeQ.length >= 2) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  openGoogleDirectionsPlaceQueries(ctx, placeQ),
                              icon: const Icon(Icons.navigation_rounded, size: 18),
                              label: const Text(AppStrings.routePlanNavGoogle),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  openYandexDirectionsPlaceQueries(ctx, placeQ),
                              icon: const Icon(Icons.alt_route_rounded, size: 18),
                              label: const Text(AppStrings.routePlanNavYandex),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  openAppleDirectionsPlaceQueries(ctx, placeQ),
                              icon: const Icon(Icons.map_rounded, size: 18),
                              label: const Text(AppStrings.routePlanNavApple),
                            ),
                          ],
                        ),
                      ] else if (navigationWaypoints != null &&
                          navigationWaypoints.length >= 2) ...[
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () =>
                              openGoogleDirectionsWaypoints(ctx, navigationWaypoints),
                          icon: const Icon(Icons.alt_route_rounded, size: 20),
                          label: const Text(
                            AppStrings.routePlanGoogleFullDirections,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ],
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          AppStrings.routePlanShowOnMap,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          AppStrings.routePlanPreviewEdit,
                          style: TextStyle(
                            color: AppColors.campaignSummaryMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
