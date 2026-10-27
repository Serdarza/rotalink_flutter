import 'package:flutter/material.dart';
import '../models/misafirhane.dart';
import '../services/weather_service.dart';
import '../theme/weather_badge_palette.dart';
import '../utils/safe_map_coordinates.dart';

typedef FacilityWeatherLoader =
    Future<WeatherSnapshot?> Function({
      required double latitude,
      required double longitude,
    });

/// Always queries the displayed facility, never the user's GPS or a default city.
class FacilityWeatherBadge extends StatefulWidget {
  const FacilityWeatherBadge({super.key, required this.facility, this.loader});
  final Misafirhane facility;
  final FacilityWeatherLoader? loader;
  static final _cache =
      <String, ({DateTime at, Future<WeatherSnapshot?> value})>{};
  @override
  State<FacilityWeatherBadge> createState() => _FacilityWeatherBadgeState();
}

class _FacilityWeatherBadgeState extends State<FacilityWeatherBadge> {
  late Future<WeatherSnapshot?> _weather = _load();
  Future<WeatherSnapshot?> _load() {
    final f = widget.facility;
    if (f.latitude == 0 ||
        f.longitude == 0 ||
        !isValidWgs84LatLng(f.latitude, f.longitude)) {
      return Future.value(null);
    }
    if (widget.loader != null) {
      return widget.loader!(latitude: f.latitude, longitude: f.longitude);
    }
    final key = '${f.latitude},${f.longitude}';
    final cached = FacilityWeatherBadge._cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < WeatherService.refreshInterval) {
      return cached.value;
    }
    if (FacilityWeatherBadge._cache.length >= 100) {
      FacilityWeatherBadge._cache.remove(
        FacilityWeatherBadge._cache.keys.first,
      );
    }
    final future = WeatherService.fetchCurrent(
      latitude: f.latitude,
      longitude: f.longitude,
    );
    FacilityWeatherBadge._cache[key] = (at: DateTime.now(), value: future);
    return future;
  }

  @override
  void didUpdateWidget(FacilityWeatherBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.facility.stableFacilityId !=
            widget.facility.stableFacilityId ||
        oldWidget.facility.latitude != widget.facility.latitude ||
        oldWidget.facility.longitude != widget.facility.longitude ||
        oldWidget.loader != widget.loader) {
      _weather = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WeatherSnapshot?>(
    future: _weather,
    builder: (context, snapshot) {
      final weather =
          snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasError &&
              (snapshot.data?.tempC.isFinite ?? false)
          ? snapshot.data
          : null;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: weatherBadgeGradient(weather?.iconCode ?? ''),
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              weather?.emoji ?? '🌡️',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, height: 1),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                weather?.tempLabel ?? '—',
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              widget.facility.il,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              snapshot.connectionState == ConnectionState.waiting
                  ? 'Yükleniyor'
                  : weather?.description ?? 'Hava bilgisi yok',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10.5),
            ),
          ],
        ),
      );
    },
  );
}
