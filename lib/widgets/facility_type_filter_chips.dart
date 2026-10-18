import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/facility_filter_provider.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';

/// Ana harita üstünde yatay kaydırılabilir 4 sabit tesis tipi filtresi.
///
/// Seçili çip: dolu turkuaz + beyaz yazı + onay işareti.
/// Pasif çip: beyaz yüzey + ince gri çerçeve + koyu gri yazı.
class FacilityTypeFilterChips extends ConsumerWidget {
  const FacilityTypeFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(facilityTypeFilterProvider);
    final dark = AppColors.isDark(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < kFacilityTypeFilterOptions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _chip(
              context,
              ref,
              label: kFacilityTypeFilterOptions[i],
              selected: active == kFacilityTypeFilterOptions[i],
              dark: dark,
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required bool selected,
    required bool dark,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: true,
      checkmarkColor: AraUi.activeForeground,
      onSelected: (_) {
        ref.read(facilityTypeFilterProvider.notifier).state = label;
      },
      selectedColor: AraUi.activeFill,
      backgroundColor: dark ? AppColors.darkSurface : AraUi.inactiveFillOf(context),
      labelStyle: TextStyle(
        color: selected
            ? AraUi.activeForeground
            : (dark ? AppColors.darkTextStrong : AraUi.inactiveForegroundOf(context)),
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 13,
      ),
      side: BorderSide(
        color: selected
            ? AraUi.activeFill
            : (dark ? AppColors.darkBorder : AraUi.inactiveBorderOf(context)),
      ),
      shape: const StadiumBorder(),
      elevation: 0,
      pressElevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
