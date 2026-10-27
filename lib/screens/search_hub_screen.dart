import 'package:flutter/material.dart';

import '../data/firebase_rota_repository.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';
import '../theme/system_ui.dart';
import '../utils/il_ilce.dart';
import '../utils/main_map_search.dart';
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
        color: AraUi.pageOf(context),
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Başlık + arama: tonlu yüzey, beyaz arama kutusu öne çıkar.
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AraUi.chromeFillOf(context),
                    border: Border(
                      bottom: BorderSide(
                        color: AraUi.secondaryActionBorderOf(context),
                      ),
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
                              _HeaderIconButton(
                                icon: Icons.tune_rounded,
                                tooltip: 'Filtreler',
                                onPressed: () => widget.onCategory(0),
                              ),
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
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                    children: [
                      const _SectionTitle('Hızlı erişim'),
                      const SizedBox(height: 12),
                      _CategoryRow(onSelected: widget.onCategory),
                      const SizedBox(height: 26),
                      const _SectionTitle(
                        'Popüler şehirler',
                        subtitle:
                            'Şehirlerdeki konaklama ve gezi seçeneklerini keşfedin.',
                      ),
                      const SizedBox(height: 12),
                      for (final city in popular)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CityCard(
                            city: city.name,
                            count: city.count,
                            onTap: () => widget.onQuery(city.name),
                          ),
                        ),
                      const SizedBox(height: 6),
                      _NearbyCard(onTap: () => widget.onCategory(0)),
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

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AraUi.secondaryActionBorderOf(context)),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.textStrongOf(context),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: TextStyle(color: AraUi.mutedTextOf(context), fontSize: 12.5),
          ),
        ],
      ],
    );
  }
}

/// Beyaz, ince çerçeveli, yuvarlak köşeli kart yüzeyi.
class _HubCard extends StatelessWidget {
  const _HubCard({required this.onTap, required this.child, this.color});

  final VoidCallback onTap;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? AppColors.surfaceOf(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: color == null
              ? AraUi.cardBorderOf(context)
              : AraUi.primaryActionBorder,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primary.withValues(alpha: 0.06),
        highlightColor: AppColors.primary.withValues(alpha: 0.03),
        child: child,
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.onSelected});

  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Konaklama', Icons.bed_outlined, AraUi.stay),
      ('Gezi', Icons.landscape_outlined, AraUi.gezi),
      ('Yemek', Icons.restaurant_outlined, AraUi.yemek),
      ('Tesisler', Icons.apartment_outlined, AraUi.tesis),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: _HubCard(
              onTap: () => onSelected(i),
              child: SizedBox(
                height: 92,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: items[i].$3.bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(items[i].$2, color: items[i].$3.fg, size: 22),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      items[i].$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AraUi.inactiveForegroundOf(context),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
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
    return _HubCard(
      onTap: onTap,
      child: Container(
        height: 74,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AraUi.stay.bg,
                borderRadius: BorderRadius.circular(13),
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
                  Text(
                    city,
                    style: TextStyle(
                      color: AppColors.textStrongOf(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$count konaklama kaydı',
                    style: TextStyle(
                      color: AraUi.mutedTextOf(context),
                      fontSize: 12.5,
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
    );
  }
}

class _NearbyCard extends StatelessWidget {
  const _NearbyCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HubCard(
      onTap: onTap,
      color: AraUi.primaryActionFill,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.near_me_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Yakınımda ara',
                    style: TextStyle(
                      color: AppColors.textStrongOf(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Konumunuza göre sonuçları görün',
                    style: TextStyle(
                      color: AraUi.mutedTextOf(context),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: AppColors.primary),
          ],
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
