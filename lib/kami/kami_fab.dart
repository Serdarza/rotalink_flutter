import 'package:flutter/material.dart';

import 'kami_animation.dart';
import 'kami_messages.dart';

/// KAMİ FAB — verilen logo, mevcut 56px yuvarlak boyut.
class KamiFab extends StatelessWidget {
  const KamiFab({
    super.key,
    required this.onPressed,
    this.pulsing = true,
  });

  final VoidCallback onPressed;
  final bool pulsing;

  static const double size = 56;

  @override
  Widget build(BuildContext context) {
    return KamiPulseAnimation(
      enabled: pulsing,
      child: Tooltip(
        message: KamiMessages.fabTooltip,
        child: Material(
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: 0.28),
          shape: const CircleBorder(),
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Ink(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: AssetImage('assets/images/kami_logo.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
