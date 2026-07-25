import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/facility_address_repository.dart';
import '../data/facility_image_repository.dart';
import '../map_location_state.dart';
import '../models/misafirhane.dart';
import '../theme/app_colors.dart';
import 'distance_permission_chip.dart';
import 'facility_overnight_price_box.dart';
import 'rotalink_cached_image.dart';

/// Tesis listesinden açılan profesyonel detay kartı (Geri ile listeye dönüş).
class FacilityDetailCard extends StatelessWidget {
  const FacilityDetailCard({
    super.key,
    required this.misafirhane,
    required this.mapLocationState,
    required this.isFavorite,
    required this.onBack,
    required this.onCall,
    required this.onShare,
    required this.onFavorite,
    required this.onInspect,
    required this.onReview,
    required this.onShowOnMap,
    required this.onRequestLocation,
  });

  final Misafirhane misafirhane;
  final MapLocationState mapLocationState;
  final bool isFavorite;
  final VoidCallback onBack;
  final VoidCallback onCall;
  final VoidCallback onShare;
  final VoidCallback onFavorite;
  final VoidCallback onInspect;
  final VoidCallback onReview;
  final VoidCallback onShowOnMap;
  final Future<void> Function() onRequestLocation;

  @override
  Widget build(BuildContext context) {
    final m = FacilityImageRepository.instance.resolveFacility(
      FacilityAddressRepository.instance.resolveFacility(misafirhane),
    );
    final tip = m.tip.trim();
    final il = m.il.trim();
    final ilce = m.ilce.trim();
    final adres = m.adres.trim();
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? const Color(0xFF151A1C) : const Color(0xFFF7FAFB);
    final cardBg = isDark ? const Color(0xFF1E2528) : Colors.white;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : AppColors.textPrimary.withValues(alpha: 0.55);
    final titleColor =
        isDark ? Colors.white.withValues(alpha: 0.96) : AppColors.textPrimary;
    final hairline = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppColors.primary.withValues(alpha: 0.08);

    return Material(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: cardBg,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 14, 10),
              child: Row(
                children: [
                  Material(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : AppColors.primary.withValues(alpha: 0.08),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onBack,
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 22,
                          color: isDark ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Listeye dön',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.92)
                                : AppColors.primary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Konaklama detayı',
                          style: TextStyle(
                            color: muted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onBack,
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Kapat',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 1, color: hairline),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              physics: const ClampingScrollPhysics(),
              children: [
                if (m.imageUrls.isNotEmpty) ...[
                  _FacilityImageCarousel(urls: m.imageUrls),
                  const SizedBox(height: 12),
                ],
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: hairline),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.isim.trim().isEmpty ? 'Tesis' : m.isim.trim(),
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (il.isNotEmpty || tip.isNotEmpty || ilce.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (il.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.location_city_outlined,
                                      size: 15,
                                      color: muted,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      ilce.isNotEmpty ? '$ilce / $il' : il,
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              if (tip.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    tip,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (adres.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 16,
                                color: muted,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  adres,
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 13,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        DistancePermissionChip(
                          userLocation: mapLocationState.userLocation,
                          locationPermissionGranted:
                              mapLocationState.locationPermissionGranted,
                          facilityPoint: LatLng(m.latitude, m.longitude),
                          onRequestLocation: onRequestLocation,
                          spacingAbove: 0,
                          fullWidthSingleLine: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FacilityOvernightPriceBox(
                  facility: m,
                ),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: hairline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        _DetailAction(
                          icon: Icons.call_rounded,
                          color: const Color(0xFF2E7D32),
                          label: 'Ara',
                          onTap: onCall,
                        ),
                        _DetailAction(
                          icon: Icons.ios_share_rounded,
                          color: const Color(0xFF039BE5),
                          label: 'Paylaş',
                          onTap: onShare,
                        ),
                        _DetailAction(
                          icon: isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: const Color(0xFFC2185B),
                          label: 'Favori',
                          onTap: onFavorite,
                        ),
                        _DetailAction(
                          icon: Icons.map_outlined,
                          color: AppColors.primary,
                          label: 'İncele',
                          onTap: onInspect,
                        ),
                        _DetailAction(
                          icon: Icons.chat_bubble_outline_rounded,
                          color: const Color(0xFFE65100),
                          label: 'Yorum',
                          onTap: onReview,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: cardBg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: onShowOnMap,
                  icon: const Icon(Icons.my_location_outlined, size: 20),
                  label: const Text(
                    'Haritada göster',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      letterSpacing: 0.1,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FacilityImageCarousel extends StatefulWidget {
  const _FacilityImageCarousel({required this.urls});

  final List<String> urls;

  @override
  State<_FacilityImageCarousel> createState() => _FacilityImageCarouselState();
}

class _FacilityImageCarouselState extends State<_FacilityImageCarousel> {
  late final PageController _page;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _page = PageController();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls.take(3).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _page,
              itemCount: urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                return RotalinkCachedImage(
                  url: urls[i],
                  placeholderIcon: Icons.hotel_rounded,
                );
              },
            ),
            if (urls.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(urls.length, (i) {
                    final on = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: on ? 14 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: on
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Konaklama',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
