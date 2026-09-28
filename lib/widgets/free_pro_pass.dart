import 'dart:async';

import 'package:flutter/material.dart';

import '../billing/pro_service.dart';
import '../theme/app_colors.dart';

/// Ücretsiz Pro'nun kalan süresi: "42:13".
String formatFreePassRemaining(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

/// Başlatmadan önce onay: süre başladıktan sonra durdurulamaz.
Future<bool> confirmAndStartFreePass(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(
        Icons.timer_outlined,
        color: AppColors.primary,
        size: 32,
      ),
      title: const Text('1 saat ücretsiz Pro'),
      content: const Text(
        'Tüm Pro özellikleri 1 saat boyunca açılır. Bu hak her kullanıcıya '
        'yalnızca bir kez verilir ve başladıktan sonra durdurulamaz.\n\n'
        'Konaklama araştırmanıza hazır olduğunuzda başlatmanızı öneririz.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Daha sonra'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Şimdi başlat'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  return ProService.instance.startFreePass();
}

/// Ücretsiz Pro sürerken her saniye yeniden çizilen kalan süre.
class FreePassCountdown extends StatefulWidget {
  const FreePassCountdown({super.key, required this.builder});

  final Widget Function(BuildContext context, Duration? remaining) builder;

  @override
  State<FreePassCountdown> createState() => _FreePassCountdownState();
}

class _FreePassCountdownState extends State<FreePassCountdown> {
  final ProService _pro = ProService.instance;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _pro.freePassEndsAt.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pro.freePassEndsAt.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final active = _pro.freePassEndsAt.value != null;
    if (active && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active) {
      _tick?.cancel();
      _tick = null;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final end = _pro.freePassEndsAt.value;
    Duration? remaining;
    if (end != null) {
      final d = end.difference(DateTime.now());
      remaining = d.isNegative ? Duration.zero : d;
    }
    return widget.builder(context, remaining);
  }
}

/// Uygulamanın altında süren ücretsiz Pro'yu gösteren küçük şerit.
class FreePassPill extends StatelessWidget {
  const FreePassPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FreePassCountdown(
      builder: (context, remaining) {
        if (remaining == null) return const SizedBox.shrink();
        return Material(
          color: AppColors.primary,
          elevation: 4,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ücretsiz Pro · ${formatFreePassRemaining(remaining)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
