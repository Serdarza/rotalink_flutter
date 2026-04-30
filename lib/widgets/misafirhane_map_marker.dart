import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/misafirhane.dart';
import '../theme/app_colors.dart';
import '../utils/safe_map_coordinates.dart';

/// Haritada misafirhane pin'i + [PopupMarkerLayer] ile açılan bilgi kutusu için taşıyıcı marker.
///
/// Kotlin [MainActivity.createAndAddMarkers]: OSMDroid [InfoWindow] ile
/// [marker_info_window_small] kullanımının karşılığı.
class MisafirhaneMapMarker extends Marker {
  MisafirhaneMapMarker({
    required this.misafirhane,
    required bool primaryHighlight,
  }) : super(
          key: ValueKey<String>('mh-popup-${misafirhane.stableFacilityId}'),
          width: primaryHighlight ? 50.0 : 40.0,
          height: primaryHighlight ? 50.0 : 40.0,
          point: latLngOrFallback(misafirhane.latitude, misafirhane.longitude),
          child: Tooltip(
            message: '${misafirhane.isim}\n${misafirhane.il}',
            child: Icon(
              Icons.location_on,
              color: primaryHighlight
                  ? const Color(0xFF1976D2)
                  : AppColors.mapLocationPin,
              size: primaryHighlight ? 50.0 : 40.0,
            ),
          ),
        );

  final Misafirhane misafirhane;

  /// [PopupSpec] eşleşmesi ve sheet’ten `showPopupsOnlyFor` ile aynı tesisi
  /// seçebilmek için [stableFacilityId] tabanlı kimlik.
  @override
  bool operator ==(Object other) =>
      other is MisafirhaneMapMarker &&
      other.misafirhane.stableFacilityId == misafirhane.stableFacilityId;

  @override
  int get hashCode => misafirhane.stableFacilityId.hashCode;
}
