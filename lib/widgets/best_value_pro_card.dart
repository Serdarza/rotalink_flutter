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
class BestValueProCard extends StatefulWidget {
  const BestValueProCard({
    super.key,
    required this.pick,
    required this.onOpenFacility,
  });

  final BestValuePick pick;
  final VoidCallback onOpenFacility;

  @override
  State<BestValueProCard> createState() => _BestValueProCardState();
}

class _BestValueProCardState extends State<BestValueProCard>
    with SingleTickerProviderStateMixin {
  static const _sweeps = 3;

  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  int _sweepsDone = 0;

  @override
  void initState() {
    super.initState();
    ProService.instance.isPro.addListener(_onProChanged);
    _shine.addStatusListener((s) {
      if (s != AnimationStatus.completed || !mounted) return;
      _sweepsDone++;
      if (_sweepsDone < _sweeps) {
        Future<void>.delayed(const Duration(milliseconds: 450), () {
          if (mounted) _shine.forward(from: 0);
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) return;
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _shine.forward(from: 0);
      });
    });
  }

  @override
  void dispose() {
    ProService.instance.isPro.removeListener(_onProChanged);
    _shine.dispose();
    super.dispose();
  }

  void _onProChanged() {
    if (mounted) setState(() {});
  }

  void _onTap() {
    if (PriceAccess.unlocked) {
      widget.onOpenFacility();
    } else {
      Navigator.of(context).pushNamed(RotalinkShellRoutes.pro);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pick = widget.pick;
    final unlocked = PriceAccess.unlocked;
    final title = pick.isComparison
        ? (pick.il != null
            ? FacilityPricing.bestValueTitleIl(pick.il!)
            : FacilityPricing.bestValueTitle)
        : FacilityPricing.bestValueSingleTitle;
    final basisLabel = pick.basis == BestValueBasis.sivil
        ? FacilityPricing.sivilLabel
        : FacilityPricing.kamuLabel;
    final tip = pick.facility.tip.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Semantics(
        button: true,
        label: unlocked
            ? '$title: ${pick.facility.isim}, ${formatTl(pick.price)}'
            : '$title. ${FacilityPricing.bestValueCta}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, _tealDark],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _gold.withValues(alpha: 0.85), width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: _gold.withValues(alpha: 0.28),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const _ProBadge(),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.hotel_rounded, color: _gold, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    unlocked
                                        ? Text(
                                            pick.facility.isim,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              height: 1.2,
                                            ),
                                          )
                                        : const _Blurred(
                                            text: 'Gizli tesis adı',
                                            fontSize: 15,
                                          ),
                                    const SizedBox(height: 3),
                                    Text(
                                      [if (unlocked && tip.isNotEmpty) tip, basisLabel].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.78),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  unlocked
                                      ? Text(
                                          formatTl(pick.price),
                                          style: const TextStyle(
                                            color: _gold,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        )
                                      : const _Blurred(text: '0.000 TL', fontSize: 17, color: _gold),
                                  Text(
                                    FacilityPricing.bestValueUnit,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.75),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (pick.isComparison) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(Icons.verified_outlined,
                                    size: 14, color: Colors.white.withValues(alpha: 0.8)),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    FacilityPricing.bestValueCompared(pick.comparedCount),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          _CtaButton(unlocked: unlocked, onTap: _onTap),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _shine,
                          builder: (context, _) {
                            if (!_shine.isAnimating) return const SizedBox.shrink();
                            final t = Curves.easeInOutCubic.transform(_shine.value);
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment(-3 + 5 * t, -1),
                                  end: Alignment(-1 + 5 * t, 1),
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.28),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                  stops: const [0.35, 0.5, 0.65],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  const _Blurred({required this.text, required this.fontSize, this.color = Colors.white});

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
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w800),
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
        icon: Icon(unlocked ? Icons.arrow_forward_rounded : Icons.lock_open_rounded, size: 18),
        label: Text(unlocked ? FacilityPricing.bestValueOpen : FacilityPricing.bestValueCta),
        style: FilledButton.styleFrom(
          backgroundColor: unlocked ? Colors.white : _gold,
          foregroundColor: unlocked ? AppColors.primary : const Color(0xFF3D2A00),
          padding: const EdgeInsets.symmetric(vertical: 11),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
