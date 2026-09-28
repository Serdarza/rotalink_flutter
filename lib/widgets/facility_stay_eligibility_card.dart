import 'package:flutter/material.dart';

import '../constants/facility_stay_rules.dart';
import '../models/misafirhane.dart';
import '../theme/app_colors.dart';

Color stayAccessColor(StayAccess a) => switch (a) {
  StayAccess.allowed => const Color(0xFF2E7D32),
  StayAccess.conditional => const Color(0xFFE08600),
  StayAccess.notAllowed => const Color(0xFFC62828),
};

IconData stayAccessIcon(StayAccess a) => switch (a) {
  StayAccess.allowed => Icons.check_circle_rounded,
  StayAccess.conditional => Icons.error_rounded,
  StayAccess.notAllowed => Icons.cancel_rounded,
};

String stayCivilBadge(StayAccess a) => switch (a) {
  StayAccess.allowed => 'Sivillere açık',
  StayAccess.conditional => 'Siviller şartlı',
  StayAccess.notAllowed => 'Sivil konaklayamaz',
};

/// Tesis detayında "Kimler konaklayabilir?" — tesis tipine göre gruplar
/// ve açılır "Nasıl kalınır?" adımları.
class FacilityStayEligibilityCard extends StatefulWidget {
  const FacilityStayEligibilityCard({super.key, required this.facility});

  final Misafirhane facility;

  @override
  State<FacilityStayEligibilityCard> createState() =>
      _FacilityStayEligibilityCardState();
}

class _FacilityStayEligibilityCardState
    extends State<FacilityStayEligibilityCard> {
  bool _howToOpen = false;

  static Color _accessColor(StayAccess a) => stayAccessColor(a);
  static IconData _accessIcon(StayAccess a) => stayAccessIcon(a);
  static String _civilBadge(StayAccess a) => stayCivilBadge(a);

  @override
  Widget build(BuildContext context) {
    final rule = FacilityStayRules.forFacility(widget.facility);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E2528) : Colors.white;
    final hairline = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppColors.primary.withValues(alpha: 0.08);
    final titleColor = isDark
        ? Colors.white.withValues(alpha: 0.96)
        : AppColors.textPrimary;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.60)
        : AppColors.textPrimary.withValues(alpha: 0.60);
    final badgeColor = _accessColor(rule.civilAccess);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hairline),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.groups_2_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kimler konaklayabilir?',
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rule.authority,
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: isDark ? 0.20 : 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    _civilBadge(rule.civilAccess),
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final (i, g) in rule.groups.indexed) ...[
              if (i > 0) Divider(height: 18, thickness: 1, color: hairline),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      _accessIcon(g.access),
                      size: 19,
                      color: _accessColor(g.access),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.title,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          g.detail,
                          style: TextStyle(
                            color: muted,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Material(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _howToOpen = !_howToOpen),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.checklist_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Nasıl kalınır?',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          AnimatedRotation(
                            turns: _howToOpen ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.expand_more_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: !_howToOpen
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  right: 4,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final (i, step) in rule.howTo.indexed)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 20,
                                              height: 20,
                                              alignment: Alignment.center,
                                              decoration: const BoxDecoration(
                                                color: AppColors.primary,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Text(
                                                '${i + 1}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                step,
                                                style: TextStyle(
                                                  color: titleColor,
                                                  fontSize: 12.5,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    FacilityStayRules.disclaimer,
                    style: TextStyle(color: muted, fontSize: 11, height: 1.35),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
