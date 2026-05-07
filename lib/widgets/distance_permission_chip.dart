import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';
import '../utils/geo_helpers.dart';

// ignore_for_file: public_member_api_docs

/// Tüm listelerde ortak uzaklık / konum izni satırı. İzin yok veya kullanıcı konumu yoksa
/// [kDistancePermissionNeededLabel] gösterilir; yalnızca [onRequestLocation] ile izin / konum istenir.
class DistancePermissionChip extends StatelessWidget {
  const DistancePermissionChip({
    super.key,
    required this.userLocation,
    required this.locationPermissionGranted,
    required this.facilityPoint,
    required this.onRequestLocation,
    this.spacingAbove = 4,
    this.fullWidthSingleLine = false,
  });

  final LatLng? userLocation;
  final bool locationPermissionGranted;
  /// Tesis / geocode sonrası nokta; null ise yalnızca izin gerekiyorsa [kDistancePermissionNeededLabel].
  final LatLng? facilityPoint;
  final Future<void> Function() onRequestLocation;
  final double spacingAbove;

  /// true: tam genişlik, metin tek satır ([TextOverflow.ellipsis]). Gezi / Yemek / Sosyal satırında ikonların altına uzanır.
  final bool fullWidthSingleLine;

  @override
  Widget build(BuildContext context) {
    final label = resolveDistanceRowTextWithOptionalFacility(
      userLocation: userLocation,
      facility: facilityPoint,
      locationPermissionGranted: locationPermissionGranted,
    );
    if (label == null) return const SizedBox.shrink();

    // Tıklanabilir: izin gerekli (kDistancePermissionNeededLabel) VEYA konum yenilenmesi (kDistanceRetryLabel).
    final isTap = isDistanceTapLabel(label);
    final isRetry = label == kDistanceRetryLabel;

    final chipColor =
        isTap ? AppColors.primary.withValues(alpha: 0.08) : const Color(0xFFE0F7FA);
    final contentColor =
        isTap ? AppColors.primary : AppColors.purple700;
    final iconData = isRetry
        ? Icons.gps_not_fixed
        : isTap
            ? Icons.touch_app_outlined
            : Icons.place;

    final textStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: contentColor,
      decoration: isTap ? TextDecoration.underline : TextDecoration.none,
      decorationColor: contentColor,
    );
    final labelWidget = fullWidthSingleLine
        ? Expanded(
            child: Text(
              label,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          )
        : Flexible(
            child: Text(
              label,
              style: textStyle,
              maxLines: 3,
              softWrap: true,
            ),
          );

    final chip = Container(
      width: fullWidthSingleLine ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(12),
        border: isTap
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(
        mainAxisSize: fullWidthSingleLine ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(iconData, size: 14, color: contentColor),
          const SizedBox(width: 4),
          labelWidget,
        ],
      ),
    );

    final child = isTap
        ? InkWell(
            onTap: () => unawaited(onRequestLocation()),
            borderRadius: BorderRadius.circular(12),
            child: chip,
          )
        : chip;

    if (spacingAbove <= 0) return child;
    return Column(
      crossAxisAlignment:
          fullWidthSingleLine ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: spacingAbove),
        child,
      ],
    );
  }
}
