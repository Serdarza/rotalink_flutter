import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../map_location_state.dart';
import '../models/gezi_yemek_item.dart';
import '../theme/app_colors.dart';
import 'distance_permission_chip.dart';
import 'rotalink_cached_image.dart';

/// Gezi / yemek listesinden açılan detay (görseller + açıklama).
class GeziYemekDetailCard extends StatefulWidget {
  const GeziYemekDetailCard({
    super.key,
    required this.item,
    required this.isGezi,
    required this.mapLocationState,
    required this.facilityPoint,
    required this.onBack,
    required this.onInspect,
    required this.onShare,
    required this.onReview,
    required this.onPrimaryCta,
    required this.onRequestLocation,
    this.onSecondaryCta,
    this.secondaryCtaLabel,
    this.secondaryCtaIcon,
  });

  final GeziYemekItem item;
  final bool isGezi;
  final MapLocationState mapLocationState;
  final LatLng? facilityPoint;
  final VoidCallback onBack;
  final VoidCallback onInspect;
  final VoidCallback onShare;
  final VoidCallback onReview;
  final VoidCallback onPrimaryCta;
  final Future<void> Function() onRequestLocation;
  final VoidCallback? onSecondaryCta;
  final String? secondaryCtaLabel;
  final IconData? secondaryCtaIcon;

  @override
  State<GeziYemekDetailCard> createState() => _GeziYemekDetailCardState();
}

class _GeziYemekDetailCardState extends State<GeziYemekDetailCard> {
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

  List<String> get _urls => widget.item.imageUrls.take(3).toList();

  @override
  Widget build(BuildContext context) {
    final g = widget.item;
    final kindLabel = widget.isGezi ? 'Gezi' : 'Yemek';
    final listTitle = widget.isGezi ? 'Gezi listesi' : 'Yemek listesi';
    final urls = _urls;
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
              padding: const EdgeInsets.fromLTRB(2, 2, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    tooltip: 'Geri',
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: isDark ? Colors.white : AppColors.primary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      listTitle,
                      style: TextStyle(
                        color: muted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: urls.isEmpty
                        ? _DetailPlaceholder(label: kindLabel)
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              PageView.builder(
                                controller: _page,
                                itemCount: urls.length,
                                onPageChanged: (i) =>
                                    setState(() => _index = i),
                                itemBuilder: (_, i) {
                                  return RotalinkCachedImage(
                                    url: urls[i],
                                    placeholderIcon: kindLabel.contains('Yemek')
                                        ? Icons.restaurant_rounded
                                        : Icons.landscape_rounded,
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
                                        duration:
                                            const Duration(milliseconds: 180),
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                        ),
                                        width: on ? 14 : 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: on
                                              ? Colors.white
                                              : Colors.white
                                                  .withValues(alpha: 0.45),
                                          borderRadius:
                                              BorderRadius.circular(99),
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
                                    color:
                                        Colors.black.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      kindLabel,
                                      style: const TextStyle(
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
                ),
                const SizedBox(height: 12),
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
                          g.isim.trim().isEmpty ? kindLabel : g.isim.trim(),
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (g.il.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.location_city_outlined,
                                size: 15,
                                color: muted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                g.il.trim(),
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (widget.isGezi) ...[
                          DistancePermissionChip(
                            userLocation: widget.mapLocationState.userLocation,
                            locationPermissionGranted: widget
                                .mapLocationState.locationPermissionGranted,
                            facilityPoint: widget.facilityPoint,
                            onRequestLocation: widget.onRequestLocation,
                            spacingAbove: 0,
                            fullWidthSingleLine: true,
                          ),
                          if (g.aciklama.trim().isNotEmpty)
                            const SizedBox(height: 14),
                        ],
                        if (g.aciklama.trim().isNotEmpty) ...[
                          Text(
                            g.aciklama.trim(),
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.78)
                                  : AppColors.campaignSummaryMuted,
                              fontSize: 13.5,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
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
                          icon: widget.isGezi
                              ? Icons.map_outlined
                              : Icons.image_search,
                          color: AppColors.primary,
                          label: 'İncele',
                          onTap: widget.onInspect,
                        ),
                        if (widget.onSecondaryCta != null)
                          _DetailAction(
                            icon: widget.secondaryCtaIcon ??
                                Icons.map_rounded,
                            color: const Color(0xFF2E7D32),
                            label: widget.secondaryCtaLabel ?? 'Git',
                            onTap: widget.onSecondaryCta!,
                          ),
                        _DetailAction(
                          icon: Icons.ios_share_rounded,
                          color: const Color(0xFF039BE5),
                          label: 'Paylaş',
                          onTap: widget.onShare,
                        ),
                        _DetailAction(
                          icon: Icons.chat_bubble_outline_rounded,
                          color: const Color(0xFFE65100),
                          label: 'Yorum',
                          onTap: widget.onReview,
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
                  onPressed: widget.onPrimaryCta,
                  icon: Icon(
                    widget.isGezi
                        ? Icons.my_location_outlined
                        : Icons.image_search,
                    size: 20,
                  ),
                  label: Text(
                    widget.isGezi ? 'Haritada göster' : 'Görselleri aç',
                    style: const TextStyle(
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

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.85),
            AppColors.primary.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              label.contains('Yemek')
                  ? Icons.restaurant_rounded
                  : Icons.landscape_rounded,
              color: Colors.white.withValues(alpha: 0.9),
              size: 36,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
