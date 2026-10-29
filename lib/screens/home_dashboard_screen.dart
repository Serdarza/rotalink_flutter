import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../billing/pro_service.dart';
import '../data/firebase_rota_repository.dart';
import '../data/hediyelik_repository.dart';
import '../models/misafirhane.dart';
import '../data/kamp_repository.dart';
import '../data/recent_search_store.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';
import '../theme/system_ui.dart';
import '../utils/main_map_search.dart';
import '../widgets/custom_search_bar.dart';
import '../widgets/rotalink_app_drawer.dart';
import '../widgets/rotalink_app_header.dart';
import '../widgets/map_weather_chip.dart';
import '../widgets/nationwide_price_sheet.dart';
import '../widgets/weather_bottom_sheet.dart';
import '../widgets/home_photo_discover_card.dart';
import '../widgets/winter_discover_home_card.dart';

/// Haritayı özellik olarak koruyan, uygulamanın yeni ana giriş ekranı.
///
/// Bu ekran yalnızca sunum ve yönlendirme yapar. Tüm veri işlemleri mevcut
/// repository ve harita ekranındaki akışlarda kalır.
class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({
    super.key,
    required this.repository,
    required this.onOpenMap,
    required this.onOpenSearch,
    required this.onSubmitQuery,
    required this.onOpenCategory,
    required this.onOpenFavorites,
    required this.onOpenRoutePlan,
    required this.onOpenDiscover,
    required this.onOpenNamedRoute,
    required this.onOpenKami,
  });

  final FirebaseRotaRepository repository;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenSearch;
  final ValueChanged<String> onSubmitQuery;
  final ValueChanged<int> onOpenCategory;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenRoutePlan;
  final VoidCallback onOpenDiscover;
  final ValueChanged<String> onOpenNamedRoute;
  final VoidCallback onOpenKami;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();
  late final Stream<RotaDataState> _dataStream;

  @override
  void initState() {
    super.initState();
    _dataStream = widget.repository.watchRoot();
    unawaited(RecentSearchStore.instance.ensureLoaded());
    unawaited(RotalinkSystemUi.applyEdgeToEdge());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(HediyelikRepository.instance.ensureLoaded());
      unawaited(KampRepository.instance.ensureLoaded());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      widget.onOpenSearch();
      return;
    }
    widget.onSubmitQuery(query);
  }

  Future<void> _openWeather() => showWeatherBottomSheet(context);

  Future<void> _openPriceBrowse(RotaDataState? data) {
    final facilities = data == null
        ? const <Misafirhane>[]
        : (data.aramaIcinTumTesisler.isNotEmpty
              ? data.aramaIcinTumTesisler
              : data.misafirhaneler);
    return showNationwidePriceSheet(
      context,
      facilities: facilities,
      onOpenPro: () => widget.onOpenNamedRoute(RotalinkShellRoutes.pro),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: RotalinkSystemUi.forBrightness(Theme.of(context).brightness),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AraUi.pageOf(context),
        drawer: RotalinkAppDrawer(
          onOpenRoute: widget.onOpenNamedRoute,
          onOpenWeather: () => unawaited(_openWeather()),
        ),
        body: SafeArea(
          bottom: false,
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
              return CustomScrollView(
                clipBehavior: Clip.none,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(context, data)),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
                    sliver: SliverList.list(
                      children: [
                        _WelcomeHeader(
                          controller: _searchController,
                          ilOptionsSorted: iller,
                          onSubmitted: _submitSearch,
                        ),
                        const SizedBox(height: 16),
                        const _SectionTitle(title: 'Ne arıyorsunuz?'),
                        const SizedBox(height: 12),
                        _CategoryGrid(
                          data: data,
                          onSelected: widget.onOpenCategory,
                        ),
                        const SizedBox(height: 16),
                        _MapDiscoverCard(onTap: widget.onOpenMap),
                        const SizedBox(height: 12),
                        WinterDiscoverHomeCard(
                          onTap: () => widget.onOpenNamedRoute(
                            RotalinkShellRoutes.winterDiscover,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _SectionTitle(title: 'Hızlı işlemler'),
                        const SizedBox(height: 12),
                        _QuickActions(
                          onRoute: () => widget.onOpenNamedRoute(
                            RotalinkShellRoutes.nearby,
                          ),
                          onPrice: () => unawaited(_openPriceBrowse(data)),
                          onWeather: () => unawaited(_openWeather()),
                          onHolidays: () => widget.onOpenNamedRoute(
                            RotalinkShellRoutes.holidays,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _RecentSearches(onSelect: widget.onSubmitQuery),
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

  Widget _buildHeader(BuildContext context, RotaDataState? data) {
    return RotalinkAppHeader(
      onMenu: () => _scaffoldKey.currentState?.openDrawer(),
      trailing: MapWeatherChip(compact: true, rotaData: data),
    );
  }
}

String _formatTurkishDate(DateTime date) {
  const months = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];
  const weekdays = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  final day = date.day.toString().padLeft(2, '0');
  return '$day ${months[date.month - 1]} ${weekdays[date.weekday - 1]}';
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({
    required this.controller,
    required this.ilOptionsSorted,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final List<String> ilOptionsSorted;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _formatTurkishDate(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dateLabel,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Türkiye’yi birlikte keşfedelim',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        CustomSearchBar(
          controller: controller,
          ilOptionsSorted: ilOptionsSorted,
          onSubmitted: onSubmitted,
          ignoreKeyboardInset: true,
          emphasized: true,
          compactHome: true,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ),
      ],
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.data, required this.onSelected});

  final RotaDataState? data;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, List<HediyelikItem>>>(
      valueListenable: HediyelikRepository.instance.byIl,
      builder: (context, hediyelikByIl, _) {
        return ValueListenableBuilder<List<KampAlani>>(
          valueListenable: KampRepository.instance.items,
          builder: (context, kampAlanlari, _) {
            return _CategoryGridBody(
              data: data,
              onSelected: onSelected,
              hediyelikCount: HediyelikRepository.instance
                  .forIller(const {})
                  .length,
              kampCount: kampAlanlari.length,
            );
          },
        );
      },
    );
  }
}

class _CategoryGridBody extends StatelessWidget {
  const _CategoryGridBody({
    required this.data,
    required this.onSelected,
    required this.hediyelikCount,
    required this.kampCount,
  });

  final RotaDataState? data;
  final ValueChanged<int> onSelected;
  final int hediyelikCount;
  final int kampCount;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final konaklamaCount = d == null
        ? null
        : MainMapSearch.tesisKaynagiArama(
            aramaIcinTumTesisler: d.aramaIcinTumTesisler,
            misafirhaneler: d.misafirhaneler,
          ).length;
    final items = [
      (
        'Konaklama',
        'Kamu Misafirhaneleri',
        Icons.bed_rounded,
        konaklamaCount,
        const Color(0xFF007B8F),
        'assets/images/home_categories/konaklama.webp',
      ),
      (
        'Gezi',
        'Gezilecek yerler',
        Icons.landscape_rounded,
        data?.gezi.length,
        const Color(0xFF2E7D32),
        'assets/images/home_categories/gezi.webp',
      ),
      (
        'Yemek',
        'Yerel lezzetler',
        Icons.restaurant_rounded,
        data?.yemek.length,
        const Color(0xFFE65100),
        'assets/images/home_categories/yemek.webp',
      ),
      (
        'Sosyal tesisler',
        'Yakınındaki tesisler',
        Icons.apartment_rounded,
        data?.sosyal.length,
        const Color(0xFF5E35B1),
        'assets/images/home_categories/sosyal.webp',
      ),
      (
        'Hediyelik',
        'Yöresel ürünler',
        Icons.card_giftcard_rounded,
        hediyelikCount == 0 ? null : hediyelikCount,
        const Color(0xFFAD1457),
        'assets/images/home_categories/hediyelik.webp',
      ),
      (
        'Kamp yerleri',
        'Çadır ve karavan',
        Icons.park_rounded,
        kampCount == 0 ? null : kampCount,
        const Color(0xFF558B2F),
        'assets/images/home_categories/kamp.webp',
      ),
    ];

    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent:
            128 +
            (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 28) * 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final categoryIcon = Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: item.$5,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Icon(item.$3, color: Colors.white, size: 18),
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            final stackedIcon =
                constraints.maxWidth < 155 ||
                MediaQuery.textScalerOf(context).scale(14) > 17.5;
            return Material(
              color: item.$5,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              elevation: 0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    item.$6,
                    fit: BoxFit.cover,
                    cacheWidth: 640,
                    excludeFromSemantics: true,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.32, 0.66, 1],
                        colors: [
                          Color(0x08000000),
                          Color(0x18000000),
                          Color(0x85000000),
                          Color(0xE6000000),
                        ],
                      ),
                    ),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: () => onSelected(index),
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        children: [
                          if (stackedIcon)
                            Positioned(top: 10, left: 10, child: categoryIcon),
                          if (item.$4 != null)
                            Positioned(
                              top: 9,
                              right: 9,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${item.$4}',
                                  style: const TextStyle(
                                    color: Color(0xFF142832),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 10,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (!stackedIcon) ...[
                                  categoryIcon,
                                  const SizedBox(width: 7),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.$1,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: stackedIcon ? 12 : 14,
                                          fontWeight: FontWeight.w800,
                                          height: 1.1,
                                          letterSpacing: -0.25,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        item.$2,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFF5F7F8),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MapDiscoverCard extends StatelessWidget {
  const _MapDiscoverCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HomePhotoDiscoverCard(
      title: 'Haritada keşfet',
      subtitle: 'Yakınındaki yerleri ve tesisleri haritada görün.',
      actionLabel: 'Haritayı aç',
      imageAsset: 'assets/images/home_discover/map.webp',
      icon: Icons.map_rounded,
      accent: const Color(0xFF007B8F),
      onTap: onTap,
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onRoute,
    required this.onPrice,
    required this.onWeather,
    required this.onHolidays,
  });

  final VoidCallback onRoute;
  final VoidCallback onPrice;
  final VoidCallback onWeather;
  final VoidCallback onHolidays;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fontExtra = MediaQuery.textScalerOf(context).scale(12) - 12;
        final columns = constraints.maxWidth < 320 || fontExtra > 3 ? 2 : 4;
        return GridView.count(
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 112 + fontExtra.clamp(0, 30) * 2,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _QuickAction(
              icon: Icons.location_on_rounded,
              label: 'Yakınımdaki\nMisafirhaneler',
              color: const Color(0xFF1565C0),
              background: const Color(0xFFE3F0FF),
              imageAsset: 'assets/images/home_categories/konaklama.webp',
              onTap: onRoute,
            ),
            ValueListenableBuilder<bool>(
              valueListenable: ProService.instance.isPro,
              builder: (_, _, _) {
                final pro = ProService.instance.hasProAccess;
                return _QuickAction(
                  icon: Icons.payments_rounded,
                  label: 'Fiyat',
                  color: dark
                      ? const Color(0xFFF2C14E)
                      : const Color(0xFFB8860B),
                  background: dark
                      ? const Color(0xFF3A2E14)
                      : const Color(0xFFFFF3D0),
                  imageAsset: 'assets/images/home_discover/prices.webp',
                  badge: pro ? null : 'Pro',
                  onTap: onPrice,
                );
              },
            ),
            _QuickAction(
              icon: Icons.cloud_rounded,
              label: 'Meteoroloji',
              color: const Color(0xFF00838F),
              background: const Color(0xFFD7F4F7),
              imageAsset: 'assets/images/home_discover/weather.webp',
              onTap: onWeather,
            ),
            _QuickAction(
              icon: Icons.calendar_month_rounded,
              label: 'Tatiller',
              color: const Color(0xFFEF6C00),
              background: const Color(0xFFFFE8CC),
              imageAsset: 'assets/images/home_discover/holidays.webp',
              onTap: onHolidays,
            ),
          ],
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
    required this.imageAsset,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final String imageAsset;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final shade = Color.lerp(color, const Color(0xFF0B1823), 0.7)!;
    return Material(
      color: AppColors.isDark(context) ? shade : background,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            imageAsset,
            fit: BoxFit.cover,
            cacheWidth: 360,
            excludeFromSemantics: true,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.4, 1],
                colors: [
                  const Color(0x22000000),
                  shade.withValues(alpha: 0.1),
                  shade,
                ],
              ),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 18),
                    ),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: label.contains('\n') ? 2 : 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              top: 6,
              right: 6,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFDC83),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Color(0xFF503608),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<RecentSearchEntry>>(
      valueListenable: RecentSearchStore.instance.items,
      builder: (context, queries, _) {
        final recent = queries.take(RecentSearchStore.maxItems).toList();
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.isDark(context)
                            ? AppColors.darkPrimarySoft
                            : AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.history_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Son aramalar',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            recent.isEmpty
                                ? 'Aradığınız yerler burada durur'
                                : 'Kaldığınız yerden devam edin',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'Bir il, ilçe veya tesis arayın. Son üç aramanız kısayol olarak burada görünür.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 60,
                      color: AppColors.borderOf(context),
                    ),
                  _RecentSearchRow(
                    entry: recent[i],
                    onTap: () => onSelect(recent[i].query),
                  ),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _RecentSearchRow extends StatelessWidget {
  const _RecentSearchRow({required this.entry, required this.onTap});

  final RecentSearchEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Icon(
                Icons.place_outlined,
                color: AppColors.textMutedOf(context),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textStrongOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.dateLabel,
                style: TextStyle(
                  color: AppColors.textMutedOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.north_east_rounded,
                color: AppColors.textMutedOf(context),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
