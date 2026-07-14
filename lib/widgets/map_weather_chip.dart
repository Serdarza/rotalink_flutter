import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/user_location_cache.dart';
import '../data/firebase_rota_repository.dart' show RotaDataState;
import '../services/weather_location_resolver.dart';
import '../services/weather_service.dart';
import '../theme/app_colors.dart';
import 'weather_bottom_sheet.dart';

/// Ana harita üst çubuk / sağ üst — sıcaklık + hava durumu emojisi; dokununca detay sheet.
class MapWeatherChip extends StatefulWidget {
  const MapWeatherChip({
    super.key,
    this.compact = false,
    this.liveGps,
    this.locationGranted = false,
    this.focusedCity,
    this.mapCenter,
    this.rotaData,
  });

  final bool compact;
  final LatLng? liveGps;
  final bool locationGranted;
  final String? focusedCity;
  final LatLng? mapCenter;
  final RotaDataState? rotaData;

  @override
  State<MapWeatherChip> createState() => _MapWeatherChipState();
}

class _MapWeatherChipState extends State<MapWeatherChip> {
  LatLng? _cachedGps;
  WeatherSnapshot? _snapshot;
  WeatherLocationTarget? _target;
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
    _refreshTimer = Timer.periodic(WeatherService.refreshInterval, (_) {
      unawaited(_loadWeather());
    });
  }

  @override
  void didUpdateWidget(MapWeatherChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final depsChanged = oldWidget.liveGps?.latitude != widget.liveGps?.latitude ||
        oldWidget.liveGps?.longitude != widget.liveGps?.longitude ||
        oldWidget.locationGranted != widget.locationGranted ||
        oldWidget.focusedCity != widget.focusedCity ||
        oldWidget.mapCenter?.latitude != widget.mapCenter?.latitude ||
        oldWidget.mapCenter?.longitude != widget.mapCenter?.longitude ||
        oldWidget.rotaData != widget.rotaData;
    if (depsChanged) unawaited(_loadWeather());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _cachedGps = await UserLocationCache.load();
    await _loadWeather();
  }

  Future<void> _loadWeather() async {
    final live = widget.locationGranted ? widget.liveGps : null;
    final target = WeatherLocationResolver.resolve(
      liveGps: live,
      cachedGps: _cachedGps,
      focusedCity: widget.focusedCity,
      mapCenter: widget.mapCenter,
      rotaData: widget.rotaData,
    );
    final snap = await WeatherService.fetchCurrent(
      latitude: target.latitude,
      longitude: target.longitude,
    );
    if (!mounted) return;
    setState(() {
      _target = target;
      _snapshot = snap;
      _loading = false;
    });
  }

  String? _subtitle() {
    final target = _target;
    final snap = _snapshot;
    if (target == null) return null;
    if (target.source == WeatherLocationSource.gps) {
      final city = snap?.cityName.trim();
      return city != null && city.isNotEmpty ? city : null;
    }
    if (target.displayName != null && target.displayName!.isNotEmpty) {
      return target.displayName;
    }
    final city = snap?.cityName.trim();
    if (city != null && city.isNotEmpty) return city;
    if (target.source == WeatherLocationSource.cachedGps) {
      return WeatherLocationSource.cachedGps.label;
    }
    if (target.source == WeatherLocationSource.mapCenter) {
      return WeatherLocationSource.mapCenter.label;
    }
    return target.source.label;
  }

  List<Color> _gradientForIcon(String icon) {
    if (icon.startsWith('01')) {
      return const [Color(0xFFFFB347), Color(0xFFFF8C42), Color(0xFFE85D04)];
    }
    if (icon.startsWith('02') || icon.startsWith('03') || icon.startsWith('04')) {
      return const [Color(0xFF90A4AE), Color(0xFF607D8B), Color(0xFF455A64)];
    }
    if (icon.startsWith('09') || icon.startsWith('10')) {
      return const [Color(0xFF4FC3F7), Color(0xFF0288D1), Color(0xFF01579B)];
    }
    if (icon.startsWith('11')) {
      return const [Color(0xFF5C6BC0), Color(0xFF3949AB), Color(0xFF283593)];
    }
    if (icon.startsWith('13')) {
      return const [Color(0xFFB3E5FC), Color(0xFF81D4FA), Color(0xFF4FC3F7)];
    }
    if (icon.startsWith('50')) {
      return const [Color(0xFFB0BEC5), Color(0xFF78909C), Color(0xFF546E7A)];
    }
    return [
      AppColors.drawerHeaderGradientStart,
      AppColors.drawerHeaderGradientEnd,
      AppColors.purple500.withValues(alpha: 0.9),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    final icon = snap?.iconCode ?? '01d';
    final subtitle = _subtitle();
    final radius = widget.compact ? 14.0 : 18.0;

    return Material(
      color: Colors.transparent,
      elevation: widget.compact ? 0 : 6,
      shadowColor: AppColors.primary.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: () => unawaited(showWeatherBottomSheet(context)),
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _gradientForIcon(icon),
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 8 : 12,
            vertical: widget.compact ? 3 : 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading && snap == null)
                SizedBox(
                  width: widget.compact ? 16 : 22,
                  height: widget.compact ? 16 : 22,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Text(
                  snap?.emoji ?? '🌡️',
                  style: TextStyle(
                    fontSize: widget.compact ? 18 : 24,
                    height: 1,
                  ),
                ),
              SizedBox(width: widget.compact ? 5 : 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: widget.compact ? 76 : 120,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snap != null ? snap.tempLabel : '—',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: widget.compact ? 15 : 18,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: widget.compact ? 10 : 11,
                          fontWeight: FontWeight.w600,
                          height: 1.05,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
