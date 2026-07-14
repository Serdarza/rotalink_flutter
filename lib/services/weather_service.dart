import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import 'weather_api_config.dart';

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.tempC,
    required this.iconCode,
    required this.cityName,
    required this.description,
  });

  final double tempC;
  final String iconCode;
  final String cityName;
  final String description;

  String get emoji => WeatherService.emojiForIcon(iconCode);
  String get tempLabel => '${tempC.round()}°';
}

abstract final class WeatherService {
  static const _refreshInterval = Duration(minutes: 30);

  static Duration get refreshInterval => _refreshInterval;

  static String emojiForIcon(String icon) {
    if (icon.startsWith('01')) return icon.endsWith('d') ? '☀️' : '🌙';
    if (icon.startsWith('02')) return '⛅';
    if (icon.startsWith('03') || icon.startsWith('04')) return '☁️';
    if (icon.startsWith('09')) return '🌧️';
    if (icon.startsWith('10')) return '🌦️';
    if (icon.startsWith('11')) return '⛈️';
    if (icon.startsWith('13')) return '❄️';
    if (icon.startsWith('50')) return '🌫️';
    return '🌡️';
  }

  static Future<WeatherSnapshot?> fetchCurrent({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(
      '${WeatherApiConfig.weatherUrl}?lat=$latitude&lon=$longitude'
      '&appid=${WeatherApiConfig.apiKey}&units=metric&lang=tr',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('WeatherService: HTTP ${res.statusCode}');
        }
        return null;
      }
      final root = jsonDecode(res.body) as Map<String, dynamic>;
      final main = root['main'] as Map<String, dynamic>?;
      final weather = (root['weather'] as List?)?.cast<dynamic>();
      if (main == null || weather == null || weather.isEmpty) return null;
      final w0 = weather.first as Map<String, dynamic>;
      final temp = (main['temp'] as num?)?.toDouble();
      if (temp == null) return null;
      final desc = (w0['description']?.toString() ?? '').trim();
      return WeatherSnapshot(
        tempC: temp,
        iconCode: w0['icon']?.toString() ?? '01d',
        cityName: root['name']?.toString() ?? '',
        description: desc,
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('WeatherService: $e\n$st');
      return null;
    }
  }
}
