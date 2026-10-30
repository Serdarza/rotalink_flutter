import 'package:flutter/material.dart';

import '../services/facility_route.dart';

const _teal = Color(0xFF008C95);
const _ink = Color(0xFF172A32);
const _soft = Color(0xFFE4F4F5);

/// Seçilen tesisin harita kartı. Süre ve mesafe yalnızca ulaşım kartlarında durur.
class FacilityRoutePanel extends StatelessWidget {
  const FacilityRoutePanel({
    super.key,
    required this.name,
    required this.detail,
    required this.birdKm,
    required this.mode,
    required this.drive,
    required this.walk,
    required this.driveBusy,
    required this.walkBusy,
    required this.note,
    required this.onMode,
    required this.onOpenMaps,
    required this.onClose,
    required this.onAbout,
    required this.onPhotos,
    required this.isFavorite,
    required this.onFavorite,
    required this.onShare,
    this.onCall,
  });

  final String name;
  final String detail;
  final double birdKm;
  final String mode;
  final FacilityRoute? drive;
  final FacilityRoute? walk;
  final bool driveBusy;
  final bool walkBusy;
  final String? note;
  final ValueChanged<String> onMode;
  final VoidCallback onOpenMaps;
  final VoidCallback onClose;
  final VoidCallback onAbout;
  final VoidCallback onPhotos;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onShare;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final walking = FacilityRouteFormat.walkingOffered(birdKm);
    final tone = _Tone.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              tooltip: 'Geri',
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.arrow_back_rounded, color: tone.ink),
            ),
            Expanded(
              child: Text(
                name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tone.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  height: 1.2,
                ),
              ),
            ),
            IconButton(
              tooltip: isFavorite ? 'Favorilerden çıkar' : 'Favorilere ekle',
              onPressed: onFavorite,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isFavorite ? Icons.favorite_rounded : Icons.favorite_border,
                color: isFavorite ? const Color(0xFFE53935) : tone.ink,
              ),
            ),
            IconButton(
              tooltip: 'Paylaş',
              onPressed: onShare,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.share_outlined, color: tone.ink),
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.location_on_outlined, size: 16, color: _teal),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tone.muted, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ModeChoice(
                icon: Icons.directions_car_filled_rounded,
                label: 'Araç',
                selected: mode == 'drive',
                busy: driveBusy,
                time: drive == null
                    ? null
                    : FacilityRouteFormat.duration(drive!.durationSeconds),
                distance: drive == null
                    ? null
                    : FacilityRouteFormat.distance(drive!.distanceMeters),
                onTap: () => onMode('drive'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ModeChoice(
                icon: Icons.directions_walk_rounded,
                label: 'Yürüyüş',
                selected: mode == 'walk',
                busy: walkBusy,
                enabled: walking,
                time: !walking
                    ? '5 km+'
                    : walk == null
                    ? null
                    : FacilityRouteFormat.duration(walk!.durationSeconds),
                distance: walk == null
                    ? null
                    : FacilityRouteFormat.distance(walk!.distanceMeters),
                onTap: walking ? () => onMode('walk') : null,
              ),
            ),
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note!, style: TextStyle(color: tone.muted, height: 1.3)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionChip(
                icon: Icons.info_outline_rounded,
                label: 'Tesis Detayları',
                onTap: onAbout,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionChip(
                icon: Icons.photo_outlined,
                label: 'Fotoğraflar',
                onTap: onPhotos,
              ),
            ),
            if (onCall != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _ActionChip(
                  icon: Icons.call_outlined,
                  label: 'Ara',
                  onTap: onCall!,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onOpenMaps,
          style: FilledButton.styleFrom(
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          icon: const Icon(Icons.navigation_rounded),
          label: const Text('Yol Tarifini Başlat'),
        ),
      ],
    );
  }
}

class _ModeChoice extends StatelessWidget {
  const _ModeChoice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.busy,
    required this.time,
    required this.distance,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool busy;
  final bool enabled;
  final String? time;
  final String? distance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = _Tone.of(context);
    return Material(
      color: selected ? tone.soft : tone.chip,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? _teal : const Color(0xFFE3EBED),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: selected ? _teal : tone.muted),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? _teal : tone.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  if (selected)
                    const Icon(Icons.check_circle, size: 16, color: _teal),
                ],
              ),
              const SizedBox(height: 6),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _teal,
                  ),
                )
              else
                Text(
                  time ?? '—',
                  style: TextStyle(
                    color: enabled ? tone.ink : tone.muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              Text(
                distance ?? '',
                style: TextStyle(color: tone.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tone {
  const _Tone({
    required this.ink,
    required this.muted,
    required this.fill,
    required this.soft,
    required this.chip,
  });

  final Color ink;
  final Color muted;
  final Color fill;
  final Color soft;
  final Color chip;

  static _Tone of(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return const _Tone(
        ink: Colors.white,
        muted: Color(0xFFB7C9CC),
        fill: Color(0xFF16383E),
        soft: Color(0xFF1A4C54),
        chip: Color(0xFF16383E),
      );
    }
    return const _Tone(
      ink: _ink,
      muted: Color(0xFF5C7278),
      fill: Colors.white,
      soft: _soft,
      chip: Color(0xFFF7F9FA),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = _Tone.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: tone.ink,
        backgroundColor: tone.fill,
        minimumSize: const Size.fromHeight(46),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        side: const BorderSide(color: _teal),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: _teal),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
