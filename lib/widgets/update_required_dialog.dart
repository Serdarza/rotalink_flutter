import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Zorunlu güncelleme uyarısı dialog'u
class UpdateRequiredDialog extends StatelessWidget {
  const UpdateRequiredDialog({
    super.key,
    required this.currentVersion,
    this.message,
    required this.storeUrl,
    required this.onDismiss,
  });

  final String currentVersion;
  final String? message;
  final String storeUrl;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.system_update,
            color: Theme.of(context).primaryColor,
            size: 28,
          ),
          const SizedBox(width: 12),
          const Text('Güncelleme Gerekli'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message ??
                'Rotalink uygulamasının yeni bir sürümü yayımlandı. '
                    'En iyi deneyim için lütfen güncelleyin.',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Text(
                  'Mevcut Sürüm: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  currentVersion,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            onDismiss();
            Navigator.of(context).pop();
          },
          child: const Text('Daha Sonra'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            final url = Uri.parse(storeUrl);
            try {
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            } catch (_) {}
            onDismiss();
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.storefront_outlined, size: 18),
          label: const Text('Mağazaya Git'),
        ),
      ],
    );
  }

  static Future<void> show(
    BuildContext context, {
    required String currentVersion,
    String? message,
    required String storeUrl,
    required VoidCallback onDismiss,
  }) {
    return showDialog(
      context: context,
      builder: (context) => UpdateRequiredDialog(
        currentVersion: currentVersion,
        message: message,
        storeUrl: storeUrl,
        onDismiss: onDismiss,
      ),
      barrierDismissible: false,
    );
  }
}
