import 'package:flutter/material.dart';

import '../models/kis_kesfet_place.dart';
import '../models/kis_kesfet_ucret.dart';
import '../theme/app_colors.dart';
import 'kis_kesfet_ui.dart';

class KisKesfetUcretSummary extends StatelessWidget {
  const KisKesfetUcretSummary({super.key, required this.place});
  final KisKesfetPlace place;

  @override
  Widget build(BuildContext context) {
    final ucret = place.ucretBilgisi?.baslangicUcreti(DateTime.now());
    if (ucret == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KisKesfetUi.tintOf(context, place.kategori),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Başlangıç · ${ucret.tur.etiket}',
            style: TextStyle(
              color: AppColors.textStrongOf(context),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${ucret.fiyat} / ${ucret.birim}',
            style: TextStyle(
              color: KisKesfetUi.accentOf(context, place.kategori),
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [ucret.ad, if (ucret.kosul.isNotEmpty) ucret.kosul].join(' · '),
            style: TextStyle(
              color: AppColors.textMutedOf(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class KisKesfetUcretSection extends StatelessWidget {
  const KisKesfetUcretSection({super.key, required this.place});
  final KisKesfetPlace place;

  @override
  Widget build(BuildContext context) {
    final bilgi = place.ucretBilgisi;
    final kalemler = bilgi?.gecerliKalemler(DateTime.now()) ?? const [];
    if (kalemler.isEmpty) return const SizedBox.shrink();
    final accent = KisKesfetUi.accentOf(context, place.kategori);
    final muted = AppColors.textMutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ücretler',
          style: TextStyle(
            color: AppColors.textStrongOf(context),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        for (final tur in KisKesfetUcretTuru.values.where(
          (tur) => kalemler.any((k) => k.tur == tur),
        )) ...[
          Text(
            tur.etiket,
            style: TextStyle(color: accent, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final kalem in kalemler.where((k) => k.tur == tur))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.borderOf(context)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kalem.ad,
                    style: TextStyle(
                      color: AppColors.textStrongOf(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${kalem.fiyat} / ${kalem.birim}',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (kalem.kosul.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      kalem.kosul,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                  if (kalem.gecerlilikBitis.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Geçerlilik sonu: ${KisKesfetUi.formatDate(kalem.gecerlilikBitis)}',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
        ],
        if (bilgi != null) ...[
          if (bilgi.aciklama.isNotEmpty)
            Text(
              bilgi.aciklama,
              style: TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
          const SizedBox(height: 8),
          Text(
            'Ücret son kontrol: ${KisKesfetUi.formatDate(bilgi.sonKontrol)}',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
