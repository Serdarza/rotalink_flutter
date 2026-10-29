import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Google Haritalar konum iğnesi. Yazı iğnenin üstünde durur.
///
/// Gövde yaklaşık 18×28 mantıksal pikseldir; telefon ekranındaki
/// Google iğnesine yakın, kalabalık haritada baskın olmayan boyuttadır.
abstract final class MapPinIcon {
  static const start = Color(0xFFEA4335);
  static const destination = Color(0xFF34A853);
  static const facility = Color(0xFF4285F4);
  static const revealed = Color(0xFF1A73E8);
  static const browse = Color(0xFFFBBC04);

  static Future<BitmapDescriptor> create({
    required Color color,
    String? label,
  }) async {
    const ratio = 3.0;
    const pinWidth = 18.0;
    const pinHeight = 28.0;
    final text = label?.trim() ?? '';
    TextPainter? painter;
    var pillLogicalWidth = pinWidth;
    var pillLogicalHeight = 0.0;
    if (text.isNotEmpty) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: const Color(0xFF202124),
            fontSize: 11 * ratio,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      pillLogicalWidth = painter.width / ratio + 10;
      pillLogicalHeight = painter.height / ratio + 5;
    }
    final logicalWidth = text.isEmpty
        ? pinWidth + 6
        : pillLogicalWidth.clamp(pinWidth + 6, 120.0);
    final gap = text.isEmpty ? 0.0 : 3.0;
    final logicalHeight =
        pinHeight + 4 + (text.isEmpty ? 0 : pillLogicalHeight + gap);
    final pixelWidth = (logicalWidth * ratio).ceil();
    final pixelHeight = (logicalHeight * ratio).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (painter != null) {
      final pill = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          (pixelWidth - pillLogicalWidth * ratio) / 2,
          1 * ratio,
          pillLogicalWidth * ratio,
          pillLogicalHeight * ratio,
        ),
        Radius.circular(8 * ratio),
      );
      canvas.drawRRect(
        pill.shift(Offset(0, 0.5 * ratio)),
        Paint()
          ..color = const Color(0x33000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, ratio),
      );
      canvas.drawRRect(pill, Paint()..color = Colors.white);
      painter.paint(
        canvas,
        Offset(
          (pixelWidth - painter.width) / 2,
          1 * ratio + (pillLogicalHeight * ratio - painter.height) / 2,
        ),
      );
    }

    final pinTop = text.isEmpty
        ? 1.0 * ratio
        : (1 + pillLogicalHeight + gap) * ratio;
    final pinRect = Rect.fromLTWH(
      (pixelWidth - pinWidth * ratio) / 2,
      pinTop,
      pinWidth * ratio,
      pinHeight * ratio,
    );
    final pin = _googlePin(pinRect);
    canvas.drawPath(
      pin.shift(Offset(0, 0.7 * ratio)),
      Paint()
        ..color = const Color(0x38000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.1 * ratio),
    );
    canvas.drawPath(pin, Paint()..color = color);
    canvas.drawCircle(
      Offset(pinRect.center.dx, pinRect.top + pinRect.width / 2),
      pinRect.width * 0.21,
      Paint()..color = Colors.white,
    );

    final image = await recorder.endRecording().toImage(
      pixelWidth,
      pixelHeight,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: logicalWidth,
      height: logicalHeight,
    );
  }

  /// Klasik Google iğnesi: yuvarlak baş, aşağı sivrilen uç.
  static Path _googlePin(Rect box) {
    final cx = box.center.dx;
    final r = box.width / 2;
    final top = box.top;
    final cy = top + r;
    final tip = box.bottom - r * 0.04;
    return Path()
      ..moveTo(cx, top + r * 0.04)
      ..cubicTo(cx + r * 0.55, top, cx + r, cy - r * 0.55, cx + r, cy)
      ..cubicTo(cx + r, cy + r * 0.9, cx + r * 0.2, cy + r * 1.45, cx, tip)
      ..cubicTo(cx - r * 0.2, cy + r * 1.45, cx - r, cy + r * 0.9, cx - r, cy)
      ..cubicTo(cx - r, cy - r * 0.55, cx - r * 0.55, top, cx, top + r * 0.04)
      ..close();
  }
}
