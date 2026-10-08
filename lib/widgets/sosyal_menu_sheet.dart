import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/sosyal_menu_repository.dart';
import '../theme/app_colors.dart';

String formatTl(double v) {
  final whole = v == v.roundToDouble();
  final s = whole ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll('.', ',');
  final parts = s.split(',');
  final digits = parts.first;
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${buf.toString()}${parts.length > 1 ? ',${parts[1]}' : ''} ₺';
}

String formatTrDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String sosyalMenuKaynakSatiri(SosyalMenu m) {
  final kaynak = m.kaynakAdi.isNotEmpty ? m.kaynakAdi : m.kaynak.host;
  final k = m.kontrol;
  final tarih = k == null ? (m.yil != null ? '${m.yil}' : '') : formatTrDate(k);
  return tarih.isEmpty ? 'Kaynak: $kaynak' : 'Kaynak: $kaynak · $tarih';
}

String? sosyalMenuUyari(SosyalMenu m) {
  if (!m.kaynakBulunamadi) return null;
  final d = m.dogrulama ?? m.kontrol;
  return d == null
      ? 'Resmî kaynak şu an bulunamıyor; son doğrulanan fiyatlar gösteriliyor.'
      : 'Resmî kaynak şu an bulunamıyor; ${formatTrDate(d)} tarihinde doğrulanan fiyatlar gösteriliyor.';
}

Future<void> showSosyalMenuSheet(BuildContext context, SosyalMenu menu) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, controller) => _SosyalMenuBody(menu: menu, controller: controller),
    ),
  );
}

class _SosyalMenuBody extends StatelessWidget {
  const _SosyalMenuBody({required this.menu, required this.controller});

  final SosyalMenu menu;
  final ScrollController controller;

  Future<void> _openSource() async {
    if (!SosyalMenu.isOfficialSource(menu.kaynak)) return;
    try {
      await launchUrl(menu.kaynak, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scopeText = menu.tesisMenusu
        ? 'Tesisin menüsü'
        : 'Belediyenin sosyal tesis fiyat tarifesi';
    final scopeNote = menu.tesisMenusu
        ? 'Fiyatlar belediyenin resmî sitesinde bu tesis için yayımlanan belgeden alınmıştır.'
        : 'Bu fiyatlar belediyenin sosyal tesisleri için yayımladığı genel tarifedir; '
            'tesiste farklılık olabilir.';
    final uyari = sosyalMenuUyari(menu);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD5DDE0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '🍽️ YEMEK & MENÜ FİYATLARI',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          menu.isim,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              menu.tesisMenusu ? Icons.restaurant_menu_rounded : Icons.receipt_long_rounded,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                scopeText,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          scopeNote,
          style: const TextStyle(color: Color(0xFF6B7C82), fontSize: 12.5, height: 1.4),
        ),
        if (uyari != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFB26A00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    uyari,
                    style: const TextStyle(color: Color(0xFF8A5300), fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        for (final k in menu.kategoriler) ...[
          const SizedBox(height: 18),
          Text(
            k.ad,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final u in k.urunler)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: u.ad,
                        children: [
                          if (u.birim.isNotEmpty)
                            TextSpan(
                              text: '  ${u.birim}',
                              style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
                            ),
                        ],
                      ),
                      style: const TextStyle(
                        color: Color(0xFF37474F),
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatTl(u.fiyat),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (u.oncekiFiyat != null)
                        Text(
                          formatTl(u.oncekiFiyat!),
                          style: const TextStyle(
                            color: Color(0xFF90A4AE),
                            fontSize: 11.5,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 22),
        const Divider(height: 1),
        const SizedBox(height: 12),
        const Text(
          'Fiyatlar belediyenin resmi internet sitesinden alınmıştır.',
          style: TextStyle(color: Color(0xFF37474F), fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        if (menu.kontrol != null) ...[
          const SizedBox(height: 4),
          Text(
            'Son kontrol: ${formatTrDate(menu.kontrol!)}',
            style: const TextStyle(color: Color(0xFF6B7C82), fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          sosyalMenuKaynakSatiri(menu),
          style: const TextStyle(color: Color(0xFF6B7C82), fontSize: 12.5),
        ),
        if (menu.belge.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            menu.belge,
            style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => unawaited(_openSource()),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Resmi kaynağı görüntüle'),
          ),
        ),
        const Text(
          'Fiyatlar her ay belediyenin kendi sitesinden otomatik kontrol edilir. '
          'Güncel fiyat için tesisle teyit ediniz.',
          style: TextStyle(color: Color(0xFF90A4AE), fontSize: 11.5, height: 1.4),
        ),
      ],
    );
  }
}
