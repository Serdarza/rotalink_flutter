import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/firebase_rota_repository.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';
import '../theme/system_ui.dart';
import '../utils/main_map_search.dart';
import '../utils/search_normalize.dart';
import '../widgets/custom_search_bar.dart';

/// Harita aramasına açılan sade başlangıç ekranı.
///
/// Sonuç üretmez; seçimi mevcut harita/arama motoruna aktarır.
///
/// Görsel düzen (Ara listesiyle aynı dil): üstte tonlu başlık + arama bölgesi,
/// altta açık gri zemin üzerinde beyaz, çerçeveli kartlar.
class SearchHubScreen extends StatefulWidget {
  const SearchHubScreen({
    super.key,
    required this.repository,
    required this.onBack,
    required this.onQuery,
    this.onCitySelected,
    required this.onNearby,
  });

  final FirebaseRotaRepository repository;
  final VoidCallback onBack;
  final ValueChanged<String> onQuery;
  final ValueChanged<String>? onCitySelected;
  final VoidCallback onNearby;

  @override
  State<SearchHubScreen> createState() => _SearchHubScreenState();
}

class _SearchHubScreenState extends State<SearchHubScreen> {
  static const _quickKey = 'ara_quick_cities_v1';
  static const _recentKey = 'ara_recent_cities_v1';

  final _controller = TextEditingController();
  late final Stream<RotaDataState> _dataStream;
  List<String> _quickPlates = List<String>.of(_defaultQuickPlates);
  List<String> _recentPlates = const [];

  @override
  void initState() {
    super.initState();
    _dataStream = widget.repository.watchRoot();
    unawaited(_loadCityPrefs());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_CityChoice> get _quickCities => [
    for (final plate in _quickPlates) ?_cityByPlate(plate),
  ];

  List<_CityChoice> get _recentCities => [
    for (final plate in _recentPlates) ?_cityByPlate(plate),
  ];

  Future<void> _loadCityPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final quick = _knownPlates(prefs.getStringList(_quickKey), 9);
      final recent = _knownPlates(prefs.getStringList(_recentKey), 3);
      if (!mounted) return;
      setState(() {
        if (quick.length == 9) _quickPlates = quick;
        _recentPlates = recent;
      });
    } catch (_) {}
  }

  Future<void> _writePlates(String key, List<String> plates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, plates);
    } catch (_) {}
  }

  void _remember(_CityChoice city) {
    final next = <String>[
      city.plate,
      ..._recentPlates.where((plate) => plate != city.plate),
    ].take(3).toList(growable: false);
    if (!mounted) return;
    setState(() => _recentPlates = next);
    unawaited(_writePlates(_recentKey, next));
  }

  void _removeRecent(_CityChoice city) {
    final next = [
      for (final plate in _recentPlates)
        if (plate != city.plate) plate,
    ];
    setState(() => _recentPlates = next);
    unawaited(_writePlates(_recentKey, next));
  }

  void _clearRecent() {
    setState(() => _recentPlates = const []);
    unawaited(_writePlates(_recentKey, const []));
  }

  void _submit([String? value]) {
    final query = (value ?? _controller.text).trim();
    if (query.isEmpty) return;
    final city = _matchCity(query);
    if (city != null) _remember(city);
    widget.onQuery(city?.query ?? query);
  }

  void _selectCity(_CityChoice city) {
    _controller.clear();
    _remember(city);
    final onCitySelected = widget.onCitySelected;
    if (onCitySelected != null) {
      onCitySelected(city.query);
    } else {
      widget.onQuery(city.query);
    }
  }

  Future<void> _editQuickList() async {
    final next = await showModalBottomSheet<List<String>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickListEditor(initialPlates: _quickPlates),
    );
    if (!mounted || next == null || next.length != 9) return;
    setState(() => _quickPlates = next);
    unawaited(_writePlates(_quickKey, next));
  }

  _CityChoice? _matchCity(String query) {
    final plateNumber = int.tryParse(query);
    if (plateNumber != null && plateNumber >= 1 && plateNumber <= 81) {
      return _cityByPlate(plateNumber.toString().padLeft(2, '0'));
    }
    final key = normalizeForSearch(query);
    if (key.isEmpty) return null;
    for (final city in _allCities) {
      if (normalizeForSearch(city.name) == key ||
          normalizeForSearch(city.query) == key) {
        return city;
      }
      for (final alias in city.aliases) {
        if (normalizeForSearch(alias) == key) return city;
      }
    }
    return null;
  }

  Future<void> _showCityPicker() async {
    final city = await showModalBottomSheet<_CityChoice>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CityPickerSheet(),
    );
    if (!mounted || city == null) return;
    _selectCity(city);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: RotalinkSystemUi.forBrightness(Theme.of(context).brightness),
      child: Material(
        color: AraUi.pageOf(context),
        child: StreamBuilder<RotaDataState>(
          stream: _dataStream,
          initialData: widget.repository.currentState,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final iller = data == null
                ? const <String>[]
                : MainMapSearch.distinctSortedIller(
                    aramaIcinTumTesisler: data.aramaIcinTumTesisler,
                    misafirhaneler: data.misafirhaneler,
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Başlık + arama: tonlu yüzey, beyaz arama kutusu öne çıkar.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: AppColors.isDark(context)
                          ? const [Color(0xFF12383F), Color(0xFF10181A)]
                          : const [
                              Color(0xFF7ED0DA),
                              Color(0xFFD5F1F4),
                              Color(0xFFEDF2F3),
                            ],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: widget.onBack,
                                icon: Icon(
                                  Icons.arrow_back_rounded,
                                  color: AraUi.inactiveForegroundOf(context),
                                ),
                                tooltip: 'Geri',
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Ara',
                                style: TextStyle(
                                  color: AppColors.textStrongOf(context),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Spacer(),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: CustomSearchBar(
                              controller: _controller,
                              ilOptionsSorted: iller,
                              onSubmitted: _submit,
                              onClearPressed: widget.onBack,
                              ignoreKeyboardInset: true,
                              restrained: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      const _DiscoverHero(),
                      if (_recentCities.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _RecentHeader(onClear: _clearRecent),
                        const SizedBox(height: 8),
                        _RecentStrip(
                          cities: _recentCities,
                          onOpen: _selectCity,
                          onRemove: _removeRecent,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _QuickHeader(onEdit: _editQuickList),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final spacing = constraints.maxWidth < 340
                              ? 8.0
                              : 10.0;
                          final cities = _quickCities;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: cities.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: spacing,
                                  mainAxisSpacing: spacing,
                                  mainAxisExtent: 148,
                                ),
                            itemBuilder: (context, index) {
                              final city = cities[index];
                              return _PhotoCityCard(
                                city: city,
                                onTap: () => _selectCity(city),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      _AllCitiesCard(onTap: _showCityPicker),
                      const SizedBox(height: 11),
                      _NearbyCard(onTap: widget.onNearby),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

const _defaultQuickPlates = <String>[
  '34',
  '06',
  '35',
  '07',
  '38',
  '16',
  '61',
  '27',
  '25',
];

const _heroAsset = 'assets/images/cities/hero.webp';

String _cityCoverAsset(String plate) =>
    'assets/images/cities/${plate == 'KKTC' ? 'kktc' : plate}.webp';

_CityChoice? _cityByPlate(String plate) {
  for (final city in _allCities) {
    if (city.plate == plate) return city;
  }
  return null;
}

List<String> _knownPlates(List<String>? raw, int max) {
  if (raw == null) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final plate in raw) {
    if (!_knownPlate(plate) || !seen.add(plate)) continue;
    out.add(plate);
    if (out.length == max) break;
  }
  return out;
}

bool _knownPlate(String plate) => _cityByPlate(plate) != null;

const _allCities = <_CityChoice>[
  _CityChoice('01', 'Adana', 'Adana'),
  _CityChoice('02', 'Adıyaman', 'Adıyaman'),
  _CityChoice('03', 'Afyonkarahisar', 'Afyonkarahisar'),
  _CityChoice('04', 'Ağrı', 'Ağrı'),
  _CityChoice('05', 'Amasya', 'Amasya'),
  _CityChoice('06', 'Ankara', 'Ankara'),
  _CityChoice('07', 'Antalya', 'Antalya'),
  _CityChoice('08', 'Artvin', 'Artvin'),
  _CityChoice('09', 'Aydın', 'Aydın'),
  _CityChoice('10', 'Balıkesir', 'Balıkesir'),
  _CityChoice('11', 'Bilecik', 'Bilecik'),
  _CityChoice('12', 'Bingöl', 'Bingöl'),
  _CityChoice('13', 'Bitlis', 'Bitlis'),
  _CityChoice('14', 'Bolu', 'Bolu'),
  _CityChoice('15', 'Burdur', 'Burdur'),
  _CityChoice('16', 'Bursa', 'Bursa'),
  _CityChoice('17', 'Çanakkale', 'Çanakkale'),
  _CityChoice('18', 'Çankırı', 'Çankırı'),
  _CityChoice('19', 'Çorum', 'Çorum'),
  _CityChoice('20', 'Denizli', 'Denizli'),
  _CityChoice('21', 'Diyarbakır', 'Diyarbakır'),
  _CityChoice('22', 'Edirne', 'Edirne'),
  _CityChoice('23', 'Elazığ', 'Elazığ'),
  _CityChoice('24', 'Erzincan', 'Erzincan'),
  _CityChoice('25', 'Erzurum', 'Erzurum'),
  _CityChoice('26', 'Eskişehir', 'Eskişehir'),
  _CityChoice('27', 'Gaziantep', 'Gaziantep'),
  _CityChoice('28', 'Giresun', 'Giresun'),
  _CityChoice('29', 'Gümüşhane', 'Gümüşhane'),
  _CityChoice('30', 'Hakkâri', 'Hakkâri'),
  _CityChoice('31', 'Hatay', 'Hatay'),
  _CityChoice('32', 'Isparta', 'Isparta'),
  _CityChoice('33', 'Mersin', 'Mersin'),
  _CityChoice('34', 'İstanbul', 'İstanbul'),
  _CityChoice('35', 'İzmir', 'İzmir'),
  _CityChoice('36', 'Kars', 'Kars'),
  _CityChoice('37', 'Kastamonu', 'Kastamonu'),
  _CityChoice('38', 'Kayseri', 'Kayseri'),
  _CityChoice('39', 'Kırklareli', 'Kırklareli'),
  _CityChoice('40', 'Kırşehir', 'Kırşehir'),
  _CityChoice('41', 'Kocaeli', 'Kocaeli'),
  _CityChoice('42', 'Konya', 'Konya'),
  _CityChoice('43', 'Kütahya', 'Kütahya'),
  _CityChoice('44', 'Malatya', 'Malatya'),
  _CityChoice('45', 'Manisa', 'Manisa'),
  _CityChoice('46', 'Kahramanmaraş', 'Kahramanmaraş'),
  _CityChoice('47', 'Mardin', 'Mardin'),
  _CityChoice('48', 'Muğla', 'Muğla'),
  _CityChoice('49', 'Muş', 'Muş'),
  _CityChoice('50', 'Nevşehir', 'Nevşehir'),
  _CityChoice('51', 'Niğde', 'Niğde'),
  _CityChoice('52', 'Ordu', 'Ordu'),
  _CityChoice('53', 'Rize', 'Rize'),
  _CityChoice('54', 'Sakarya', 'Sakarya'),
  _CityChoice('55', 'Samsun', 'Samsun'),
  _CityChoice('56', 'Siirt', 'Siirt'),
  _CityChoice('57', 'Sinop', 'Sinop'),
  _CityChoice('58', 'Sivas', 'Sivas'),
  _CityChoice('59', 'Tekirdağ', 'Tekirdağ'),
  _CityChoice('60', 'Tokat', 'Tokat'),
  _CityChoice('61', 'Trabzon', 'Trabzon'),
  _CityChoice('62', 'Tunceli', 'Tunceli'),
  _CityChoice('63', 'Şanlıurfa', 'Şanlıurfa'),
  _CityChoice('64', 'Uşak', 'Uşak'),
  _CityChoice('65', 'Van', 'Van'),
  _CityChoice('66', 'Yozgat', 'Yozgat'),
  _CityChoice('67', 'Zonguldak', 'Zonguldak'),
  _CityChoice('68', 'Aksaray', 'Aksaray'),
  _CityChoice('69', 'Bayburt', 'Bayburt'),
  _CityChoice('70', 'Karaman', 'Karaman'),
  _CityChoice('71', 'Kırıkkale', 'Kırıkkale'),
  _CityChoice('72', 'Batman', 'Batman'),
  _CityChoice('73', 'Şırnak', 'Şırnak'),
  _CityChoice('74', 'Bartın', 'Bartın'),
  _CityChoice('75', 'Ardahan', 'Ardahan'),
  _CityChoice('76', 'Iğdır', 'Iğdır'),
  _CityChoice('77', 'Yalova', 'Yalova'),
  _CityChoice('78', 'Karabük', 'Karabük'),
  _CityChoice('79', 'Kilis', 'Kilis'),
  _CityChoice('80', 'Osmaniye', 'Osmaniye'),
  _CityChoice('81', 'Düzce', 'Düzce'),
  _CityChoice('KKTC', 'Kuzey Kıbrıs', 'Kıbrıs', aliases: ['KKTC', 'Kıbrıs']),
];

class _CityChoice {
  const _CityChoice(
    this.plate,
    this.name,
    this.query, {
    this.aliases = const [],
  });

  final String plate;
  final String name;
  final String query;
  final List<String> aliases;
}

class _PhotoCityCard extends StatelessWidget {
  const _PhotoCityCard({
    required this.city,
    required this.onTap,
    this.height = 148,
  });

  final _CityChoice city;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${city.plate} ${city.name}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: const Color(0xFF0C5C66),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    _cityCoverAsset(city.plate),
                    fit: BoxFit.cover,
                    cacheWidth: 480,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00000000),
                          Color(0x00000000),
                          Color(0xE6102028),
                        ],
                        stops: [0.42, 0.58, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF128F6A),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            city.plate,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          city.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoverHero extends StatelessWidget {
  const _DiscoverHero();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A6E78).withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 136,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFF0E7F8C), Color(0xFF1498A8)],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: 168,
                child: Image.asset(
                  _heroAsset,
                  fit: BoxFit.cover,
                  alignment: const Alignment(-0.15, -0.05),
                  cacheWidth: 640,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const Positioned(
                top: 0,
                right: 72,
                bottom: 0,
                width: 120,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFF128EA0), Color(0x00128EA0)],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 112, 12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 210,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Şehrini Seç, Keşfet!',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Konaklama, gezi, yeme-içme ve daha fazlası tek dokunuşla!',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Positioned(
                right: 78,
                bottom: 18,
                child: Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentHeader extends StatelessWidget {
  const _RecentHeader({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.access_time_rounded,
          size: 18,
          color: AppColors.textStrongOf(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Son Baktıkların',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textStrongOf(context),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextButton(
          onPressed: onClear,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text('Tümünü Temizle'),
        ),
      ],
    );
  }
}

class _RecentStrip extends StatelessWidget {
  const _RecentStrip({
    required this.cities,
    required this.onOpen,
    required this.onRemove,
  });

  final List<_CityChoice> cities;
  final ValueChanged<_CityChoice> onOpen;
  final ValueChanged<_CityChoice> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cities.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final city = cities[index];
          return _RecentCityChip(
            city: city,
            onOpen: () => onOpen(city),
            onRemove: () => onRemove(city),
          );
        },
      ),
    );
  }
}

class _RecentCityChip extends StatelessWidget {
  const _RecentCityChip({
    required this.city,
    required this.onOpen,
    required this.onRemove,
  });

  final _CityChoice city;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context),
      elevation: 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: Image.asset(
                  _cityCoverAsset(city.plate),
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  cacheWidth: 160,
                  errorBuilder: (_, _, _) => Container(
                    width: 44,
                    height: 44,
                    color: AppColors.primarySoftOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    city.plate,
                    style: TextStyle(
                      color: AppColors.textStrongOf(context),
                      fontSize: 14,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    city.name,
                    style: TextStyle(
                      color: AraUi.mutedTextOf(context),
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Kaldır',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: onRemove,
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AraUi.subtleTextOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickHeader extends StatelessWidget {
  const _QuickHeader({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.bolt_rounded, size: 18, color: Color(0xFF3B73F0)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Hızlı Şehir Seçimi',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textStrongOf(context),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onEdit,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          icon: const Icon(Icons.settings_rounded, size: 16),
          label: const Text('Listemi Düzenle'),
        ),
      ],
    );
  }
}


class _NearbyCard extends StatelessWidget {
  const _NearbyCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.near_me_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Yakınımda ara',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Yakın misafirhaneleri keşfet',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllCitiesCard extends StatelessWidget {
  const _AllCitiesCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primarySoftOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(Icons.map_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tüm Şehirleri Gör',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textStrongOf(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '81 il ve Kuzey Kıbrıs',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AraUi.mutedTextOf(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AraUi.subtleTextOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet();

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = normalizeForSearch(_query.trim());
    final cities = _allCities
        .where((city) {
          if (normalizedQuery.isEmpty) return true;
          final searchable = normalizeForSearch(
            '${city.plate} ${city.name} ${city.query} ${city.aliases.join(' ')}',
          );
          return searchable.contains(normalizedQuery);
        })
        .toList(growable: false);

    return DraggableScrollableSheet(
      initialChildSize: 0.84,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Material(
        color: AppColors.surfaceOf(context),
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AraUi.subtleTextOf(context).withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 13, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Şehir Seç',
                        style: TextStyle(
                          color: AppColors.textStrongOf(context),
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: AraUi.inactiveForegroundOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Şehir adı veya plaka ara...',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.primary,
                    ),
                    filled: true,
                    fillColor: AppColors.fieldFillOf(context),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(
                        color: AraUi.cardBorderOf(context),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(
                        color: AraUi.cardBorderOf(context),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: cities.isEmpty
                    ? Center(
                        child: Text(
                          'Şehir bulunamadı',
                          style: TextStyle(color: AraUi.mutedTextOf(context)),
                        ),
                      )
                    : GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              mainAxisExtent: 132,
                            ),
                        itemCount: cities.length,
                        itemBuilder: (context, index) => _PhotoCityCard(
                          city: cities[index],
                          height: 132,
                          onTap: () => Navigator.pop(context, cities[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickListEditor extends StatefulWidget {
  const _QuickListEditor({required this.initialPlates});

  final List<String> initialPlates;

  @override
  State<_QuickListEditor> createState() => _QuickListEditorState();
}

class _QuickListEditorState extends State<_QuickListEditor> {
  late final List<String> _plates = List<String>.of(widget.initialPlates);

  Future<void> _replace(int index) async {
    final city = await showModalBottomSheet<_CityChoice>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CityPickerSheet(),
    );
    if (!mounted || city == null) return;
    setState(() {
      final existing = _plates.indexOf(city.plate);
      if (existing == index) return;
      if (existing >= 0) {
        _plates[existing] = _plates[index];
      }
      _plates[index] = city.plate;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final plate = _plates.removeAt(oldIndex);
      _plates.insert(newIndex, plate);
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.88;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: AppColors.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: height,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AraUi.subtleTextOf(context).withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Listemi Düzenle',
                          style: TextStyle(
                            color: AppColors.textStrongOf(context),
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close_rounded,
                          color: AraUi.inactiveForegroundOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '9 şehir seç. Sırayı değiştirmek için tutup sürükle.',
                      style: TextStyle(
                        color: AraUi.mutedTextOf(context),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: _plates.length,
                    onReorder: _reorder,
                    buildDefaultDragHandles: false,
                    itemBuilder: (context, index) {
                      final city = _cityByPlate(_plates[index]);
                      return Material(
                        key: ValueKey(_plates[index]),
                        color: Colors.transparent,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: AraUi.subtleTextOf(context),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ClipOval(
                                child: city == null
                                    ? const SizedBox(width: 40, height: 40)
                                    : Image.asset(
                                        _cityCoverAsset(city.plate),
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        cacheWidth: 120,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 40,
                                          height: 40,
                                          color: AppColors.primarySoftOf(
                                            context,
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  city == null
                                      ? _plates[index]
                                      : '${city.plate}  ${city.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textStrongOf(context),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _replace(index),
                                child: const Text('Değiştir'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() {
                          _plates
                            ..clear()
                            ..addAll(_defaultQuickPlates);
                        }),
                        child: const Text('Varsayılan'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _plates.toSet().length == 9
                            ? () => Navigator.pop(
                                context,
                                List<String>.of(_plates),
                              )
                            : null,
                        child: const Text('Kaydet'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

