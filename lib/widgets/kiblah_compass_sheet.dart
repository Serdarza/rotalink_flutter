import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_qiblah/flutter_qiblah.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;

import '../theme/app_colors.dart';

/// Ana ekrandan çağrılacak giriş noktası.
void showKiblahCompassSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _KiblahCompassSheet(),
  );
}

// ---------------------------------------------------------------------------

class _KiblahCompassSheet extends StatefulWidget {
  const _KiblahCompassSheet();

  @override
  State<_KiblahCompassSheet> createState() => _KiblahCompassSheetState();
}

class _KiblahCompassSheetState extends State<_KiblahCompassSheet> {
  StreamSubscription<QiblahDirection>? _sub;
  double _heading = 0;
  double _qiblah = 0;
  bool _loading = true;
  String? _error;
  bool _hapticLock = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final status = await FlutterQiblah.checkLocationStatus();
      if (!status.enabled ||
          status.status == LocationPermission.denied ||
          status.status == LocationPermission.deniedForever) {
        await FlutterQiblah.requestPermissions();
      }
      _sub = FlutterQiblah.qiblahStream.listen(
        (data) {
          if (!mounted) return;
          _checkHaptic(data.direction, data.offset);
          setState(() {
            _heading = data.direction;
            _qiblah = data.offset;
            _loading = false;
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'Pusula sensörüne erişilemiyor.';
          });
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Pusula başlatılamadı. Sensör veya konum izni gerekiyor.';
        });
      }
    }
  }

  void _checkHaptic(double heading, double qiblah) {
    final diff = (heading - qiblah).abs() % 360;
    final aligned = diff < 3 || diff > 357;
    if (aligned && !_hapticLock) {
      _hapticLock = true;
      HapticFeedback.mediumImpact();
    } else if (!aligned) {
      _hapticLock = false;
    }
  }

  static String _dirName(double d) {
    const dirs = ['K', 'KD', 'D', 'GD', 'G', 'GB', 'B', 'KB'];
    return dirs[((d + 22.5) / 45).floor() % 8];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A2460), Color(0xFF0D1443)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          // Başlık
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.explore_outlined, color: AppColors.white, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Pusula & Kıble Yönü',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          if (_loading) ...[
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: AppColors.white),
            const SizedBox(height: 16),
            const Text(
              'Konum ve sensör hazırlanıyor…',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 40),
          ] else if (_error != null) ...[
            const SizedBox(height: 24),
            const Icon(Icons.sensors_off_rounded, color: Colors.redAccent, size: 52),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 14),
            ),
            const SizedBox(height: 24),
          ] else ...[
            _CompassWidget(heading: _heading, qiblah: _qiblah),
            const SizedBox(height: 28),
            // Dijital bilgi paneli
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _InfoChip(
                    icon: Icons.navigation_rounded,
                    iconColor: Colors.white,
                    label: 'Kuzey',
                    value: '${_heading.toStringAsFixed(0)}°',
                    sub: _dirName(_heading),
                    color: AppColors.white,
                  ),
                  Container(width: 1, height: 56, color: Colors.white12),
                  _InfoChip(
                    icon: Icons.mosque_rounded,
                    iconColor: const Color(0xFF69F0AE),
                    label: 'Kıble',
                    value: '${_qiblah.toStringAsFixed(0)}°',
                    sub: _dirName(_qiblah),
                    color: const Color(0xFF69F0AE),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Yeşil ok Kâbe yönünü gösterir • Hizalandığında titreşir',
              style: TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pusula widget'ı
// ---------------------------------------------------------------------------

class _CompassWidget extends StatelessWidget {
  const _CompassWidget({required this.heading, required this.qiblah});

  final double heading;
  final double qiblah;

  @override
  Widget build(BuildContext context) {
    const size = 268.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Statik kadran (halka + çizgiler + yön yazıları)
          CustomPaint(
            painter: _DialPainter(),
            size: const Size(size, size),
          ),
          // Dönen pusula ibresi (kırmızı = Kuzey, gri = Güney)
          Transform.rotate(
            angle: -heading * pi / 180,
            child: CustomPaint(
              painter: _NeedlePainter(),
              size: const Size(size, size),
            ),
          ),
          // Kıble oku + Kâbe ikonu (birlikte döner)
          Transform.rotate(
            angle: (qiblah - heading) * pi / 180,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    painter: _QiblahArrowPainter(),
                    size: const Size(size, size),
                  ),
                  // Ok ucuna hizalanmış Kâbe ikonu
                  // len = size*0.33 ≈ 88 → shaft tip y ≈ 134-88 = 46
                  // İkon merkezi shaft tipine yaslanır: top = 46 - 14 = 32
                  Positioned(
                    top: 20,
                    left: size / 2 - 16,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B5E20),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mosque_rounded,
                        color: Color(0xFF69F0AE),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Merkez kapak
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Statik kadran painter
// ---------------------------------------------------------------------------

class _DialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Arka plan dairesi
    canvas.drawCircle(
      c,
      r - 2,
      Paint()..color = const Color(0xFF0D1443),
    );
    // Dış halka
    canvas.drawCircle(
      c,
      r - 2,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Dereceler (5° aralıkla çizgiler)
    for (var i = 0; i < 360; i += 5) {
      final isMain = i % 90 == 0;
      final isMid = i % 45 == 0;
      final len = isMain ? 14.0 : (isMid ? 9.0 : 5.0);
      final a = i * pi / 180;
      final outerR = r - 4;
      final p1 = Offset(c.dx + outerR * sin(a), c.dy - outerR * cos(a));
      final p2 = Offset(
        c.dx + (outerR - len) * sin(a),
        c.dy - (outerR - len) * cos(a),
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = isMain ? Colors.white : Colors.white38
          ..strokeWidth = isMain ? 2.0 : 1.0,
      );
    }

    // Ana yönler (K/D/G/B)
    _label(canvas, 'K', 0.0, c, r - 28, color: Colors.redAccent, fontSize: 17, bold: true);
    _label(canvas, 'D', 90.0, c, r - 28, color: Colors.white70, fontSize: 17, bold: true);
    _label(canvas, 'G', 180.0, c, r - 28, color: Colors.white70, fontSize: 17, bold: true);
    _label(canvas, 'B', 270.0, c, r - 28, color: Colors.white70, fontSize: 17, bold: true);

    // Ara yönler (KD/GD/GB/KB)
    _label(canvas, 'KD', 45.0, c, r - 29, color: Colors.white38, fontSize: 10, bold: false);
    _label(canvas, 'GD', 135.0, c, r - 29, color: Colors.white38, fontSize: 10, bold: false);
    _label(canvas, 'GB', 225.0, c, r - 29, color: Colors.white38, fontSize: 10, bold: false);
    _label(canvas, 'KB', 315.0, c, r - 29, color: Colors.white38, fontSize: 10, bold: false);
  }

  void _label(
    Canvas canvas,
    String text,
    double deg,
    Offset center,
    double radius, {
    required Color color,
    required double fontSize,
    required bool bold,
  }) {
    final a = deg * pi / 180;
    final pos = Offset(
      center.dx + radius * sin(a),
      center.dy - radius * cos(a),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ---------------------------------------------------------------------------
// Pusula ibresi painter (kırmızı=K / gri=G)
// ---------------------------------------------------------------------------

class _NeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final len = size.width * 0.36;

    // Kuzey (kırmızı)
    final northPath = Path()
      ..moveTo(c.dx, c.dy - len)
      ..lineTo(c.dx - 7, c.dy + 6)
      ..lineTo(c.dx + 7, c.dy + 6)
      ..close();
    canvas.drawPath(
      northPath,
      Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      northPath,
      Paint()
        ..color = Colors.red.shade800
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // Güney (gri)
    final southPath = Path()
      ..moveTo(c.dx, c.dy + len * 0.55)
      ..lineTo(c.dx - 7, c.dy + 6)
      ..lineTo(c.dx + 7, c.dy + 6)
      ..close();
    canvas.drawPath(southPath, Paint()..color = Colors.white30);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ---------------------------------------------------------------------------
// Kıble oku painter (yeşil)
// ---------------------------------------------------------------------------

class _QiblahArrowPainter extends CustomPainter {
  static const Color _green = Color(0xFF69F0AE);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final len = size.width * 0.33;

    // Gövde çizgisi (ikon ok ucuna konduğu için üçgen çizilmiyor)
    canvas.drawLine(
      c,
      Offset(c.dx, c.dy - len),
      Paint()
        ..color = _green
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Ok kuyruğu
    canvas.drawLine(
      Offset(c.dx, c.dy + len * 0.28),
      Offset(c.dx, c.dy + 8),
      Paint()
        ..color = _green.withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ---------------------------------------------------------------------------
// Dijital bilgi chip'i
// ---------------------------------------------------------------------------

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sub,
          style: TextStyle(
            color: color.withValues(alpha: 0.75),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
