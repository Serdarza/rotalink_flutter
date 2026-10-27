import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/kis_kesfet_osm_piste_repository.dart';
import '../models/kis_kesfet_place.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';
import 'kis_kesfet_osm_pist_map.dart';
import 'kis_kesfet_ui.dart';

bool kisKesfetPistHaritasiUygulamada(KisKesfetPlace place) =>
    place.pistHaritasiUygulamada ||
    KisKesfetOsmPisteRepository.contains(place.id);

/// OSM pist katmanı varsa onu açar; yoksa görsel paneli; o da yoksa resmî bağlantı.
Future<void> showKisKesfetPistHaritasi(
  BuildContext context,
  KisKesfetPlace place,
) async {
  final osm = await KisKesfetOsmPisteRepository.forId(place.id);
  if (osm != null && osm.hasGeometry) {
    if (!context.mounted) return;
    await _showPistSheet(
      context,
      KisKesfetOsmPistMap(
        place: place,
        harita: osm,
        onOfficialTap: place.pistHaritasiBaglanti == null
            ? null
            : () => openKisKesfetLink(context, place.pistHaritasiBaglanti!),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  if (place.pistHaritasiUygulamada) {
    await _showPistSheet(context, _PistHaritasiBody(place: place));
    return;
  }
  final uri = place.pistHaritasiBaglanti;
  if (uri != null) {
    await openKisKesfetLink(context, uri);
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Harita henüz bulunamadı')));
  }
}

Future<void> _showPistSheet(BuildContext context, Widget body) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height * 0.88;
      return Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: AppColors.surfaceOf(ctx),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(height: height, child: body),
        ),
      );
    },
  );
}

Future<void> openKisKesfetLink(BuildContext context, Uri uri) async {
  var ok = false;
  try {
    ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Bağlantı açılamadı')));
  }
}

class _PistHaritasiBody extends StatelessWidget {
  const _PistHaritasiBody({required this.place});

  final KisKesfetPlace place;

  KisKesfetPistHaritasi get harita => place.pistHaritasi!;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textMutedOf(context);
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
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
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
            child: _ZoomableMap(
              url: harita.gorselUri!,
              onBroken: () async {
                final uri = place.pistHaritasiBaglanti;
                if (uri != null && context.mounted) {
                  await openKisKesfetLink(context, uri);
                }
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (harita.kaynakAdi.isNotEmpty)
                Text(
                  harita.resmi
                      ? 'Kaynak: ${harita.kaynakAdi} (resmî)'
                      : 'Kaynak: ${harita.kaynakAdi}',
                  style: TextStyle(
                    color: muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              if (harita.sonKontrol.isNotEmpty)
                Text(
                  'Güncelleme tarihi: ${KisKesfetUi.formatDate(harita.sonKontrol)}',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              if (place.pistHaritasiBaglanti != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        openKisKesfetLink(context, place.pistHaritasiBaglanti!),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Resmî pist haritasını aç'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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

class _ZoomableMap extends StatelessWidget {
  const _ZoomableMap({required this.url, required this.onBroken});

  final Uri url;
  final VoidCallback onBroken;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: AraUi.primaryActionFillOf(context),
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: CachedNetworkImage(
            imageUrl: url.toString(),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            placeholder: (_, _) => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            errorWidget: (_, _, _) {
              WidgetsBinding.instance.addPostFrameCallback((_) => onBroken());
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            },
          ),
        ),
      ),
    );
  }
}
