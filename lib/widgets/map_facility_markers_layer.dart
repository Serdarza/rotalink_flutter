import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/misafirhane.dart';
import '../providers/facility_filter_provider.dart';
import '../utils/safe_map_coordinates.dart';
import '../widgets/misafirhane_map_marker.dart';

/// Tesis popup marker katmanı — filtre değişince yalnızca bu widget yeniden çizilir.
class MapFacilityPopupMarkersLayer extends ConsumerWidget {
  const MapFacilityPopupMarkersLayer({
    super.key,
    required this.baseFacilities,
    required this.highlight,
    required this.visible,
    required this.popupController,
    required this.onMarkerTap,
  });

  final List<Misafirhane> baseFacilities;
  final Misafirhane? highlight;
  final bool visible;
  final PopupController popupController;
  final void Function(
    PopupSpec popupSpec,
    PopupState popupState,
    PopupController popupController,
  ) onMarkerTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(facilityTypeFilterProvider);
    final display = filterFacilitiesByType(baseFacilities, filter);
    final markers = _buildFacilityMarkers(display, highlight);
    final show = visible && markers.isNotEmpty;

    return AnimatedOpacity(
      opacity: show ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !show,
        child: PopupMarkerLayer(
          options: PopupMarkerLayerOptions(
            markers: markers,
            popupController: popupController,
            markerTapBehavior: MarkerTapBehavior.custom(onMarkerTap),
          ),
        ),
      ),
    );
  }

  static List<Marker> _buildFacilityMarkers(
    List<Misafirhane> list,
    Misafirhane? primaryHighlight,
  ) {
    final hl = primaryHighlight;
    final seen = <String>{};
    return list
        .where(
          (m) =>
              m.latitude != 0 &&
              m.longitude != 0 &&
              isValidWgs84LatLng(m.latitude, m.longitude),
        )
        .where((m) => seen.add(m.stableFacilityId))
        .map(
          (m) => MisafirhaneMapMarker(
            misafirhane: m,
            primaryHighlight: hl != null && m.sameFavoriteIdentity(hl),
          ),
        )
        .toList();
  }
}

/// İl özet marker katmanı — filtre değişince yalnızca bu widget yeniden çizilir.
class MapOverviewCityMarkersLayer extends ConsumerWidget {
  const MapOverviewCityMarkersLayer({
    super.key,
    required this.buildMarkers,
    required this.visible,
  });

  final List<Marker> Function(String typeFilter) buildMarkers;
  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(facilityTypeFilterProvider);
    final markers = buildMarkers(filter);

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !visible,
        child: MarkerLayer(markers: markers),
      ),
    );
  }
}
