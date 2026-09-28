import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../billing/price_access.dart';
import '../constants/facility_pricing.dart';
import '../data/facility_compare_selection.dart';
import '../models/misafirhane.dart';
import '../screens/facility_compare_screen.dart';
import '../theme/app_colors.dart';
import 'facility_sort_bar.dart' show showProFeatureTeaser;

const _gold = Color(0xFFF2C14E);
const _goldDeep = Color(0xFFB8860B);

Future<void> openFacilityCompare(BuildContext context, {LatLng? userLocation}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FacilityCompareScreen(userLocation: userLocation),
    ),
  );
}

Future<void> showCompareProTeaser(BuildContext context) => showProFeatureTeaser(
      context,
      icon: Icons.compare_arrows_rounded,
      title: FacilityPricing.compareTeaserTitle,
      headline: FacilityPricing.compareTeaserHeadline,
      perks: FacilityPricing.compareTeaserPerks,
    );

/// Tesis detayında "Karşılaştırmaya ekle" satırı; seçim 2+ olunca "Karşılaştır (n)".
class FacilityCompareButton extends StatelessWidget {
  const FacilityCompareButton({super.key, required this.facility, this.userLocation});

  final Misafirhane facility;
  final LatLng? userLocation;

  void _onToggle(BuildContext context) {
    if (!PriceAccess.unlocked) {
      showCompareProTeaser(context);
      return;
    }
    final selection = FacilityCompareSelection.instance;
    if (!selection.toggle(facility)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text(FacilityPricing.compareFull)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E2528) : Colors.white;
    final hairline = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppColors.primary.withValues(alpha: 0.08);
    return ValueListenableBuilder<List<Misafirhane>>(
      valueListenable: FacilityCompareSelection.instance,
      builder: (context, selected, _) {
        final unlocked = PriceAccess.unlocked;
        final inList = unlocked && selected.any((x) => x.sameFavoriteIdentity(facility));
        final canOpen = unlocked && selected.length >= 2;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _onToggle(context),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      foregroundColor: AppColors.primary,
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    icon: Icon(
                      inList ? Icons.check_circle_rounded : Icons.compare_arrows_rounded,
                      size: 20,
                    ),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            inList ? FacilityPricing.compareAdded : FacilityPricing.compareAdd,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!unlocked) ...[const SizedBox(width: 6), const CompareProBadge()],
                      ],
                    ),
                  ),
                ),
                if (canOpen)
                  FilledButton(
                    onPressed: () => openFacilityCompare(context, userLocation: userLocation),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                    child: Text(FacilityPricing.compareOpen(selected.length)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Arama listesinin üstünde, karşılaştırmaya tesis eklenmişken görünen çubuk.
class FacilityCompareBar extends StatelessWidget {
  const FacilityCompareBar({super.key, required this.selected, this.userLocation});

  final List<Misafirhane> selected;
  final LatLng? userLocation;

  @override
  Widget build(BuildContext context) {
    final canOpen = selected.length >= 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            children: [
              const Icon(Icons.compare_arrows_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  canOpen
                      ? selected.map((m) => m.isim.trim()).join(' · ')
                      : FacilityPricing.compareNeedTwo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: FacilityCompareSelection.instance.clear,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF5B6B70),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(FacilityPricing.compareClear),
              ),
              if (canOpen)
                FilledButton(
                  onPressed: () => openFacilityCompare(context, userLocation: userLocation),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  child: Text(FacilityPricing.compareOpen(selected.length)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompareProBadge extends StatelessWidget {
  const CompareProBadge({super.key});

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
