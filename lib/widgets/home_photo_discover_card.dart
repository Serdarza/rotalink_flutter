import 'package:flutter/material.dart';

/// Ana sayfanın keşif girişleri için çevrimdışı fotoğraflı kart.
class HomePhotoDiscoverCard extends StatelessWidget {
  const HomePhotoDiscoverCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.imageAsset,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final String imageAsset;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 330 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        final shade = Color.lerp(accent, const Color(0xFF071B2A), 0.65)!;
        return Material(
          color: shade,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  imageAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  cacheWidth: 1024,
                  excludeFromSemantics: true,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: const [0, 0.45, 0.78, 1],
                      colors: [
                        shade.withValues(alpha: 0.96),
                        shade.withValues(alpha: 0.85),
                        shade.withValues(alpha: 0.4),
                        shade.withValues(alpha: 0.08),
                      ],
                    ),
                  ),
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 160),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    height: 1.15,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  subtitle,
                                  style: const TextStyle(
                                    color: Color(0xFFF0F7FA),
                                    fontSize: 12,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (compact) ...[
                                        Icon(
                                          icon,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 7),
                                      ],
                                      Flexible(
                                        child: Text(
                                          actionLabel,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(width: 26),
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Icon(icon, color: Colors.white, size: 25),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
