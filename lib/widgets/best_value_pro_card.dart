import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../billing/price_access.dart';
import '../billing/pro_service.dart';
import '../constants/facility_pricing.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../theme/app_colors.dart';
import '../utils/best_value_facility.dart';
import 'facility_tariff_view.dart' show formatTl;

const _gold = Color(0xFFF2C14E);
const _goldDeep = Color(0xFFB8860B);
const _tealDark = Color(0xFF00566B);

/// Arama sonuçlarının en üstünde: fiyatı doğrulanmış en uygun konaklama.
/// Pro değilse tesis adı ve tutar bulanık; dokununca Pro ekranı açılır.
/// Pro ise gerçek tesis ve tutar görünür; dokununca [onOpenFacility].
class BestValueProCard extends StatelessWidget {
  const BestValueProCard({
    super.key,
    required this.pick,
    required this.onOpenFacility,
  });
  final BestValuePick pick;
  final VoidCallback onOpenFacility;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ProService.instance.isPro,
    builder: (context, _, _) {
      final unlocked = PriceAccess.unlocked;
      final title = pick.isComparison
          ? (pick.il != null
                ? FacilityPricing.bestValueTitleIl(pick.il!)
                : FacilityPricing.bestValueTitle)
          : FacilityPricing.bestValueSingleTitle;
      final basis = pick.basis == BestValueBasis.sivil
          ? FacilityPricing.sivilLabel
          : FacilityPricing.kamuLabel;
      void open() {
        if (unlocked) {
          onOpenFacility();
        } else {
          Navigator.of(context).pushNamed(RotalinkShellRoutes.pro);
        }
      }

      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unlocked)
            Text(
              [
                pick.facility.il,
                pick.facility.ilce,
              ].where((s) => s.trim().isNotEmpty).join(' / '),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          Text(
            [
              if (unlocked && pick.facility.tip.trim().isNotEmpty)
                pick.facility.tip,
              basis,
            ].join(' · '),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      );
      final amount = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          unlocked
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatTl(pick.price),
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              : const _Blurred(text: '0.000 TL', fontSize: 22, color: _gold),
          const Text(
            FacilityPricing.bestValueUnit,
            style: TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Semantics(
          button: true,
          label: unlocked
              ? '${pick.facility.isim}, ${formatTl(pick.price)}'
              : '$title. ${FacilityPricing.bestValueCta}',
          child: Material(
            clipBehavior: Clip.antiAlias,
            color: _tealDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: _gold, width: 1.4),
            ),
            child: Ink(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, _tealDark],
                ),
              ),
              child: InkWell(
                onTap: open,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: _ProBadge(),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: unlocked
                                ? Text(
                                    pick.facility.isim,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  )
                                : Text(
                                    title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, box) {
                          final stacked =
                              box.maxWidth < 310 ||
                              MediaQuery.textScalerOf(context).scale(14) > 20;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 40,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.hotel_rounded,
                                  color: _gold,
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (stacked)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      details,
                                      const SizedBox(height: 6),
                                      amount,
                                    ],
                                  ),
                                )
                              else ...[
                                Expanded(child: details),
                                const SizedBox(width: 8),
                                SizedBox(width: 115, child: amount),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      _CtaButton(unlocked: unlocked, onTap: open),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_gold, _goldDeep]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded, size: 13, color: Colors.white),
          SizedBox(width: 3),
          Text(
            'PRO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gerçek veriyi değil sabit yer tutucu metni bulanıklaştırır (ekran görüntüsünden okunamaz).
class _Blurred extends StatelessWidget {
  const _Blurred({
    required this.text,
    required this.fontSize,
    this.color = Colors.white,
  });

  final String text;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.unlocked, required this.onTap});

  final bool unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(
          unlocked ? Icons.arrow_forward_rounded : Icons.lock_open_rounded,
          size: 18,
        ),
        label: Text(unlocked ? 'Tesisi İncele' : FacilityPricing.bestValueCta),
        style: FilledButton.styleFrom(
          backgroundColor: unlocked ? Colors.white : _gold,
          foregroundColor: unlocked
              ? AppColors.primary
              : const Color(0xFF3D2A00),
          padding: const EdgeInsets.symmetric(vertical: 11),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
