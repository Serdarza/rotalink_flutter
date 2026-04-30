import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../services/simple_location_service.dart';
import '../theme/app_colors.dart';

/// Kotlin [WeatherBottomSheet] ile aynı: OpenWeatherMap 2.5 + Nominatim.
const _owmApiKey = '6ef5a34093512e8ce92ff4e845063e80';
const _weatherUrl = 'https://api.openweathermap.org/data/2.5/weather';
const _forecastUrl = 'https://api.openweathermap.org/data/2.5/forecast';
const _nominatimUrl = 'https://nominatim.openstreetmap.org/search';

const _kNominatimUa = 'RotaLink/3.2 (android; com.serdarza.rotalink)';

Future<void> showWeatherBottomSheet(BuildContext context) async {
  var lat = 39.0;
  var lon = 35.0;
  if (context.mounted) {
    // İzin yoksa ve bu oturumda reddedilmemişse iste.
    var geoStatus = await Geolocator.checkPermission();
    if (geoStatus != LocationPermission.whileInUse && geoStatus != LocationPermission.always) {
      if (!await SimpleLocationService.isLocationPermissionDeclinedByUser()) {
        final granted =
            await SimpleLocationService.ensureLocationPermissionFromUserAction();
        if (!granted) {
          geoStatus = await Geolocator.checkPermission();
          if (geoStatus == LocationPermission.deniedForever && context.mounted) {
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
                  onPressed: () => Geolocator.openAppSettings(),
                ),
              ),
            );
          }
        }
      }
    }
    // İzin verilmişse konumu al (red durumunda fallback Türkiye merkezi).
    geoStatus = await Geolocator.checkPermission();
    if (geoStatus == LocationPermission.whileInUse || geoStatus == LocationPermission.always) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          lat = last.latitude;
          lon = last.longitude;
        } else {
          final cur = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 8),
            ),
          );
          lat = cur.latitude;
          lon = cur.longitude;
        }
      } catch (_) {}
    }
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => _WeatherSheetBody(
        initialLat: lat,
        initialLon: lon,
        scrollController: scroll,
      ),
    ),
  );
}

class _WeatherSheetBody extends StatefulWidget {
  const _WeatherSheetBody({
    required this.initialLat,
    required this.initialLon,
    required this.scrollController,
  });

  final double initialLat;
  final double initialLon;
  final ScrollController scrollController;

  @override
  State<_WeatherSheetBody> createState() => _WeatherSheetBodyState();
}

class _WeatherSheetBodyState extends State<_WeatherSheetBody> {
  late double _lat;
  late double _lon;
  bool _daily = true;
  bool _loading = true;
  bool _loadingForecast = false;
  String? _error;
  String? _cityLabel;

  Map<String, dynamic>? _weatherJson;
  List<_ForecastDay>? _forecastDays;

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lon = widget.initialLon;
    unawaited(_fetchCurrent());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static String _owmEmoji(String icon) {
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

  Uri _weatherUri(double la, double lo) => Uri.parse(
        '$_weatherUrl?lat=$la&lon=$lo&appid=$_owmApiKey&units=metric&lang=tr',
      );

  Uri _forecastUri(double la, double lo) => Uri.parse(
        '$_forecastUrl?lat=$la&lon=$lo&appid=$_owmApiKey&units=metric&lang=tr',
      );

  /// OpenWeather 2.5 genelde `dt_txt` verir; yoksa `dt` ile yerel takvim gününe göre grupla.
  String? _forecastDayKey(Map<String, dynamic> o) {
    final dtTxt = o['dt_txt']?.toString();
    if (dtTxt != null && dtTxt.length >= 10) {
      return dtTxt.substring(0, 10);
    }
    final raw = o['dt'];
    final sec = raw is int ? raw : (raw is num ? raw.toInt() : null);
    if (sec == null) return null;
    final local = DateTime.fromMillisecondsSinceEpoch(sec * 1000, isUtc: true).toLocal();
    return DateFormat('yyyy-MM-dd').format(local);
  }

  List<_ForecastDay> _parseForecastDays(Map<String, dynamic> root) {
    final list = root['list'] as List<dynamic>? ?? [];
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in list) {
      if (item is! Map) continue;
      final o = item.map((k, v) => MapEntry(k.toString(), v));
      final key = _forecastDayKey(o);
      if (key == null) continue;
      grouped.putIfAbsent(key, () => []).add(o);
    }
    if (grouped.isEmpty) return const [];

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final dayFmt = DateFormat('EEEE', 'tr_TR');
    final sortedKeys = grouped.keys.toList()..sort();
    final days = <_ForecastDay>[];

    for (final dateStr in sortedKeys) {
      if (days.length >= 7) break;
      final items = grouped[dateStr]!;
      final temps = <double>[];
      for (final it in items) {
        final mainMap = it['main'];
        if (mainMap is! Map) continue;
        final m = mainMap.map((k, v) => MapEntry(k.toString(), v));
        for (final k in ['temp', 'temp_min', 'temp_max']) {
          final v = (m[k] as num?)?.toDouble();
          if (v != null) temps.add(v);
        }
      }
      if (temps.isEmpty) continue;

      Map<String, dynamic>? pick;
      for (final h in ['12:00:00', '15:00:00', '09:00:00', '18:00:00']) {
        for (final it in items) {
          if ('${it['dt_txt']}'.contains(h)) {
            pick = it;
            break;
          }
        }
        if (pick != null) break;
      }
      pick ??= items[items.length ~/ 2];

      final w0 = (pick['weather'] as List?)?.cast<dynamic>();
      final icon = (w0 != null && w0.isNotEmpty)
          ? (w0.first as Map)['icon']?.toString() ?? '01d'
          : '01d';

      String weekdayLabel() {
        try {
          return _capitalizeTr(dayFmt.format(DateTime.parse('${dateStr}T12:00:00')));
        } catch (_) {
          return dateStr;
        }
      }

      final label = dateStr == today ? 'Bugün' : weekdayLabel();
      days.add(_ForecastDay(
        dayName: label,
        emoji: _owmEmoji(icon),
        minTemp: temps.reduce((a, b) => a < b ? a : b).round(),
        maxTemp: temps.reduce((a, b) => a > b ? a : b).round(),
      ));
    }
    return days;
  }

  Future<void> _fetchCurrent() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(_weatherUri(_lat, _lon)).timeout(const Duration(seconds: 18));
      if (res.statusCode == 401) {
        throw Exception('API anahtarı geçersiz.');
      }
      if (res.statusCode != 200 || res.body.isEmpty) {
        throw Exception('Hava durumu alınamadı. (${res.statusCode})');
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _weatherJson = map;
        _loading = false;
        _error = null;
      });
      unawaited(_prefetchForecastQuiet());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Günlük yüklendikten sonra haftalığı arka planda doldurur (sekme anında hazır olur).
  Future<void> _prefetchForecastQuiet() async {
    try {
      final res = await http.get(_forecastUri(_lat, _lon)).timeout(const Duration(seconds: 18));
      if (res.statusCode != 200 || res.body.isEmpty || !mounted) return;
      final root = jsonDecode(res.body) as Map<String, dynamic>;
      final days = _parseForecastDays(root);
      if (days.isEmpty || !mounted) return;
      setState(() {
        _forecastDays = days;
        // Kullanıcı önce "Haftalık"a geçtiyse _fetchForecast ile yarışır; sadece günleri
        // güncellemek yükleme bayrağını kapatmaz ve sonsuz spinner kalır.
        if (!_daily) {
          _loadingForecast = false;
          _error = null;
        }
      });
    } catch (_) {}
  }

  Future<void> _fetchForecast() async {
    setState(() {
      _loadingForecast = true;
      _error = null;
    });
    try {
      final res = await http.get(_forecastUri(_lat, _lon)).timeout(const Duration(seconds: 18));
      if (res.statusCode == 401) {
        throw Exception('API anahtarı geçersiz.');
      }
      if (res.statusCode != 200 || res.body.isEmpty) {
        throw Exception('Haftalık veri alınamadı. (${res.statusCode})');
      }
      final root = jsonDecode(res.body) as Map<String, dynamic>;
      final days = _parseForecastDays(root);
      if (!mounted) return;
      setState(() {
        _forecastDays = days;
        _loadingForecast = false;
        _error = days.isEmpty ? 'Haftalık özet oluşturulamadı.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingForecast = false;
      });
    }
  }

  String _capitalizeTr(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String? _buildCityLabelFromNominatim(Map<String, dynamic> first) {
    final address = first['address'];
    if (address is! Map) {
      final dn = first['display_name']?.toString();
      return dn?.split(',').first.trim();
    }
    final a = address.map((k, v) => MapEntry(k.toString(), v));
    String? pick(String k) {
      final v = a[k]?.toString().trim();
      return (v != null && v.isNotEmpty) ? v : null;
    }

    final district = pick('town') ??
        pick('city_district') ??
        pick('suburb') ??
        pick('village') ??
        pick('quarter');
    final city = pick('city') ?? pick('province') ?? pick('county') ?? pick('state');
    final fallback = first['display_name']?.toString() ?? '';

    if (district != null && city != null && district != city) return '$district/$city';
    if (district != null && city != null) return city;
    if (district != null) return district;
    if (city != null) return city;
    final part = fallback.split(',').first.trim();
    return part.isEmpty ? null : part;
  }

  Future<void> _searchCity() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    try {
      final enc = Uri.encodeComponent('$q, Türkiye');
      final uri = Uri.parse(
        '$_nominatimUrl?q=$enc&format=json&limit=1&countrycodes=tr&addressdetails=1',
      );
      final res = await http.get(
        uri,
        headers: {
          'User-Agent': _kNominatimUa,
          'Accept': 'application/json',
          'Accept-Language': 'tr',
        },
      ).timeout(const Duration(seconds: 18));
      if (res.statusCode != 200) return;
      final list = jsonDecode(res.body) as List<dynamic>;
      if (list.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$q" bulunamadı. İl veya ilçe adını kontrol edin.')),
          );
        }
        return;
      }
      final first = list.first as Map<String, dynamic>;
      final la = double.parse(first['lat'].toString());
      final lo = double.parse(first['lon'].toString());
      if (!mounted) return;
      setState(() {
        _lat = la;
        _lon = lo;
        _cityLabel = _buildCityLabelFromNominatim(first);
        _forecastDays = null;
        _weatherJson = null;
      });
      if (_daily) {
        await _fetchCurrent();
      } else {
        await _fetchForecast();
      }
      if (!mounted || !context.mounted) return;
      FocusScope.of(context).unfocus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arama başarısız')),
        );
      }
    }
  }

  void _onTabDaily() {
    final has = _weatherJson != null;
    setState(() {
      _daily = true;
      if (has) {
        _loading = false;
        _error = null;
      } else {
        _loading = true;
        _error = null;
      }
    });
    if (has) return;
    unawaited(_fetchCurrent());
  }

  void _onTabWeekly() {
    final has = _forecastDays != null && _forecastDays!.isNotEmpty;
    setState(() {
      _daily = false;
      if (has) {
        _loadingForecast = false;
        _error = null;
      } else {
        _loadingForecast = true;
        _error = null;
      }
    });
    if (has) return;
    unawaited(_fetchForecast());
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Material(
        color: const Color(0xFFF3F7F8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => unawaited(_searchCity()),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'İl veya ilçe ara',
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => unawaited(_searchCity()),
                      icon: const Icon(Icons.search_rounded, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _PremiumTabBar(
                daily: _daily,
                onDaily: _onTabDaily,
                onWeekly: _onTabWeekly,
              ),
            ),
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (_daily && _loading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    )
                  else if (!_daily && _loadingForecast)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    )
                  else if (_error != null)
                    _PremiumErrorCard(message: _error!)
                  else if (_daily && _weatherJson != null)
                    _buildDailyPremium(_weatherJson!)
                  else if (!_daily && _forecastDays != null && _forecastDays!.isNotEmpty)
                    _buildWeeklyPremium(_forecastDays!)
                  else if (!_daily && _forecastDays != null && _forecastDays!.isEmpty)
                    _PremiumErrorCard(message: _error ?? 'Haftalık veri bulunamadı.')
                  else
                    const _PremiumErrorCard(message: 'Veri yükleniyor…'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyPremium(Map<String, dynamic> j) {
    final main = j['main'] as Map<String, dynamic>?;
    final weather = (j['weather'] as List?)?.cast<dynamic>();
    final wind = j['wind'] as Map<String, dynamic>?;
    if (main == null || weather == null || weather.isEmpty) {
      return const _PremiumErrorCard(message: 'Veri eksik');
    }
    final w0 = weather.first as Map<String, dynamic>;
    final apiCity = j['name']?.toString() ?? 'Bilinmiyor';
    final title = _cityLabel ?? apiCity;
    final temp = (main['temp'] as num?)?.toDouble();
    final feels = (main['feels_like'] as num?)?.toDouble();
    final hum = (main['humidity'] as num?)?.toInt();
    final windMs = (wind?['speed'] as num?)?.toDouble() ?? 0;
    final windKmh = (windMs * 3.6).round();
    final desc = (w0['description']?.toString() ?? '').trim();
    final capDesc = desc.isEmpty ? '' : '${desc[0].toUpperCase()}${desc.substring(1)}';
    final icon = w0['icon']?.toString() ?? '01d';
    final emoji = _owmEmoji(icon);
    final timeStr = DateFormat('HH:mm').format(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.drawerHeaderGradientStart,
                AppColors.drawerHeaderGradientEnd,
                AppColors.purple500.withValues(alpha: 0.9),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: Color(0xFFB0E8EE), size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Text(
                    emoji,
                    style: const TextStyle(fontSize: 36),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                temp != null ? '${temp.round()}°' : '—',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w300,
                  height: 1.05,
                ),
              ),
              if (capDesc.isNotEmpty)
                Text(
                  capDesc,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Güncellendi $timeStr',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                icon: Icons.thermostat_rounded,
                label: 'Hissedilen',
                value: feels != null ? '${feels.round()}°' : '—',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                icon: Icons.water_drop_outlined,
                label: 'Nem',
                value: hum != null ? '%$hum' : '—',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                icon: Icons.air_rounded,
                label: 'Rüzgar',
                value: '$windKmh km/s',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeeklyPremium(List<_ForecastDay> days) {
    final title = _cityLabel ?? (_weatherJson?['name']?.toString() ?? 'Konum');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(Icons.calendar_month_rounded, color: AppColors.primary.withValues(alpha: 0.9)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        ...days.asMap().entries.map((e) {
          final i = e.key;
          final d = e.value;
          final isFirst = i == 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: AppColors.white,
              elevation: isFirst ? 4 : 2,
              shadowColor: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE0ECEF)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Text(d.emoji, style: const TextStyle(fontSize: 32)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.dayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Min ${d.minTemp}° · Max ${d.maxTemp}°',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.campaignBtnSecondary,
                              AppColors.suggestionBg,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${d.minTemp}° / ${d.maxTemp}°',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _PremiumTabBar extends StatelessWidget {
  const _PremiumTabBar({
    required this.daily,
    required this.onDaily,
    required this.onWeekly,
  });

  final bool daily;
  final VoidCallback onDaily;
  final VoidCallback onWeekly;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegButton(label: 'Günlük', selected: daily, onTap: onDaily),
          ),
          Expanded(
            child: _SegButton(label: 'Haftalık', selected: !daily, onTap: onWeekly),
          ),
        ],
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  const _SegButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                colors: [
                  AppColors.drawerHeaderGradientStart,
                  AppColors.drawerHeaderGradientEnd,
                ],
              )
            : null,
        color: selected ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.campaignSummaryMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0ECEF)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumErrorCard extends StatelessWidget {
  const _PremiumErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.grey.shade800, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastDay {
  _ForecastDay({
    required this.dayName,
    required this.emoji,
    required this.minTemp,
    required this.maxTemp,
  });

  final String dayName;
  final String emoji;
  final int minTemp;
  final int maxTemp;
}
