import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/kis_kesfet_osm_pist.dart';
import '../models/kis_kesfet_place.dart';
import '../theme/app_colors.dart';
import 'rotalink_tile_layer.dart';

class KisKesfetOsmPistMap extends StatelessWidget {
  const KisKesfetOsmPistMap({
    super.key,
    required this.place,
    required this.harita,
    this.onOfficialTap,
  });

  final KisKesfetPlace place;
  final KisKesfetOsmHarita harita;
  final VoidCallback? onOfficialTap;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textMutedOf(context);
    final bounds = harita.cameraBounds;
    final fit = bounds == null
        ? null
        : CameraFit.bounds(
            bounds: LatLngBounds(
              LatLng(bounds.south, bounds.west),
              LatLng(bounds.north, bounds.east),
            ),
            padding: const EdgeInsets.all(28),
            maxZoom: 15,
          );
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.borderOf(context),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pist Haritası',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    Text(
                      place.isim,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textStrongOf(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: harita.center,
                      initialZoom: 13,
                      initialCameraFit: fit,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom |
                            InteractiveFlag.drag |
                            InteractiveFlag.doubleTapZoom |
                            InteractiveFlag.scrollWheelZoom,
                      ),
                    ),
                    children: [
                      const RotalinkTileLayer(),
                      PolylineLayer(
                        polylines: [
                          for (final pist in harita.pistler)
                            if (pist.hasLine)
                              Polyline(
                                points: pist.noktalar,
                                strokeWidth: 3.6,
                                color: _pisteColor(pist.zorluk),
                              ),
                        ],
                      ),
                      PolylineLayer(
                        polylines: [
                          for (final lift in harita.liftler)
                            if (lift.hasLine && !lift.isLongHaul)
                              Polyline(
                                points: lift.noktalar,
                                strokeWidth: 2.2,
                                color: const Color(0xFF455A64),
                              ),
                        ],
                      ),
                    ],
                  ),
                  const Positioned(
                    right: 6,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xCCFFFFFF),
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Text(
                          '© OpenStreetMap · ODbL',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF455A64),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: const [
                  _LegendDot(color: Color(0xFF2E7D32), label: 'Novis'),
                  _LegendDot(color: Color(0xFF1565C0), label: 'Kolay'),
                  _LegendDot(color: Color(0xFFC62828), label: 'Orta'),
                  _LegendDot(color: Color(0xFF212121), label: 'Zor'),
                  _LegendDot(color: Color(0xFF455A64), label: 'Lift'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Pistler OpenStreetMap kış sporları verisinden. Telifli işletme haritası değildir.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.3),
              ),
              if (onOfficialTap != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onOfficialTap,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(
                      place.pistHaritasiUygulamada
                          ? 'Resmî pist görselini aç'
                          : 'Resmî sayfayı aç',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textMutedOf(context),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

Color _pisteColor(String zorluk) {
  switch (zorluk) {
    case 'novice':
      return const Color(0xFF2E7D32);
    case 'easy':
      return const Color(0xFF1565C0);
    case 'intermediate':
      return const Color(0xFFC62828);
    case 'advanced':
    case 'expert':
    case 'freeride':
      return const Color(0xFF212121);
    default:
      return const Color(0xFF6D4C41);
  }
}
