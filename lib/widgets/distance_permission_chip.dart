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

  /// true: metin tek satır ([TextOverflow.ellipsis]). Chip genişliği metne göre kalır.
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
    final labelWidget = Text(
      label,
      style: textStyle,
      maxLines: fullWidthSingleLine ? 1 : 3,
      overflow: fullWidthSingleLine ? TextOverflow.ellipsis : TextOverflow.clip,
      softWrap: !fullWidthSingleLine,
    );

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(12),
        border: isTap
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 14, color: contentColor),
          const SizedBox(width: 4),
          labelWidget,
        ],
      ),
    );

    // Üst Column stretch etse bile chip sadece metin kadar geniş kalsın.
    Widget child = Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: chip,
    );
    if (isTap) {
      child = Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: InkWell(
          onTap: () => unawaited(onRequestLocation()),
          borderRadius: BorderRadius.circular(12),
          child: chip,
        ),
      );
    }

    if (spacingAbove <= 0) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: spacingAbove),
        child,
      ],
    );
  }
}
