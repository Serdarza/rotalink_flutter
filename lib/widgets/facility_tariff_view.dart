import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/facility_tariff.dart';
import '../theme/app_colors.dart';

/// 1850 → "1.850 TL", 450.5 → "450,50 TL".
String formatTl(double v) {
  final whole = v.truncate();
  final digits = whole.abs().toString();
  final buf = StringBuffer(whole < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  final cents = ((v - whole).abs() * 100).round();
  if (cents > 0) buf.write(',${cents.toString().padLeft(2, '0')}');
  return '$buf TL';
}

String formatTlRange(double min, double max) =>
    min == max ? formatTl(min) : '${formatTl(min).replaceAll(' TL', '')} – ${formatTl(max)}';

class _TariffPalette {
  _TariffPalette(BuildContext context)
      : isDark = Theme.of(context).brightness == Brightness.dark;

  final bool isDark;

  Color get title =>
      isDark ? Colors.white.withValues(alpha: 0.92) : AppColors.textPrimary;
  Color get label => isDark
      ? Colors.white.withValues(alpha: 0.62)
      : AppColors.textPrimary.withValues(alpha: 0.58);
  Color get value =>
      isDark ? Colors.white.withValues(alpha: 0.95) : AppColors.textPrimary;
  Color get cardBg =>
      isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white;
  Color get hairline => isDark
      ? Colors.white.withValues(alpha: 0.10)
      : AppColors.primary.withValues(alpha: 0.12);
  Color get headerBg => isDark
      ? Colors.white.withValues(alpha: 0.07)
      : AppColors.primary.withValues(alpha: 0.07);
}

/// Detaylı tarife: tablolar + kurallar + dahil olanlar + indirim/ek ücret + notlar.
///
/// Yalnızca veride bulunan bölümler çizilir.
class FacilityTariffView extends StatelessWidget {
  const FacilityTariffView({super.key, required this.tariff});

  final FacilityTariff tariff;

  @override
  Widget build(BuildContext context) {
    final p = _TariffPalette(context);
    final hours = [
      if (tariff.girisSaati != null) 'Giriş ${tariff.girisSaati}',
      if (tariff.cikisSaati != null) 'Çıkış ${tariff.cikisSaati}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final table in tariff.tablolar) ...[
          _TableBlock(table: table, palette: p),
          const SizedBox(height: 12),
        ],
        _InfoSection(
          icon: Icons.rule_rounded,
          title: 'Önemli kurallar',
          items: tariff.kurallar,
          palette: p,
        ),
        if (hours.isNotEmpty)
          _InfoSection(
            icon: Icons.schedule_rounded,
            title: 'Giriş / çıkış',
            items: [hours],
            palette: p,
          ),
        _InfoSection(
          icon: Icons.check_circle_outline_rounded,
          title: 'Fiyata dahil',
          items: tariff.dahil,
          palette: p,
        ),
        _InfoSection(
          icon: Icons.percent_rounded,
          title: 'İndirimler',
          items: tariff.indirimler,
          palette: p,
        ),
        _InfoSection(
          icon: Icons.add_circle_outline_rounded,
          title: 'Ek ücretler',
          items: tariff.ekUcretler,
          palette: p,
        ),
        _InfoSection(
          icon: Icons.sticky_note_2_outlined,
          title: 'Tarife notları',
          items: tariff.notlar,
          palette: p,
        ),
      ],
    );
  }
}

class _TableBlock extends StatelessWidget {
  const _TableBlock({required this.table, required this.palette});

  final TariffTable table;
  final _TariffPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final meta = [
      if (table.donem != null) table.donem!,
      if (table.birim != null) 'Fiyatlar ${table.birim}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (table.baslik != null)
          Text(
            table.baslik!,
            style: TextStyle(
              color: p.title,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              meta,
              style: TextStyle(color: p.label, fontSize: 11.5, height: 1.3),
            ),
          ),
        if (table.aciklama != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              table.aciklama!,
              style: TextStyle(color: p.label, fontSize: 11.5, height: 1.35),
            ),
          ),
        if (table.baslik != null || meta.isNotEmpty || table.aciklama != null)
          const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final n = table.kategoriler.length;
            final fitsTable = n > 0 && constraints.maxWidth >= 170 + 96.0 * n;
            return fitsTable
                ? _CompareTable(table: table, palette: p)
                : _RowCards(table: table, palette: p);
          },
        ),
      ],
    );
  }
}

/// Geniş ekran: satır = konaklama tipi, kolon = fiyat kategorisi.
class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.table, required this.palette});

  final TariffTable table;
  final _TariffPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final headerStyle = TextStyle(
      color: p.title,
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.cardBg,
          border: Border.all(color: p.hairline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Table(
          columnWidths: {
            0: const FlexColumnWidth(1.7),
            for (var i = 1; i <= table.kategoriler.length; i++)
              i: const FlexColumnWidth(1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(
            horizontalInside: BorderSide(color: p.hairline),
          ),
          children: [
            TableRow(
              decoration: BoxDecoration(color: p.headerBg),
              children: [
                _cell(Text('Konaklama türü', style: headerStyle)),
                for (final c in table.kategoriler)
                  _cell(
                    Text(c.ad, style: headerStyle, textAlign: TextAlign.end),
                  ),
              ],
            ),
            for (final row in table.satirlar)
              TableRow(
                children: [
                  _cell(_RowTitle(row: row, palette: p)),
                  for (final c in table.kategoriler)
                    _cell(
                      _PriceText(
                        price: row.fiyatlar[c.id],
                        palette: p,
                        align: TextAlign.end,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static Widget _cell(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: child,
      );
}

/// Dar ekran: her konaklama tipi için kategorileri alt alta gösteren kart.
class _RowCards extends StatelessWidget {
  const _RowCards({required this.table, required this.palette});

  final TariffTable table;
  final _TariffPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in table.satirlar)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RowTitle(row: row, palette: p, emphasize: true),
                    const SizedBox(height: 6),
                    for (final c in table.kategoriler)
                      if (row.fiyatlar[c.id] != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  c.ad,
                                  style: TextStyle(
                                    color: p.label,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _PriceText(
                                price: row.fiyatlar[c.id],
                                palette: p,
                                align: TextAlign.end,
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RowTitle extends StatelessWidget {
  const _RowTitle({
    required this.row,
    required this.palette,
    this.emphasize = false,
  });

  final TariffRow row;
  final _TariffPalette palette;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (row.kisi != null) '${row.kisi} kişi',
      if (row.birim != null) row.birim!,
      if (row.aciklama != null) row.aciklama!,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          row.ad,
          style: TextStyle(
            color: palette.title,
            fontSize: emphasize ? 13 : 12.5,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
            height: 1.3,
          ),
        ),
        if (sub.isNotEmpty)
          Text(
            sub,
            style: TextStyle(color: palette.label, fontSize: 11, height: 1.3),
          ),
      ],
    );
  }
}

class _PriceText extends StatelessWidget {
  const _PriceText({
    required this.price,
    required this.palette,
    required this.align,
  });

  final TariffPrice? price;
  final _TariffPalette palette;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final amount = price?.amount;
    if (amount != null) {
      return Text(
        formatTl(amount),
        textAlign: align,
        style: TextStyle(
          color: palette.value,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
    return Text(
      price?.text ?? '—',
      textAlign: align,
      style: TextStyle(
        color: palette.label,
        fontSize: 12,
        fontStyle: price?.text != null ? FontStyle.italic : FontStyle.normal,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.icon,
    required this.title,
    required this.items,
    required this.palette,
  });

  final IconData icon;
  final String title;
  final List<String> items;
  final _TariffPalette palette;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final p = palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: p.title,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 3),
              child: Text(
                '• $item',
                style: TextStyle(color: p.label, fontSize: 12.5, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

/// Geçerlilik, son güncelleme, doğrulama ve kaynak — yalnızca veri varsa.
class PriceMetaFooter extends StatelessWidget {
  const PriceMetaFooter({
    super.key,
    this.gecerlilik,
    this.guncelleme,
    this.dogrulama,
    this.kaynak,
  });

  final String? gecerlilik;
  final String? guncelleme;
  final TariffVerification? dogrulama;
  final String? kaynak;

  bool get isEmpty =>
      gecerlilik == null &&
      guncelleme == null &&
      dogrulama == null &&
      kaynak == null;

  static String _formatDate(String raw) {
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();
    final p = _TariffPalette(context);
    final style = TextStyle(color: p.label, fontSize: 11.5, height: 1.35);
    final uri = kaynak == null ? null : Uri.tryParse(kaynak!);
    final isLink = uri != null && uri.hasScheme && uri.host.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dogrulama != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  dogrulama!.isConfirmed
                      ? Icons.verified_outlined
                      : Icons.help_outline_rounded,
                  size: 14,
                  color: dogrulama!.isConfirmed
                      ? AppColors.primary
                      : const Color(0xFFE08A00),
                ),
                const SizedBox(width: 5),
                Text(
                  dogrulama!.label,
                  style: style.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        if (gecerlilik != null) Text('Geçerlilik: $gecerlilik', style: style),
        if (guncelleme != null)
          Text('Son güncelleme: ${_formatDate(guncelleme!)}', style: style),
        if (kaynak != null)
          isLink
              ? InkWell(
                  onTap: () =>
                      launchUrl(uri, mode: LaunchMode.externalApplication),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text.rich(
                      TextSpan(
                        text: 'Kaynak: ',
                        style: style,
                        children: [
                          TextSpan(
                            text: uri.host.replaceFirst('www.', ''),
                            style: style.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : Text('Kaynak: $kaynak', style: style),
      ],
    );
  }
}
