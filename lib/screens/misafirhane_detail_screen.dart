import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/misafirhane.dart';
import '../theme/app_colors.dart';
import '../utils/maps_launch.dart';

/// Misafirhane detay — Kotlin [GuesthouseDetailActivity] basit karşılığı.
class MisafirhaneDetailScreen extends StatelessWidget {
  const MisafirhaneDetailScreen({super.key, required this.misafirhane});

  final Misafirhane misafirhane;

  Future<void> _call(BuildContext context) async {
    final p = misafirhane.telefon.trim().replaceAll(RegExp(r'\s'), '');
    if (p.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefon numarası yok')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: p);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arama başlatılamadı')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = misafirhane;
    return Scaffold(
      appBar: AppBar(
        title: Text(m.isim, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Text(
            m.il,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primary),
          ),
          if (m.tip.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(m.tip, style: const TextStyle(color: AppColors.campaignSummaryMuted)),
          ],
          const SizedBox(height: 16),
          if (m.adres.isNotEmpty) Text(m.adres, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _call(context),
            icon: const Icon(Icons.call),
            label: const Text('Ara'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => unawaited(
              openInNativeMaps(
                context,
                query: '${m.isim} ${m.il}',
                latitude: m.latitude,
                longitude: m.longitude,
              ),
            ),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Haritada aç'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}
