import 'package:flutter/material.dart';

import '../models/gezi_yemek_item.dart';
import '../theme/app_colors.dart';
import 'rotalink_cached_image.dart';

/// Gezi / yemek kartı — en fazla 3 kaydırılabilir görsel.
class GeziYemekMediaCard extends StatefulWidget {
  const GeziYemekMediaCard({
    super.key,
    required this.item,
    required this.kindLabel,
    this.onTap,
    this.trailing,
  });

  final GeziYemekItem item;
  final String kindLabel;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  State<GeziYemekMediaCard> createState() => _GeziYemekMediaCardState();
}

class _GeziYemekMediaCardState extends State<GeziYemekMediaCard> {
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
    final urls = _urls;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: urls.isEmpty
                      ? _PlaceholderCover(label: widget.kindLabel)
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            PageView.builder(
                              controller: _page,
                              itemCount: urls.length,
                              onPageChanged: (i) => setState(() => _index = i),
                              itemBuilder: (_, i) {
                                return RotalinkCachedImage(
                                  url: urls[i],
                                  placeholderIcon:
                                      widget.kindLabel.contains('Yemek')
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
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    widget.kindLabel,
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
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.isim,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        if (g.il.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            g.il,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                        if (g.aciklama.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            g.aciklama,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: AppColors.campaignSummaryMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.trailing != null) widget.trailing!,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.label});

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
