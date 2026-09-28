import 'package:flutter/material.dart';

import '../constants/facility_pricing.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../theme/app_colors.dart';
import '../utils/best_value_facility.dart';
import 'facility_tariff_view.dart' show formatTl;

const _gold = Color(0xFFF2C14E);
const _goldDeep = Color(0xFFB8860B);
const _amber = Color(0xFFE08A00);

/// Konaklama listesinin üstü: Yakınlık / Fiyat (Pro) sıralaması ve
/// fiyat modunda Sivil / Kamu personeli seçimi.
class FacilitySortBar extends StatelessWidget {
  const FacilitySortBar({
    super.key,
    required this.byPrice,
    required this.basis,
    required this.unlocked,
    required this.onSelectDistance,
    required this.onSelectPrice,
    required this.onBasisChanged,
  });

  final bool byPrice;
  final BestValueBasis basis;
  final bool unlocked;
  final VoidCallback onSelectDistance;
  final VoidCallback onSelectPrice;
  final ValueChanged<BestValueBasis> onBasisChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SortChip(
                icon: Icons.near_me_rounded,
                label: FacilityPricing.sortDistance,
                selected: !byPrice,
                onTap: onSelectDistance,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: _SortChip(
                  icon: Icons.trending_up_rounded,
                  label: FacilityPricing.sortPrice,
                  selected: byPrice,
                  onTap: onSelectPrice,
                  trailing: unlocked ? null : const _MiniProBadge(),
                ),
              ),
            ],
          ),
          if (byPrice) ...[
            const SizedBox(height: 8),
            SegmentedButton<BestValueBasis>(
              segments: const [
                ButtonSegment(
                  value: BestValueBasis.sivil,
                  label: Text(FacilityPricing.sivilLabel),
                ),
                ButtonSegment(
                  value: BestValueBasis.kamu,
                  label: Text(FacilityPricing.kamuLabel),
                ),
              ],
              selected: {basis},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onBasisChanged(s.first),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                selectedBackgroundColor: AppColors.primary.withValues(alpha: 0.12),
                selectedForegroundColor: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.primary;
    return Material(
      color: selected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniProBadge extends StatelessWidget {
  const _MiniProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_gold, _goldDeep]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'PRO',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Fiyat modunda satır sonu: tek kişi / gece tutarı; doğrulanmamışsa uyarı.
class FacilityNightPriceTag extends StatelessWidget {
  const FacilityNightPriceTag({super.key, required this.price});

  final FacilityNightPrice price;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatTl(price.amount),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            FacilityPricing.bestValueUnit,
            style: TextStyle(color: Color(0xFF6B7C82), fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
          if (!price.confirmed) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.help_outline_rounded, size: 12, color: _amber),
                const SizedBox(width: 3),
                Text(
                  price.dogrulama?.label ?? FacilityPricing.unverifiedPrice,
                  style: const TextStyle(color: _amber, fontSize: 10.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Fiyatlı / fiyatsız tesisleri ayıran başlık.
class FacilityUnpricedHeader extends StatelessWidget {
  const FacilityUnpricedHeader({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF4F7F8),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Text(
        FacilityPricing.unpricedHeader(count),
        style: const TextStyle(color: Color(0xFF5B6B70), fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Pro olmayan kullanıcı fiyat sıralamasına dokununca.
Future<void> showPriceSortProTeaser(BuildContext context, int pricedCount) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_gold, _goldDeep]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.trending_up_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    FacilityPricing.sortTeaserTitle,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              FacilityPricing.sortTeaserCount(pricedCount),
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final line in FacilityPricing.sortTeaserPerks)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(color: Color(0xFF37474F), fontSize: 13.5, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).pushNamed(RotalinkShellRoutes.pro);
                },
                icon: const Icon(Icons.workspace_premium_rounded, size: 20),
                label: const Text(FacilityPricing.unlockWithProButton),
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: const Color(0xFF3D2A00),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
