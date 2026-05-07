import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/misafirhane.dart';

/// Marker üstünde süzülen minimal şeffaf etiket — yalnızca tesis adı.
class MapFacilityPreviewCard extends StatelessWidget {
  const MapFacilityPreviewCard({
    super.key,
    required this.misafirhane,
  });

  final Misafirhane misafirhane;

  @override
  Widget build(BuildContext context) {
    final name = misafirhane.isim.trim();
    if (name.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.2,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
