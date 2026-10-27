import 'package:flutter/material.dart';

import 'home_photo_discover_card.dart';

/// Ana ekrandaki fotoğraflı Kış Keşfet girişi.
class WinterDiscoverHomeCard extends StatelessWidget {
  const WinterDiscoverHomeCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HomePhotoDiscoverCard(
      title: 'Kış Keşfet',
      subtitle: 'Kayak merkezlerini ve termal tesisleri keşfet',
      actionLabel: 'Keşfet',
      imageAsset: 'assets/images/home_discover/winter.webp',
      icon: Icons.ac_unit_rounded,
      accent: const Color(0xFF1B5B91),
      onTap: onTap,
    );
  }
}
