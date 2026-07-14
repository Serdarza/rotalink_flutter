import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/firebase_rota_repository.dart';
import '../models/route_plan_outcome.dart';
import '../navigator_keys.dart';
import 'kami_bubble.dart';
import 'kami_fab.dart';
import 'kami_messages.dart';
import 'kami_page.dart';

/// Oturum boyunca balon gösterim durumu (process lifetime).
abstract final class KamiSessionState {
  static bool bubbleConsumed = false;
}

/// Harita üzerindeki KAMİ FAB + konuşma balonu.
class KamiMapOverlay extends StatefulWidget {
  const KamiMapOverlay({
    super.key,
    required this.repository,
    this.initialData,
    this.userLocationHint,
    this.onRoutePlan,
    this.fabAnchorKey,
  });

  final FirebaseRotaRepository repository;
  final RotaDataState? initialData;
  final LatLng? userLocationHint;

  /// KAMİ'den haritaya rota aktarımı.
  final Future<void> Function(RoutePlanOutcome outcome)? onRoutePlan;

  /// İlk açılış turu spotlight hedefi.
  final Key? fabAnchorKey;

  /// ACİL FAB'ın hemen üstündeki küçük boşluk.
  static const double gapAboveEmergencyFab = 10;

  @override
  State<KamiMapOverlay> createState() => _KamiMapOverlayState();
}

class _KamiMapOverlayState extends State<KamiMapOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fade;
  late final String _bubbleMessage;

  Timer? _showTimer;
  Timer? _hideTimer;
  bool _bubbleVisible = false;

  @override
  void initState() {
    super.initState();
    _bubbleMessage = KamiMessages.pickRandomBubbleMessage();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);

    if (!KamiSessionState.bubbleConsumed) {
      _showTimer = Timer(const Duration(seconds: 3), _revealBubble);
    }
  }

  void _revealBubble() {
    if (!mounted || KamiSessionState.bubbleConsumed) return;
    setState(() => _bubbleVisible = true);
    _fadeController.forward();
    _hideTimer = Timer(const Duration(seconds: 5), _autoHideBubble);
  }

  Future<void> _autoHideBubble() async {
    if (!mounted || !_bubbleVisible) return;
    await _fadeController.reverse();
    if (!mounted) return;
    KamiSessionState.bubbleConsumed = true;
    setState(() => _bubbleVisible = false);
  }

  Future<void> _dismissBubble() async {
    _hideTimer?.cancel();
    if (!_bubbleVisible) {
      KamiSessionState.bubbleConsumed = true;
      return;
    }
    await _fadeController.reverse();
    if (!mounted) return;
    KamiSessionState.bubbleConsumed = true;
    setState(() => _bubbleVisible = false);
  }

  Future<void> _openKami() async {
    unawaited(_dismissBubble());
    final outcome = await pushOnRootNavigator<RoutePlanOutcome>(
      MaterialPageRoute<RoutePlanOutcome>(
        builder: (_) => KamiPage(
          repository: widget.repository,
          initialData: widget.initialData,
          userLocationHint: widget.userLocationHint,
        ),
      ),
    );
    if (!mounted || outcome == null || outcome.stops.isEmpty) return;
    final handler = widget.onRoutePlan;
    if (handler != null) {
      await handler(outcome);
    }
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_bubbleVisible)
          FadeTransition(
            opacity: _fade,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: KamiBubble(
                message: _bubbleMessage,
                onTap: () => unawaited(_openKami()),
                onDismiss: () => unawaited(_dismissBubble()),
              ),
            ),
          ),
        KeyedSubtree(
          key: widget.fabAnchorKey,
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: KamiFab(onPressed: () => unawaited(_openKami())),
          ),
        ),
      ],
    );
  }
}
