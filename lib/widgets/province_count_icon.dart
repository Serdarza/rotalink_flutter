import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// İldeki tesis sayısını küçük, net bir daire olarak çizer.
abstract final class ProvinceCountIcon {
  static Future<BitmapDescriptor> create(
    int count, {
    double pixelRatio = 3,
  }) async {
    final ratio = pixelRatio.clamp(2.0, 4.0);
    final digits = count.abs().toString().length;
    final logical = switch (digits) {
      >= 3 => 24.0,
      2 => 21.0,
      _ => 18.0,
    };
    final size = (logical * ratio).ceilToDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final radius = (logical / 2 - 1.6) * ratio;

    canvas.drawCircle(
      center.translate(0, ratio * 0.6),
      radius,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ratio * 1.1),
    );
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF007B8F));
    canvas.drawCircle(
      center,
      radius - ratio * 0.35,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = ratio * 1.05,
    );

    final fontSize = (digits >= 3 ? 8.0 : digits == 2 ? 9.0 : 10.0) * ratio;
    final painter = TextPainter(
      text: TextSpan(
        text: '$count',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1,
          letterSpacing: digits >= 3 ? -0.4 * ratio : -0.15 * ratio,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final maxText = radius * 1.45;
    final scale = painter.width > maxText ? maxText / painter.width : 1.0;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();

    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: logical,
      height: logical,
    );
  }
}
