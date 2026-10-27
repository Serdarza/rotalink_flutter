import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/misafirhane.dart';

/// Konaklama tesisinin numarasını seçtirir ve sistemin telefon ekranını açar.
/// Tek numarada ek seçim göstermez; iki numarada kullanıcı seçer.
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
          final colors = Theme.of(sheetContext).colorScheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Aramak istediğiniz numarayı seçin',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  facility.isim,
                  style: TextStyle(color: colors.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),
                for (var i = 0; i < numbers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Icon(Icons.call_outlined, color: colors.primary),
                        title: Text(
                          numbers[i],
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text((i + 1).toString() + '. telefon numarası'),
                        trailing: Icon(Icons.chevron_right, color: colors.primary),
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
    // Yalnızca kullanıcının seçtiği numara tel: URI'sine aktarılır.
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
