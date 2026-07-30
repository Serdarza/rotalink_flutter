import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/facility_pricing.dart';
import '../constants/store_links.dart';
import '../models/misafirhane.dart';
import '../theme/app_colors.dart';

/// Fiyat bildir / yanlış bildir — mailto şablonlu alt sayfa.
Future<void> showFacilityPriceReportSheet(
  BuildContext context, {
  required Misafirhane facility,
  required bool isCorrection,
  String? currentSivil,
  String? currentKamu,
  String? currentKurum,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _FacilityPriceReportSheet(
      facility: facility,
      isCorrection: isCorrection,
      currentSivil: currentSivil,
      currentKamu: currentKamu,
      currentKurum: currentKurum,
    ),
  );
}

class _FacilityPriceReportSheet extends StatefulWidget {
  const _FacilityPriceReportSheet({
    required this.facility,
    required this.isCorrection,
    this.currentSivil,
    this.currentKamu,
    this.currentKurum,
  });

  final Misafirhane facility;
  final bool isCorrection;
  final String? currentSivil;
  final String? currentKamu;
  final String? currentKurum;

  @override
  State<_FacilityPriceReportSheet> createState() =>
      _FacilityPriceReportSheetState();
}

class _FacilityPriceReportSheetState extends State<_FacilityPriceReportSheet> {
  late final TextEditingController _sivil;
  late final TextEditingController _kamu;
  late final TextEditingController _kurum;
  late final TextEditingController _note;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _sivil = TextEditingController();
    _kamu = TextEditingController();
    _kurum = TextEditingController();
    _note = TextEditingController();
  }

  @override
  void dispose() {
    _sivil.dispose();
    _kamu.dispose();
    _kurum.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final sivil = _sivil.text.trim();
    final kamu = _kamu.text.trim();
    final kurum = _kurum.text.trim();
    final note = _note.text.trim();

    if (sivil.isEmpty && kamu.isEmpty && kurum.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(FacilityPricing.reportNeedOnePrice),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final f = widget.facility;
      final kind = widget.isCorrection ? 'Düzeltme' : 'Yeni bildirim';
      final buffer = StringBuffer()
        ..writeln('Tür: $kind')
        ..writeln('İl: ${f.il}')
        ..writeln('Tesis: ${f.isim}')
        ..writeln();

      if (widget.isCorrection) {
        buffer
          ..writeln('Uygulamadaki kayıt:')
          ..writeln('  Sivil: ${widget.currentSivil ?? "—"}')
          ..writeln('  Kamu: ${widget.currentKamu ?? "—"}')
          ..writeln('  Kurum: ${widget.currentKurum ?? "—"}')
          ..writeln();
      }

      buffer
        ..writeln('Bildirilen fiyatlar:')
        ..writeln('  Sivil misafir: ${sivil.isEmpty ? "—" : sivil}')
        ..writeln('  Kamu personeli: ${kamu.isEmpty ? "—" : kamu}')
        ..writeln('  Kurum personeli: ${kurum.isEmpty ? "—" : kurum}');

      if (note.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('Not / kaynak:')
          ..writeln(note);
      }

      final uri = Uri(
        scheme: 'mailto',
        path: StoreLinks.supportEmail,
        query: _encodeQueryParameters({
          'subject': 'Fiyat bildirimi — ${f.il} / ${f.isim}',
          'body': buffer.toString().trim(),
        }),
      );

      final ok = await launchUrl(uri);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(FacilityPricing.reportMailFailed),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.58)
        : const Color(0xFF6B7280);
    final title = widget.isCorrection
        ? FacilityPricing.reportSheetTitleCorrection
        : FacilityPricing.reportSheetTitleNew;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              FacilityPricing.reportSheetSubtitle,
              style: TextStyle(fontSize: 13, height: 1.4, color: muted),
            ),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF3F8F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.facility.isim,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.facility.il,
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _field(
              label: FacilityPricing.sivilLabel,
              controller: _sivil,
              hint: FacilityPricing.reportSivilHint,
            ),
            const SizedBox(height: 12),
            _field(
              label: FacilityPricing.kamuLabel,
              controller: _kamu,
              hint: FacilityPricing.reportSivilHint,
            ),
            const SizedBox(height: 12),
            _field(
              label: FacilityPricing.kurumLabel,
              controller: _kurum,
              hint: FacilityPricing.reportSivilHint,
            ),
            const SizedBox(height: 12),
            _field(
              label: 'Not / kaynak',
              controller: _note,
              hint: FacilityPricing.reportNoteHint,
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            Text(
              FacilityPricing.reportDisclaimer,
              style: TextStyle(fontSize: 11.5, height: 1.35, color: muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.mail_outline_rounded, size: 20),
              label: Text(
                _sending ? 'Hazırlanıyor…' : FacilityPricing.reportSubmit,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          textInputAction:
              maxLines == 1 ? TextInputAction.next : TextInputAction.done,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: Theme.of(context).hintColor,
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF8FAFB),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.14),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.14),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
