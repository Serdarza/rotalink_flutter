import 'package:flutter/material.dart';

import '../data/firebase_rota_repository.dart';
import '../theme/app_colors.dart';
import '../theme/system_ui.dart';
import '../utils/il_ilce.dart';
import '../utils/main_map_search.dart';
import '../widgets/custom_search_bar.dart';

/// Harita aramasına açılan sade başlangıç ekranı.
///
/// Sonuç üretmez; seçimi mevcut harita/arama motoruna aktarır.
class SearchHubScreen extends StatefulWidget {
  const SearchHubScreen({
    super.key,
    required this.repository,
    required this.onBack,
    required this.onQuery,
    required this.onCategory,
  });

  final FirebaseRotaRepository repository;
  final VoidCallback onBack;
  final ValueChanged<String> onQuery;
  final ValueChanged<int> onCategory;

  @override
  State<SearchHubScreen> createState() => _SearchHubScreenState();
}

class _SearchHubScreenState extends State<SearchHubScreen> {
  final _controller = TextEditingController();
  late final Stream<RotaDataState> _dataStream;

  @override
  void initState() {
    super.initState();
    _dataStream = widget.repository.watchRoot();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? value]) {
    final query = (value ?? _controller.text).trim();
    if (query.isEmpty) return;
    widget.onQuery(query);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: RotalinkSystemUi.forBrightness(Theme.of(context).brightness),
      child: Material(
        color: AppColors.canvasOf(context),
        child: SafeArea(
          bottom: false,
          child: StreamBuilder<RotaDataState>(
            stream: _dataStream,
            initialData: widget.repository.currentState,
            builder: (context, snapshot) {
              final data = snapshot.data;
              final popular = _popularCities(data);
              final iller = data == null
                  ? const <String>[]
                  : MainMapSearch.distinctSortedIller(
                      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
                      misafirhaneler: data.misafirhaneler,
                    );
              return CustomScrollView(
                clipBehavior: Clip.none,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: widget.onBack,
                            icon: const Icon(Icons.arrow_back_rounded),
                            tooltip: 'Geri',
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Ara',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => widget.onCategory(0),
                            icon: const Icon(Icons.tune_rounded),
                            tooltip: 'Filtreler',
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    sliver: SliverList.list(
                      children: [
                        CustomSearchBar(
                          controller: _controller,
                          ilOptionsSorted: iller,
                          onSubmitted: _submit,
                          ignoreKeyboardInset: true,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Hızlı erişim',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        _CategoryRow(onSelected: widget.onCategory),
                        const SizedBox(height: 28),
                        Text(
                          'Popüler şehirler',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Şehirlerdeki konaklama ve gezi seçeneklerini keşfedin.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        ...popular.map(
                            (city) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _CityCard(
                                city: city.name,
                                count: city.count,
                                onTap: () => widget.onQuery(city.name),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        _NearbyCard(onTap: () => widget.onCategory(0)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static const _popularCityNames = [
    'Ankara',
    'İstanbul',
    'İzmir',
    'Antalya',
    'Trabzon',
  ];

  List<_CitySummary> _popularCities(RotaDataState? data) {
    final facilities = data?.misafirhaneler ?? const [];
    return [
      for (final name in _popularCityNames)
        _CitySummary(
          name,
          facilities.where((m) => IlIlce.sameIl(m.il, name)).length,
        ),
    ];
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.onSelected});

  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Konaklama', Icons.bed_outlined),
      ('Gezi', Icons.landscape_outlined),
      ('Yemek', Icons.restaurant_outlined),
      ('Tesisler', Icons.apartment_outlined),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: Material(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => onSelected(i),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 76,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.borderOf(context)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(items[i].$2, color: AppColors.primary),
                      const SizedBox(height: 6),
                      Text(
                        items[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (i != items.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _CityCard extends StatelessWidget {
  const _CityCard({
    required this.city,
    required this.count,
    required this.onTap,
  });

  final String city;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 82,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderOf(context)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.location_city_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(city, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      '$count konaklama kaydı',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NearbyCard extends StatelessWidget {
  const _NearbyCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.near_me_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Yakınımda ara',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Konumunuza göre sonuçları görün',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CitySummary {
  const _CitySummary(this.name, this.count);

  final String name;
  final int count;
}
