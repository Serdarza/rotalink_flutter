import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/store_links.dart';
import '../models/misafirhane.dart';

const _kRed = Color(0xFFD32F2F);
const _kRedDark = Color(0xFFB71C1C);

enum _InfoErrorKind {
  price('Fiyat yanlış', Icons.payments_outlined),
  phone('Telefon yanlış', Icons.phone_disabled_outlined),
  closed('Tesis kapalı', Icons.door_front_door_outlined),
  address('Adres yanlış', Icons.wrong_location_outlined),
  discontinued('Tesis artık hizmet vermiyor', Icons.block_outlined),
  other('Diğer', Icons.more_horiz_rounded);

  const _InfoErrorKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Tesis detayının altında: "Bu bilgide hata mı var?" kartı.
class FacilityInfoErrorReportCard extends StatelessWidget {
  const FacilityInfoErrorReportCard({super.key, required this.facility});

  final Misafirhane facility;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? _kRed.withValues(alpha: 0.12) : const Color(0xFFFFF5F5);
    final border = isDark
        ? _kRed.withValues(alpha: 0.35)
        : const Color(0xFFFFCDD2);
    final body = isDark
        ? Colors.white.withValues(alpha: 0.70)
        : const Color(0xFF6D4C4C);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: isDark ? 0.22 : 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.report_gmailerrorred_rounded,
                color: _kRed,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bu bilgide hata mı var?',
                    style: TextStyle(
                      color: isDark ? Colors.white : _kRedDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Yanlış fiyat, telefon veya adres gördüyseniz bize bildirin.',
                    style: TextStyle(color: body, fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () => unawaited(
                showFacilityInfoErrorReportSheet(context, facility: facility),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _kRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Bildir'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hata türü seçimi + açıklama; e-posta uygulaması şablonla açılır.
Future<void> showFacilityInfoErrorReportSheet(
  BuildContext context, {
  required Misafirhane facility,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _InfoErrorReportSheet(facility: facility),
  );
}

class _InfoErrorReportSheet extends StatefulWidget {
  const _InfoErrorReportSheet({required this.facility});

  final Misafirhane facility;

  @override
  State<_InfoErrorReportSheet> createState() => _InfoErrorReportSheetState();
}

class _InfoErrorReportSheetState extends State<_InfoErrorReportSheet> {
  final _selected = <_InfoErrorKind>{};
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _submit() async {
    final note = _note.text.trim();
    if (_selected.isEmpty) {
      _snack('Lütfen en az bir hata türü seçin.');
      return;
    }
    if (_selected.contains(_InfoErrorKind.other) && note.isEmpty) {
      _snack('"Diğer" için lütfen kısa bir açıklama yazın.');
      return;
    }

    setState(() => _sending = true);
    try {
      final f = widget.facility;
      final kinds = _InfoErrorKind.values.where(_selected.contains);
      final buffer = StringBuffer()
        ..writeln('Tesis: ${f.isim}')
        ..writeln('İl: ${f.il}${f.ilce.trim().isEmpty ? '' : ' / ${f.ilce}'}')
        ..writeln('Tip: ${f.tip}')
        ..writeln()
        ..writeln('Uygulamadaki kayıt:')
        ..writeln('  Telefon: ${f.telefon.trim().isEmpty ? '—' : f.telefon}')
        ..writeln('  Adres: ${f.adres.trim().isEmpty ? '—' : f.adres}')
        ..writeln()
        ..writeln('Bildirilen hata:');
      for (final k in kinds) {
        buffer.writeln('  • ${k.label}');
      }
      if (note.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('Açıklama:')
          ..writeln(note);
      }

      final uri = Uri(
        scheme: 'mailto',
        path: StoreLinks.supportEmail,
        query:
            {
                  'subject': 'Bilgi hatası — ${f.il} / ${f.isim}',
                  'body': buffer.toString().trim(),
                }.entries
                .map(
                  (e) =>
                      '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
                )
                .join('&'),
      );

      final ok = await launchUrl(uri);
      if (!mounted) return;
      if (!ok) {
        _snack(
          'E-posta uygulaması açılamadı. ${StoreLinks.supportEmail} adresine yazabilirsiniz.',
        );
        return;
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.58)
        : const Color(0xFF6B7280);
    final f = widget.facility;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _kRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.report_gmailerrorred_rounded,
                    color: _kRed,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Bilgi hatası bildir',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Hatalı olan bilgileri seçin. Bildiriminiz e-posta ile ekibimize '
              'iletilir ve kontrol edildikten sonra güncellenir.',
              style: TextStyle(fontSize: 13, height: 1.4, color: muted),
            ),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Icon(Icons.apartment_rounded, size: 20, color: muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.isim,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            f.il,
                            style: TextStyle(fontSize: 12.5, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Hata türü',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final k in _InfoErrorKind.values) ...[
              _KindTile(
                kind: k,
                selected: _selected.contains(k),
                onTap: () => setState(() {
                  if (!_selected.remove(k)) _selected.add(k);
                }),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            Text(
              _selected.contains(_InfoErrorKind.other)
                  ? 'Açıklama (zorunlu)'
                  : 'Açıklama (isteğe bağlı)',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _note,
              maxLines: 4,
              minLines: 3,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Doğru bilgi, telefon numarası veya kaynak…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).hintColor,
                ),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF8FAFB),
                contentPadding: const EdgeInsets.all(14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kRed, width: 1.4),
                ),
              ),
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
              label: Text(_sending ? 'Hazırlanıyor…' : 'E-posta ile bildir'),
              style: FilledButton.styleFrom(
                backgroundColor: _kRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Gönder tuşuna bastığınızda e-posta uygulamanız hazır metinle açılır.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final _InfoErrorKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idleBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE5E7EB);
    final fg = selected
        ? _kRed
        : (isDark
              ? Colors.white.withValues(alpha: 0.85)
              : const Color(0xFF374151));

    return Material(
      color: selected
          ? _kRed.withValues(alpha: isDark ? 0.16 : 0.06)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? _kRed.withValues(alpha: 0.7) : idleBorder,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(kind.icon, size: 20, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  kind.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(selected),
                  size: 20,
                  color: selected ? _kRed : idleBorder,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
