import 'package:flutter/material.dart';

import '../constants/public_holidays_2026.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

/// Kotlin [MainActivity.showHolidaysDialog] + [dialog_holidays] listesi.
Future<void> showDrawerHolidaysDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Material(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 360,
            height: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text(
                    AppStrings.drawerHolidays,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: kPublicHolidays2026.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final h = kPublicHolidays2026[i];
                      return ListTile(
                        title: Text(
                          h.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          [h.dateLine, if (h.detail.isNotEmpty) h.detail].join(' · '),
                          style: const TextStyle(fontSize: 12, color: AppColors.campaignSummaryMuted),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Kapat'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
