import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_rating_prefs.dart';
import '../theme/app_colors.dart';

const _playStoreUrl =
    'https://play.google.com/store/apps/details?id=com.serdarza.rotalink';

/// Çift geri çıkışında veya puan isteme koşulunda gösterilir.
Future<void> showAppRatingDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Rotalink’i beğendiniz mi?'),
        content: const Text(
          'Deneyiminizi geliştirmek için Play Store’da puanlayabilir veya daha sonra hatırlatabilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await AppRatingPrefs.setDeferred();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Ertele'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              await AppRatingPrefs.setRated();
              final uri = Uri.parse(_playStoreUrl);
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Puan Ver'),
          ),
        ],
      );
    },
  );
}
