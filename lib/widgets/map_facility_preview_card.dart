import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/misafirhane.dart';

/// Marker üstünde süzülen minimal şeffaf etiket — yalnızca tesis adı.
class MapFacilityPreviewCard extends StatelessWidget {
  const MapFacilityPreviewCard({
    super.key,
    required this.misafirhane,
  });

  final Misafirhane misafirhane;

  @override
  Widget build(BuildContext context) {
    final name = misafirhane.isim.trim();
    if (name.isEmpty) return const SizedBox.shrink();

    const fill = Color(0xB3000000);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ),
          ),
        ),
        CustomPaint(
          size: const Size(14, 7),
          painter: _PreviewCaretPainter(fill),
        ),
      ],
    );
  }
}

class _PreviewCaretPainter extends CustomPainter {
  const _PreviewCaretPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PreviewCaretPainter oldDelegate) =>
      oldDelegate.color != color;
}
