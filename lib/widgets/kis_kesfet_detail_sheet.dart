import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/store_links.dart';
import '../models/kis_kesfet_place.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';
import '../utils/maps_launch.dart';
import 'kis_kesfet_pist_haritasi_sheet.dart';
import 'kis_kesfet_ui.dart';
import 'kis_kesfet_ucret_section.dart';

Future<void> showKisKesfetDetail(BuildContext context, KisKesfetPlace place) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height * 0.90;
      return Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: AppColors.surfaceOf(ctx),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: height,
            child: _KisKesfetDetailBody(place: place),
          ),
        ),
      );
    },
  );
}

class _KisKesfetDetailBody extends StatelessWidget {
  const _KisKesfetDetailBody({required this.place});
  final KisKesfetPlace place;

  @override
  Widget build(BuildContext context) {
    final accent = KisKesfetUi.accentOf(context, place.kategori);
    final description = KisKesfetUi.descriptionFor(place);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
          child: Row(
            children: [
              const SizedBox(width: 36),
              Expanded(
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderOf(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Kapat',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: AppColors.textMutedOf(context),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            children: [
              KisKesfetHero(
                kategori: place.kategori,
                eyebrow: place.kategori.etiket,
                title: place.isim,
                subtitle: place.ilIlceSatiri,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (place.tesisRozeti.isNotEmpty)
                    KisKesfetTag(
                      text: place.tesisRozeti,
                      kategori: place.kategori,
                      icon: Icons.account_balance_outlined,
                    ),
                  if (place.kullanimTuru.isNotEmpty)
                    KisKesfetTag(
                      text: place.kullanimTuru,
                      kategori: place.kategori,
                      icon: Icons.schedule_outlined,
                    ),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  description,
                  style: TextStyle(
                    color: AppColors.textStrongOf(context),
                    fontSize: 14,
                    height: 1.7,
                  ),
                ),
              ],
              if (place.hasFacts) ...[
                const SizedBox(height: 22),
                const _SectionLabel('Öne çıkan bilgiler'),
                const SizedBox(height: 12),
                for (final bilgi in place.anaBilgiler)
                  _Fact(
                    icon: KisKesfetUi.iconForFact(bilgi.baslik),
                    label: bilgi.baslik,
                    value: bilgi.deger,
                    kategori: place.kategori,
                  ),
              ],
              if (place.kategori == KisKesfetKategori.termal &&
                  (place.ucretBilgisi
                          ?.gecerliKalemler(DateTime.now())
                          .isNotEmpty ??
                      false)) ...[
                const SizedBox(height: 22),
                KisKesfetUcretSection(place: place),
              ],
              const SizedBox(height: 18),
              const _SectionLabel('Ziyaret bilgileri'),
              const SizedBox(height: 12),
              if (place.adres.isNotEmpty)
                _Fact(
                  icon: Icons.place_outlined,
                  label: 'Adres',
                  value: place.adres,
                  kategori: place.kategori,
                ),
              if (place.hasPhone)
                _Fact(
                  icon: Icons.call_outlined,
                  label: 'Telefon',
                  value: place.telefon,
                  valueColor: accent,
                  kategori: place.kategori,
                ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KisKesfetUi.tintOf(context, place.kategori),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: accent, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Güncel bilgiler için resmî kaynağı kontrol edin.',
                        style: TextStyle(
                          color: AppColors.textStrongOf(context),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (place.hasOfficialSource)
                    TextButton.icon(
                      onPressed: () => _openSource(context, place.resmiKaynak),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Resmî kaynak'),
                      style: TextButton.styleFrom(foregroundColor: accent),
                    ),
                  TextButton.icon(
                    onPressed: () => Share.share(
                      StoreLinks.shareMessage(place.isim, [
                        place.ilIlceSatiri,
                        if (place.hasPhone) place.telefon,
                        place.kisaAciklama,
                      ]),
                    ),
                    icon: const Icon(Icons.ios_share_rounded, size: 16),
                    label: const Text('Paylaş'),
                    style: TextButton.styleFrom(foregroundColor: accent),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            border: Border(top: BorderSide(color: AppColors.borderOf(context))),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            children: [
              if (place.isKayak) ...[
                _ActionButton(
                  icon: kisKesfetPistHaritasiUygulamada(place)
                      ? Icons.map_outlined
                      : Icons.open_in_new_rounded,
                  label: 'Pist Haritası',
                  background: KisKesfetUi.tintOf(context, place.kategori),
                  foreground: accent,
                  onPressed: () => showKisKesfetPistHaritasi(context, place),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.near_me_outlined,
                      label: 'Haritada göster',
                      background: KisKesfetUi.gradientFor(place.kategori).first,
                      foreground: Colors.white,
                      onPressed: () =>
                          openMapSearch(context, place.il, place.isim),
                    ),
                  ),
                  if (place.hasPhone) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.call_rounded,
                        label: 'Ara',
                        background: KisKesfetUi.callGreen,
                        foreground: Colors.white,
                        onPressed: () => _dial(context, place.telefon),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: AppColors.textStrongOf(context),
      fontSize: 16,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    required this.kategori,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final KisKesfetKategori kategori;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AraUi.pageOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: KisKesfetUi.tintOf(context, kategori),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: KisKesfetUi.accentOf(context, kategori),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textMutedOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? AppColors.textStrongOf(context),
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          textStyle: Theme.of(context).textTheme.labelLarge,
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 7,
          runSpacing: 4,
          children: [
            Icon(icon, size: 18),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _dial(BuildContext context, String phone) async {
  final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s'), ''));
  final ok = await launchUrl(uri);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Arama başlatılamadı')));
  }
}

Future<void> _openSource(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Kaynak açılamadı')));
  }
}
