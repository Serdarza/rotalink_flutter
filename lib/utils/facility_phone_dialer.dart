import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/misafirhane.dart';

/// Konaklama tesisleri için tek arama akışı.
abstract final class FacilityPhoneDialer {
  static Future<void> open(BuildContext context, Misafirhane facility) async {
    final numbers = facility.telefonNumaralari;
    if (numbers.isEmpty) {
      _message(context, 'Telefon numarası mevcut değil.');
      return;
    }

    String? selected = numbers.first;
    if (numbers.length > 1) {
      selected = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) {
          final theme = Theme.of(sheetContext);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Aramak istediğiniz numarayı seçin',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  facility.isim,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < numbers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Icon(
                          Icons.call_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(
                          numbers[i],
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('Telefon ${i + 1}'),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.primary,
                        ),
                        onTap: () => Navigator.of(sheetContext).pop(numbers[i]),
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Vazgeç'),
                ),
              ],
            ),
          );
        },
      );
    }

    if (selected == null) return;
    final dialString = selected.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: dialString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        _message(context, 'Telefon ekranı açılamadı.');
      }
    } catch (_) {
      if (context.mounted) _message(context, 'Telefon ekranı açılamadı.');
    }
  }

  static void _message(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
