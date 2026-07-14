import 'package:flutter/material.dart';

/// KAMİ FAB için hafif "nefes alma" (pulse) ölçek animasyonu.
///
/// ~8 saniyede bir %100 → %108 → %100; süreklilik abartılı değil.
class KamiPulseAnimation extends StatefulWidget {
  const KamiPulseAnimation({
    super.key,
    required this.child,
    this.period = const Duration(seconds: 8),
    this.peakScale = 1.08,
    this.enabled = true,
  });

  final Widget child;
  final Duration period;
  final double peakScale;
  final bool enabled;

  @override
  State<KamiPulseAnimation> createState() => _KamiPulseAnimationState();
}

class _KamiPulseAnimationState extends State<KamiPulseAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
    _rebuildCurve();
    if (widget.enabled) {
      _controller.repeat();
    }
  }

  void _rebuildCurve() {
    // Kısa nefes: periyodun başında büyüyüp küçül, kalanı idle.
    _scale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: widget.peakScale)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: widget.peakScale, end: 1)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1),
        weight: 76,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant KamiPulseAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _controller.duration = widget.period;
    }
    if (oldWidget.peakScale != widget.peakScale) {
      _rebuildCurve();
    }
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _controller.repeat();
      } else {
        _controller
          ..stop()
          ..value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Material Motion tarzı sayfa geçişi (fade + hafif yukarı kayma).
class KamiPageRoute<T> extends PageRouteBuilder<T> {
  KamiPageRoute({required WidgetBuilder builder})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 280),
        );
}
