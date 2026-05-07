import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/misafirhane.dart';

/// Paylaşım (metin / WhatsApp vb.) için Google Haritalar araması: **il + misafirhane adı** (Tesis sekmesi).
String googleMapsShareUrlForMisafirhane(Misafirhane m) {
  final il = m.il.trim();
  final isim = m.isim.trim();
  final raw = il.isEmpty
      ? isim
      : isim.isEmpty
          ? il
          : '$il $isim';
  if (raw.isNotEmpty) {
    return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(raw)}';
  }
  final lat = m.latitude;
  final lng = m.longitude;
  if (lat != 0 && lng != 0) {
    return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  }
  return 'https://www.google.com/maps';
}

/// Android’de Google Haritalar, iOS’ta Apple Haritalar; güvenilir yedek olarak https Google Maps araması.
Future<void> openInNativeMaps(
  BuildContext context, {
  required String query,
  double? latitude,
  double? longitude,
}) async {
  final hasCoords = latitude != null &&
      longitude != null &&
      latitude != 0 &&
      longitude != 0;

  Future<bool> tryLaunch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  final qEnc = Uri.encodeComponent(query);

  if (kIsWeb) {
    final u = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(hasCoords ? '$latitude,$longitude' : query)}',
    );
    await tryLaunch(u);
    return;
  }

  if (hasCoords) {
    if (Platform.isIOS) {
      final apple = Uri.parse('http://maps.apple.com/?ll=$latitude,$longitude&q=$qEnc');
      if (await tryLaunch(apple)) return;
    } else {
      final g = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
      );
      if (await tryLaunch(g)) return;
    }
    final gCoords = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    if (await tryLaunch(gCoords)) return;
  }

  if (Platform.isIOS) {
    final apple = Uri.parse('http://maps.apple.com/?q=$qEnc');
    if (await tryLaunch(apple)) return;
  }

  if (Platform.isAndroid) {
    final geo = Uri.parse('geo:0,0?q=$qEnc');
    if (await tryLaunch(geo)) return;
  }

  final fallback = Uri.parse('https://www.google.com/maps/search/?api=1&query=$qEnc');
  final ok = await tryLaunch(fallback);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Harita açılamadı')),
    );
  }
}

void _mapSearchLaunchFailed(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Harita uygulaması açılamadı')),
  );
}

/// Google Haritalar metin araması: `[İl] [Yer adı]` — standart `api=1` URL + [Uri.encodeComponent].
Future<void> openMapSearch(
  BuildContext context,
  String province,
  String placeName,
) async {
  final p = province.trim();
  final n = placeName.trim();
  if (p.isEmpty && n.isEmpty) return;
  final raw = p.isEmpty ? n : (n.isEmpty ? p : '$p $n');
  final enc = Uri.encodeComponent(raw);
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$enc');
  try {
    final can = await canLaunchUrl(uri);
    if (!context.mounted) return;
    if (!can) {
      _mapSearchLaunchFailed(context);
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) _mapSearchLaunchFailed(context);
  } catch (_) {
    if (context.mounted) _mapSearchLaunchFailed(context);
  }
}

/// Google Haritalar yönlendirme: başlangıç, isteğe bağlı ara duraklar, varış (araç).
Future<void> openGoogleDirectionsWaypoints(
  BuildContext context,
  List<LatLng> waypoints, {
  String travelMode = 'driving',
}) async {
  if (waypoints.length < 2) return;
  String fmt(LatLng p) => '${p.latitude},${p.longitude}';
  final params = <String, String>{
    'api': '1',
    'origin': fmt(waypoints.first),
    'destination': fmt(waypoints.last),
    'travelmode': travelMode,
  };
  if (waypoints.length > 2) {
    params['waypoints'] =
        waypoints.sublist(1, waypoints.length - 1).map(fmt).join('|');
  }
  final uri = Uri.https('www.google.com', '/maps/dir/', params);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      _mapSearchLaunchFailed(context);
    }
  } catch (_) {
    if (context.mounted) _mapSearchLaunchFailed(context);
  }
}

/// Yandex Haritalar çoklu nokta: `rtext=lat,lon~lat,lon~...`
Future<void> openYandexDirectionsWaypoints(
  BuildContext context,
  List<LatLng> waypoints,
) async {
  if (waypoints.length < 2) return;
  final rtext = waypoints.map((p) => '${p.latitude},${p.longitude}').join('~');
  final uri = Uri.parse('https://yandex.com/maps/?rtext=$rtext');
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      _mapSearchLaunchFailed(context);
    }
  } catch (_) {
    if (context.mounted) _mapSearchLaunchFailed(context);
  }
}

/// Google Haritalar yönlendirme — duraklar **il + misafirhane adı** (veya serbest metin).
Future<void> openGoogleDirectionsPlaceQueries(
  BuildContext context,
  List<String> placeQueries, {
  String travelMode = 'driving',
}) async {
  if (placeQueries.length < 2) return;
  final params = <String, String>{
    'api': '1',
    'origin': placeQueries.first,
    'destination': placeQueries.last,
    'travelmode': travelMode,
  };
  if (placeQueries.length > 2) {
    params['waypoints'] =
        placeQueries.sublist(1, placeQueries.length - 1).join('|');
  }
  final uri = Uri.https('www.google.com', '/maps/dir/', params);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      _mapSearchLaunchFailed(context);
    }
  } catch (_) {
    if (context.mounted) _mapSearchLaunchFailed(context);
  }
}

/// Yandex — aynı metin durakları `rtext` ile (~ ayırıcı).
Future<void> openYandexDirectionsPlaceQueries(
  BuildContext context,
  List<String> placeQueries,
) async {
  if (placeQueries.length < 2) return;
  final rtext = placeQueries.map(Uri.encodeComponent).join('~');
  final uri = Uri.parse('https://yandex.com.tr/maps/?rtext=$rtext');
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      _mapSearchLaunchFailed(context);
    }
  } catch (_) {
    if (context.mounted) _mapSearchLaunchFailed(context);
  }
}

Uri _appleMapsDirectionsUriFromPlaceQueries(List<String> placeQueries) {
  final b = StringBuffer('http://maps.apple.com/?dirflg=d');
  b.write('&saddr=${Uri.encodeComponent(placeQueries.first)}');
  for (var i = 1; i < placeQueries.length; i++) {
    b.write('&daddr=${Uri.encodeComponent(placeQueries[i])}');
  }
  return Uri.parse(b.toString());
}

/// Apple Haritalar — çoklu `daddr` ile durak zinciri; Android’de genelde Google’a düşer.
Future<void> openAppleDirectionsPlaceQueries(
  BuildContext context,
  List<String> placeQueries,
) async {
  if (placeQueries.length < 2) return;
  if (kIsWeb) {
    await openGoogleDirectionsPlaceQueries(context, placeQueries);
    return;
  }
  try {
    final uri = _appleMapsDirectionsUriFromPlaceQueries(placeQueries);
    var ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && Platform.isAndroid) {
      ok = await launchUrl(
        Uri.https('www.google.com', '/maps/dir/', {
          'api': '1',
          'origin': placeQueries.first,
          'destination': placeQueries.last,
          if (placeQueries.length > 2)
            'waypoints':
                placeQueries.sublist(1, placeQueries.length - 1).join('|'),
          'travelmode': 'driving',
        }),
        mode: LaunchMode.externalApplication,
      );
    }
    if (!ok && context.mounted) {
      _mapSearchLaunchFailed(context);
    }
  } catch (_) {
    if (context.mounted) _mapSearchLaunchFailed(context);
  }
}

/// Misafirhaneleri rota sırasıyla; her adımda il + isim ile harita uygulamasında açma.
Future<void> openMisafirhaneStepNavigation(
  BuildContext context,
  List<Misafirhane> steps,
) async {
  if (steps.isEmpty) return;
  for (var i = 0; i < steps.length; i++) {
    if (!context.mounted) return;
    final m = steps[i];
    final action = await showDialog<_MisafirhaneNavStepAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Adım ${i + 1} / ${steps.length}'),
          content: Text(
            '${m.il}\n${m.isim}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, _MisafirhaneNavStepAction.cancel),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, _MisafirhaneNavStepAction.skip),
              child: const Text('Atla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _MisafirhaneNavStepAction.openMap),
              child: const Text('Haritada aç'),
            ),
          ],
        );
      },
    );
    if (!context.mounted) return;
    if (action == _MisafirhaneNavStepAction.cancel) return;
    if (action == _MisafirhaneNavStepAction.openMap) {
      await openInNativeMaps(
        context,
        query: '${m.il} ${m.isim}'.trim(),
        latitude: m.latitude != 0 ? m.latitude : null,
        longitude: m.longitude != 0 ? m.longitude : null,
      );
    }
  }
}

enum _MisafirhaneNavStepAction { cancel, skip, openMap }
