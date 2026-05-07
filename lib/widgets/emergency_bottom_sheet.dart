import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/simple_location_service.dart';

/// Kotlin [MainActivity.showEmergencySheet] + [bottom_sheet_emergency.xml].
Future<void> showEmergencyBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _EmergencySheetScaffold(),
  );
}

class _EmergencySheetScaffold extends StatefulWidget {
  const _EmergencySheetScaffold();

  @override
  State<_EmergencySheetScaffold> createState() => _EmergencySheetScaffoldState();
}

class _EmergencySheetScaffoldState extends State<_EmergencySheetScaffold> {
  double? _lat;
  double? _lon;
  bool _locDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resolveLocation());
    });
  }

  Future<void> _resolveLocation() async {
    // İzin zaten verilmişse direkt konuma geç.
    if (!await Permission.locationWhenInUse.isGranted) {
      // Bu oturumda reddedilmişse tekrar sorma.
      if (await SimpleLocationService.isLocationPermissionDeclinedByUser()) {
        if (mounted) setState(() => _locDone = true);
        return;
      }
      final granted =
          await SimpleLocationService.ensureLocationPermissionFromUserAction();
      if (!granted) {
        // Reddetti — snackbar göster, bu oturumda bir daha sorma.
        if (mounted) setState(() => _locDone = true);
        final st = await Permission.locationWhenInUse.status;
        if (st.isPermanentlyDenied && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Konum izni kapalı. Ayarlardan açabilirsiniz.',
                style: TextStyle(fontSize: 15),
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Ayarlar',
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
        return;
      }
    }
    // İzin var — konumu al.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        if (mounted) {
          setState(() {
            _lat = last.latitude;
            _lon = last.longitude;
            _locDone = true;
          });
        }
        return;
      }
      final cur = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 4),
        ),
      );
      if (!mounted) return;
      setState(() {
        _lat = cur.latitude;
        _lon = cur.longitude;
        _locDone = true;
      });
    } catch (_) {
      if (mounted) setState(() => _locDone = true);
    }
  }

  Uri _mapsSearchUri(String query) {
    final enc = Uri.encodeComponent(query);
    if (_lat != null && _lon != null) {
      return Uri.parse(
        'https://www.google.com/maps/search/$enc/@$_lat,$_lon,14z',
      );
    }
    return Uri.parse('https://www.google.com/maps/search/$enc');
  }

  Future<void> _openMaps(String query) async {
    final uri = _mapsSearchUri(query);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Harita açılamadı')),
        );
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Çevirici açılamadı')),
        );
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final locOk = _lat != null && _lon != null;
    final statusText = !_locDone
        ? 'Konum alınıyor…'
        : locOk
            ? '📍 Konum alındı — yakın noktalar haritada gösterilecek'
            : '📍 Konum bilinmiyor — harita kendi konumunu kullanacak';
    final statusBg = !_locDone
        ? const Color(0xFFFFF8E1)
        : locOk
            ? const Color(0xFFF1F8E9)
            : const Color(0xFFFFF8E1);
    final statusFg = !_locDone
        ? const Color(0xFFFF8F00)
        : locOk
            ? const Color(0xFF388E3C)
            : const Color(0xFFFF8F00);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (_, scroll) {
        return ListView(
          controller: scroll,
          padding: EdgeInsets.zero,
          children: [
            Container(
              color: const Color(0xFFD32F2F),
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.emergency, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Acil & Sağlık Radarı',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Konumunuza en yakın sağlık noktaları',
                          style: TextStyle(color: Color(0xFFFFCDD2), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: statusBg,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.my_location, size: 16, color: statusFg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(fontSize: 12, color: statusFg),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _mapRow(
              iconBg: const Color(0xFF2E7D32),
              iconColor: Colors.white,
              leading: const _EmergencyHilalIcon(),
              title: 'Nöbetçi Eczane',
              subtitle: 'En yakın nöbetçi eczaneleri bul',
              onTap: () => unawaited(_openMaps('nöbetçi eczane')),
            ),
            _dividerInset(),
            _mapRow(
              iconBg: const Color(0xFFD32F2F),
              iconColor: Colors.white,
              leading: const _EmergencyHilalIcon(),
              title: 'Acil Servis',
              subtitle: 'En yakın acil servisi bul ve yol al',
              onTap: () => unawaited(_openMaps('acil servis hastane')),
            ),
            _dividerInset(),
            _mapRow(
              icon: Icons.domain,
              iconBg: const Color(0xFF1565C0),
              iconColor: Colors.white,
              leading: null,
              title: 'Devlet Hastanesi',
              subtitle: 'En yakın devlet hastanesini bul',
              onTap: () => unawaited(_openMaps('devlet hastanesi')),
            ),
            _dividerInset(),
            _mapRow(
              icon: Icons.child_care,
              iconBg: const Color(0xFFE65100),
              iconColor: Colors.white,
              leading: null,
              title: 'Çocuk Doktoru / Pediatri',
              subtitle: 'En yakın çocuk kliniği ve pediatri',
              onTap: () => unawaited(_openMaps('çocuk hastanesi pediatri')),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Önemli Numaralar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),
            ),
            _callRow(
              code: '112',
              codeBg: const Color(0xFFD32F2F),
              title: '112 Acil Çağrı Merkezi',
              body:
                  'Polis, Jandarma, İtfaiye ve Ambulans tek numarada birleşti. Tek arama, her kapıyı açar.',
              callTint: const Color(0xFFD32F2F),
              onTap: () => unawaited(_dial('112')),
            ),
            _dividerInset(marginStart: 84),
            _callRow(
              code: '159',
              codeBg: const Color(0xFF1565C0),
              title: 'ALO 159 · Karayolları',
              body: 'Yol durumu, trafik, otoyol ve karayolu danışma hattı.',
              callTint: const Color(0xFF1565C0),
              onTap: () => unawaited(_dial('159')),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Text(
                'Harita yönlendirmesi Google Maps ile · Numaralar çevirici ekranında açılır',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _dividerInset({double marginStart = 78}) {
    return Divider(height: 1, indent: marginStart, color: const Color(0xFFF5F5F5));
  }

  Widget _mapRow({
    IconData? icon,
    Widget? leading,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    assert(icon != null || leading != null);
    final avatarChild = leading ??
        Icon(icon!, color: iconColor, size: 24);
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: iconBg,
                radius: 22,
                child: avatarChild,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF212121),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _callRow({
    required String code,
    required Color codeBg,
    required String title,
    required String body,
    required Color callTint,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: codeBg,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF212121),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF757575),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.call, color: callTint, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

/// Acil sayfasında nöbetçi eczane / acil servis satırlarında artı yerine hilal.
class _EmergencyHilalIcon extends StatelessWidget {
  const _EmergencyHilalIcon();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size(26, 26),
      painter: _HilalPainter(color: Colors.white),
    );
  }
}

class _HilalPainter extends CustomPainter {
  const _HilalPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    final outer = Path()
      ..addOval(Rect.fromLTWH(w * 0.08, h * 0.12, w * 0.62, h * 0.76));
    final inner = Path()
      ..addOval(Rect.fromLTWH(w * 0.38, h * 0.14, w * 0.52, h * 0.72));
    final crescent = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(crescent, paint);
  }

  @override
  bool shouldRepaint(covariant _HilalPainter oldDelegate) =>
      oldDelegate.color != color;
}
