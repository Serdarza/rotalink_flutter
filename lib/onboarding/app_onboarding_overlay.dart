import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import 'app_onboarding_controller.dart';

/// İlk açılış spotlight + adım kartı.
class AppOnboardingOverlay extends StatefulWidget {
  const AppOnboardingOverlay({
    super.key,
    required this.controller,
  });

  final AppOnboardingController controller;

  @override
  State<AppOnboardingOverlay> createState() => _AppOnboardingOverlayState();
}

class _AppOnboardingOverlayState extends State<AppOnboardingOverlay> {
  Rect? _hole;
  final GlobalKey _overlayKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHole());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureHole();
    });
  }

  void _measureHole() {
    if (!widget.controller.active) {
      if (_hole != null) setState(() => _hole = null);
      return;
    }
    final step = widget.controller.currentStep;

    Rect? next;
    final target = step.target;
    if (target != null) {
      next = widget.controller.targetRectIn(target);
      if (next != null) {
        next = next.inflate(6);
      }
    }
    if (_hole != next) setState(() => _hole = next);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.active) return const SizedBox.shrink();

    final step = widget.controller.currentStep;
    final isCenter = step.align == OnboardingTooltipAlign.center;

    return KeyedSubtree(
      key: _overlayKey,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(
                painter: _SpotlightPainter(hole: _hole),
                child: const SizedBox.expand(),
              ),
            ),
            if (isCenter)
              Center(child: _StepCard(
                controller: widget.controller,
                step: step,
                onLayout: _measureHole,
              ))
            else
              _PositionedStepCard(
                controller: widget.controller,
                step: step,
                hole: _hole,
                onLayout: _measureHole,
              ),
          ],
        ),
      ),
    );
  }
}

class _PositionedStepCard extends StatelessWidget {
  const _PositionedStepCard({
    required this.controller,
    required this.step,
    required this.hole,
    required this.onLayout,
  });

  final AppOnboardingController controller;
  final OnboardingStep step;
  final Rect? hole;
  final VoidCallback onLayout;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    const margin = 16.0;
    const cardMaxW = 340.0;
    final cardW = (mq.width - margin * 2).clamp(0.0, cardMaxW);

    double top;
    double left;

    if (hole == null) {
      left = (mq.width - cardW) / 2;
      top = mq.height * 0.38;
    } else {
      switch (step.align) {
        case OnboardingTooltipAlign.above:
          top = (hole!.top - 12 - 220).clamp(margin, mq.height - 240);
          left = ((hole!.center.dx - cardW / 2).clamp(margin, mq.width - cardW - margin));
        case OnboardingTooltipAlign.below:
          top = (hole!.bottom + 12).clamp(margin, mq.height - 240);
          left = ((hole!.center.dx - cardW / 2).clamp(margin, mq.width - cardW - margin));
        case OnboardingTooltipAlign.left:
          top = ((hole!.center.dy - 100).clamp(margin, mq.height - 240));
          left = (hole!.left - cardW - 12).clamp(margin, mq.width - cardW - margin);
          if (left + cardW > hole!.left - 8) {
            left = (hole!.left - cardW - 12).clamp(margin, mq.width - cardW - margin);
          }
          if (left < margin + 20) {
            top = (hole!.bottom + 12).clamp(margin, mq.height - 240);
            left = ((hole!.center.dx - cardW / 2).clamp(margin, mq.width - cardW - margin));
          }
        case OnboardingTooltipAlign.center:
          left = (mq.width - cardW) / 2;
          top = mq.height * 0.38;
      }
    }

    return Positioned(
      left: left,
      top: top,
      width: cardW,
      child: _StepCard(
        controller: controller,
        step: step,
        onLayout: onLayout,
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.controller,
    required this.step,
    required this.onLayout,
  });

  final AppOnboardingController controller;
  final OnboardingStep step;
  final VoidCallback onLayout;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => onLayout());

    final stepNo = controller.stepIndex + 1;
    final total = controller.stepCount;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Material(
        key: ValueKey<int>(controller.stepIndex),
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (step.icon != null)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(step.icon, color: AppColors.primary, size: 22),
                    ),
                  if (step.icon != null) const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      step.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                step.body,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.45,
                  color: AppColors.textPrimary.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '$stepNo / $total',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.campaignSummaryMuted,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => unawaited(controller.skip()),
                    child: Text(AppStrings.onboardingSkip),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: () => unawaited(controller.next()),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    child: Text(
                      controller.isLastStep
                          ? AppStrings.onboardingFinish
                          : AppStrings.onboardingNext,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({this.hole});

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    Path path = full;
    if (hole != null) {
      final cut = Path()
        ..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(14)));
      path = Path.combine(PathOperation.difference, full, cut);
    }
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.74),
    );
    if (hole != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole!, const Radius.circular(14)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole;
}
