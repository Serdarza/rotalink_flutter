import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';
import '../utils/geo_helpers.dart';

/// Yalnızca başlığın sunumu; arama veya şehir eşleştirmesine katılmaz.
String searchProvinceLocative(String province) {
  final lower = province.toLowerCase();
  final vowels = RegExp('[aeıioöuü]').allMatches(lower).toList();
  final front = vowels.isNotEmpty && 'eiöü'.contains(vowels.last.group(0)!);
  final hard = lower.isNotEmpty && 'fstkçşhp'.contains(lower[lower.length - 1]);
  return "$province'${hard ? 't' : 'd'}${front ? 'e' : 'a'}";
}

class SearchFilterButton extends StatelessWidget {
  const SearchFilterButton({
    super.key,
    required this.label,
    required this.onTap,
    this.active = false,
    this.icon = Icons.expand_more_rounded,
  });
  final String label;
  final VoidCallback onTap;
  final bool active;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceOf(context),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(
        color: active ? AppColors.primary : AppColors.borderOf(context),
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textStrongOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (active) ...[
                const SizedBox(width: 5),
                const Icon(Icons.circle, size: 6, color: AppColors.primary),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class SearchResultDistanceLine extends StatelessWidget {
  const SearchResultDistanceLine({
    super.key,
    required this.userLocation,
    required this.facilityPoint,
    required this.locationPermissionGranted,
    this.spacingAbove = 5,
  });
  final LatLng? userLocation;
  final LatLng? facilityPoint;
  final bool locationPermissionGranted;
  final double spacingAbove;

  @override
  Widget build(BuildContext context) {
    final distance =
        locationPermissionGranted && facilityPoint != const LatLng(0, 0)
        ? distanceMetersBetween(userLocation, facilityPoint)
        : null;
    if (distance == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: spacingAbove),
      child: Text(
        '${(distance / 1000).toStringAsFixed(1).replaceAll('.', ',')} km · Konumunuzdan · (Kuş Uçuşu)',
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Sadece gerçek cihaz konumu ve geçerli tesis koordinatı varsa mesafe gösterir.
class SearchFacilityResultCard extends StatelessWidget {
  const SearchFacilityResultCard({
    super.key,
    required this.name,
    required this.location,
    required this.hasPrice,
    required this.locationPermissionGranted,
    required this.userLocation,
    required this.facilityPoint,
    required this.onTap,
    this.price,
    this.footer,
    this.distanceKm,
  });
  final String name;
  final String location;
  final bool hasPrice;
  final bool locationPermissionGranted;
  final LatLng? userLocation;
  final LatLng? facilityPoint;
  final VoidCallback onTap;
  final Widget? price;
  final Widget? footer;

  /// Already calculated from the device position (e.g. nearby Haversine list).
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final distance = !locationPermissionGranted
        ? null
        : distanceKm != null
        ? (distanceKm!.isFinite && distanceKm! >= 0 ? distanceKm! * 1000 : null)
        : locationPermissionGranted && facilityPoint != const LatLng(0, 0)
        ? distanceMetersBetween(userLocation, facilityPoint)
        : null;
    final distanceText = distance == null
        ? null
        : '${(distance / 1000).toStringAsFixed(1).replaceAll('.', ',')} km · Konumunuzdan · (Kuş Uçuşu)';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: AppColors.surfaceOf(context),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.borderOf(context)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.hotel_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textStrongOf(context),
                        ),
                      ),
                      if (location.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            location,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textMutedOf(context),
                            ),
                          ),
                        ),
                      if (hasPrice || price != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (hasPrice)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.isDark(context)
                                        ? const Color(0xFF193F2B)
                                        : const Color(0xFFE5F3E6),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    'Fiyat Bilgisi',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.isDark(context)
                                          ? const Color(0xFFA8DFAD)
                                          : const Color(0xFF257332),
                                    ),
                                  ),
                                ),
                              ?price,
                            ],
                          ),
                        ),
                      if (distanceText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            distanceText,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ?footer,
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMutedOf(context),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
