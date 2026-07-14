import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/facility_filter_provider.dart';
import '../theme/app_colors.dart';

/// Ana harita üstünde yatay kaydırılabilir 4 sabit tesis tipi filtresi.
class FacilityTypeFilterChips extends ConsumerWidget {
  const FacilityTypeFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(facilityTypeFilterProvider);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < kFacilityTypeFilterOptions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            FilterChip(
              label: Text(kFacilityTypeFilterOptions[i]),
              selected: active == kFacilityTypeFilterOptions[i],
              showCheckmark: false,
              onSelected: (_) {
                ref.read(facilityTypeFilterProvider.notifier).state =
                    kFacilityTypeFilterOptions[i];
              },
              selectedColor: theme.colorScheme.primary,
              backgroundColor: Colors.white.withValues(alpha: 0.92),
              labelStyle: TextStyle(
                color: active == kFacilityTypeFilterOptions[i]
                    ? Colors.white
                    : AppColors.textPrimary,
                fontWeight: active == kFacilityTypeFilterOptions[i]
                    ? FontWeight.w600
                    : FontWeight.w500,
                fontSize: 13,
              ),
              side: BorderSide(
                color: active == kFacilityTypeFilterOptions[i]
                    ? theme.colorScheme.primary
                    : const Color(0x33007B8F),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}
