import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Büyük, dikkat çekici soft destek bandı (modal değil; kapatılabilir).
class ProSupportBanner extends StatelessWidget {
  const ProSupportBanner({
    super.key,
    required this.onOpenPro,
    required this.onDismiss,
  });

  final VoidCallback onOpenPro;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Hafif karartma — soft; dokununca da kapanır.
          Positioned.fill(
            child: GestureDetector(
              onTap: onDismiss,
              behavior: HitTestBehavior.opaque,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.38),
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 72 + bottomPad,
            child: _BannerCard(
              onOpenPro: onOpenPro,
              onDismiss: onDismiss,
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.onOpenPro,
    required this.onDismiss,
  });

  final VoidCallback onOpenPro;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Rotalink Pro destek',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.drawerHeaderGradientStart,
              AppColors.primary,
              Color(0xFF0097A7),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rotalink’i destekleyin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Reklam göstermiyoruz. Uygulamanın giderleri için '
                          'Rotalink Pro ile destek olabilirsiniz.',
                          style: TextStyle(
                            color: Color(0xFFE0F7FA),
                            fontSize: 15.5,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onDismiss,
                    tooltip: 'Kapat',
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onOpenPro,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('Rotalink Pro’ya bak'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.92),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Şimdilik değil'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
