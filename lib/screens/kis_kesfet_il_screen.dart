import 'package:flutter/material.dart';
import '../models/kis_kesfet_place.dart';
import '../navigation/rotalink_shell_scope.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';
import '../utils/maps_launch.dart';
import '../widgets/kis_kesfet_detail_sheet.dart';
import '../widgets/kis_kesfet_pist_haritasi_sheet.dart';
import '../widgets/kis_kesfet_ui.dart';
import '../widgets/kis_kesfet_ucret_section.dart';

class KisKesfetIlScreen extends StatelessWidget {
  const KisKesfetIlScreen({
    super.key,
    required this.il,
    required this.kategori,
    required this.places,
  });
  final String il;
  final KisKesfetKategori kategori;
  final List<KisKesfetPlace> places;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AraUi.pageOf(context),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Geri',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          style: IconButton.styleFrom(
                            foregroundColor: AppColors.textStrongOf(context),
                            backgroundColor: AppColors.surfaceOf(context),
                            side: BorderSide(
                              color: AppColors.borderOf(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            kategori.etiket,
                            style: TextStyle(
                              color: AppColors.textStrongOf(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    KisKesfetHero(
                      kategori: kategori,
                      eyebrow: 'BİR SONRAKİ DURAĞIN',
                      title: il,
                      subtitle: KisKesfetUi.ilOzeti(kategori, places),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Keşfedilecek yerler',
                      style: TextStyle(
                        color: AppColors.textStrongOf(context),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Detayları incele, yolculuğunu planla.',
                      style: TextStyle(
                        color: AppColors.textMutedOf(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + RotalinkShellScope.scrollBottomPadding(context),
              ),
              sliver: SliverList.separated(
                itemCount: places.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) =>
                    _PlaceCard(place: places[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place});
  final KisKesfetPlace place;

  @override
  Widget build(BuildContext context) {
    final accent = KisKesfetUi.accentOf(context, place.kategori);
    final description = KisKesfetUi.descriptionFor(place);
    final hasPrices =
        place.kategori == KisKesfetKategori.termal &&
        (place.ucretBilgisi?.gecerliKalemler(DateTime.now()).isNotEmpty ??
            false);
    return Material(
      color: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.borderOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showKisKesfetDetail(context, place),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: KisKesfetUi.headerGradient(place.kategori),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: KisKesfetUi.tintOf(context, place.kategori),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          KisKesfetUi.iconFor(place.kategori),
                          color: accent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              place.isim,
                              style: TextStyle(
                                color: AppColors.textStrongOf(context),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              place.ilIlceSatiri,
                              style: TextStyle(
                                color: AppColors.textMutedOf(context),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (place.tesisRozeti.isNotEmpty)
                        KisKesfetTag(
                          text: place.tesisRozeti,
                          kategori: place.kategori,
                        ),
                      if (hasPrices)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Fiyat Bilgisi',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (place.kullanimTuru.isNotEmpty)
                        KisKesfetTag(
                          text: place.kullanimTuru,
                          kategori: place.kategori,
                          icon: Icons.schedule_rounded,
                        ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMutedOf(context),
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ],
                  if (hasPrices &&
                      place.ucretBilgisi?.baslangicUcreti(DateTime.now()) !=
                          null) ...[
                    const SizedBox(height: 14),
                    KisKesfetUcretSummary(place: place),
                  ],
                  if (place.hasFacts) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final bilgi in place.anaBilgiler.take(4))
                          KisKesfetTag(
                            text: bilgi.deger,
                            kategori: place.kategori,
                            icon: KisKesfetUi.iconForFact(bilgi.baslik),
                          ),
                      ],
                    ),
                  ],
                  if (place.hasPhone) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.call_outlined, size: 15, color: accent),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            place.telefon,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Divider(
                      height: 1,
                      color: AppColors.borderOf(context),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _CardButton(
                          label: 'Detay',
                          icon: Icons.arrow_forward_rounded,
                          place: place,
                          filled: false,
                          onPressed: () => showKisKesfetDetail(context, place),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CardButton(
                          label: 'Haritada göster',
                          icon: Icons.near_me_outlined,
                          place: place,
                          filled: true,
                          onPressed: () =>
                              openMapSearch(context, place.il, place.isim),
                        ),
                      ),
                    ],
                  ),
                  if (place.isKayak) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () =>
                            showKisKesfetPistHaritasi(context, place),
                        icon: Icon(
                          kisKesfetPistHaritasiUygulamada(place)
                              ? Icons.map_outlined
                              : Icons.open_in_new_rounded,
                          size: 18,
                        ),
                        label: const Text('Pist Haritası'),
                        style: TextButton.styleFrom(
                          foregroundColor: accent,
                          minimumSize: const Size.fromHeight(44),
                          backgroundColor: KisKesfetUi.tintOf(
                            context,
                            place.kategori,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                          textStyle: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.icon,
    required this.place,
    required this.filled,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final KisKesfetPlace place;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = KisKesfetUi.accentOf(context, place.kategori);
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        textStyle: Theme.of(context).textTheme.labelLarge,
        backgroundColor: filled
            ? KisKesfetUi.gradientFor(place.kategori).first
            : KisKesfetUi.tintOf(context, place.kategori),
        foregroundColor: filled ? Colors.white : accent,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          Icon(icon, size: 16),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
