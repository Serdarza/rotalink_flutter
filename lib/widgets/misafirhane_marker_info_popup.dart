import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/misafirhane.dart';
import '../utils/maps_launch.dart';

/// Kotlin `res/layout/marker_info_window_small.xml` ile hizalı bilgi kutusu:
/// Card (5dp köşe, 8dp elevation, beyaz), başlık (#1976D2), ayırıcı (#E0E0E0),
/// [İncele] (#673AB7) ve [Ara] (#4CAF50) — metin ~10sp.
class MisafirhaneMarkerInfoPopup extends StatelessWidget {
  const MisafirhaneMarkerInfoPopup({
    super.key,
    required this.misafirhane,
    this.onInceleHaritaArama,
  });

  final Misafirhane misafirhane;

  /// İncele: il + tesis adı ile uygulama içi harita araması. Verilmezse yerel harita uygulaması açılır.
  final Future<void> Function(String searchQuery)? onInceleHaritaArama;

  static const double _cardWidth = 250;
  static const Color _titleColor = Color(0xFF1976D2);
  static const Color _dividerColor = Color(0xFFE0E0E0);
  static const Color _inceleColor = Color(0xFF673AB7);
  static const Color _araColor = Color(0xFF4CAF50);

  /// Kotlin arama çubuğu ile uyumlu: önce il, sonra tesis adı.
  static String haritaAramaSorgusu(Misafirhane m) {
    final il = m.il.trim();
    final isim = m.isim.trim();
    if (il.isEmpty && isim.isEmpty) return '';
    if (il.isEmpty) return isim;
    if (isim.isEmpty) return il;
    return '$il $isim';
  }

  Future<void> _onIncele(BuildContext context) async {
    final m = misafirhane;
    await openInNativeMaps(
      context,
      query: m.isim.trim().isEmpty ? m.il.trim() : m.isim.trim(),
      latitude: m.latitude != 0 ? m.latitude : null,
      longitude: m.longitude != 0 ? m.longitude : null,
    );
  }

  Future<void> _onIncelePressed(BuildContext context) async {
    final q = haritaAramaSorgusu(misafirhane);
    if (q.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arama için il veya tesis adı yok.')),
        );
      }
      return;
    }
    final harita = onInceleHaritaArama;
    if (harita != null) {
      await harita(q);
    } else {
      await _onIncele(context);
    }
  }

  Future<void> _onAra(BuildContext context) async {
    final raw = misafirhane.telefon.trim();
    if (raw.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Telefon numarası mevcut değil.')),
        );
      }
      return;
    }
    final uri = Uri(scheme: 'tel', path: raw.replaceAll(RegExp(r'\s'), ''));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Arama başlatılamadı')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = misafirhane.isim.trim().isEmpty
        ? misafirhane.il.trim().isEmpty
            ? 'Tesis'
            : misafirhane.il.trim()
        : misafirhane.isim.trim();

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(5),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: _cardWidth,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _titleColor,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 1,
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                color: _dividerColor,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: FilledButton(
                        onPressed: () => _onIncelePressed(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: _inceleColor,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          textStyle: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text('İncele'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: FilledButton(
                        onPressed: () => _onAra(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: _araColor,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          textStyle: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text('Ara'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
