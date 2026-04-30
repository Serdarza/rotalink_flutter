import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Kotlin [MainActivity.showAboutDialog] + [dialog_about] metinleri.
Future<void> showDrawerAboutDialog(BuildContext context) {
  const body =
      'Rotalink, yollara gönül vermiş ve sevdikleriyle güvenle seyahat etmek isteyenler için doğmuş bir projedir. '
      'Özellikle kamu personellerimizin; tayin, görev veya tatil yolculuklarında “Nerede güvenle konaklayabilirim?” '
      'sorusuna en hızlı cevabı verebilmek amacıyla geliştirilmiştir.\n\n'
      'Amacımız; Türkiye’nin dört bir yanındaki misafirhaneleri ve gezi rotalarını tek bir haritada birleştirmektir. '
      'Tamamen bağımsız bir çabayla tasarlanan Rotalink, sizlerin destekleriyle büyümeye devam edecektir.\n\n'
      'Rotanız hep açık olsun!';

  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final h = MediaQuery.sizeOf(ctx).height;
      return Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.campaignBtnSecondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.attractions_outlined, size: 36, color: AppColors.primary),
              ),
              const SizedBox(height: 14),
              const Text(
                'Rotalink Hakkında',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  letterSpacing: 0.02,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 48,
                height: 2,
                color: AppColors.primary,
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: (h * 0.42).clamp(160.0, 320.0),
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF333333),
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '— Rotalink Geliştirici Ekibi',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                  ),
                  child: const Text('Kapat'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
