import 'package:flutter/material.dart';

import '../billing/pro_service.dart';
import '../navigation/rotalink_shell_routes.dart';

/// Üst çubuk Pro girişı — hava durumu ile aynı iki satırlık ölçü.
class RotalinkProChip extends StatelessWidget {
  const RotalinkProChip({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ProService.instance.isPro,
      builder: (_, _, _) {
        final active = ProService.instance.hasProAccess;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap ??
                () {
                  Navigator.of(context).pushNamed(RotalinkShellRoutes.pro);
                },
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF6C343),
                    Color(0xFFE09A12),
                    Color(0xFFC47A00),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF6C343).withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    active
                        ? Icons.verified_rounded
                        : Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 5),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Pro',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      if (!active)
                        Text(
                          'Ol',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            height: 1.05,
                          ),
                        ),
                    ],
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
