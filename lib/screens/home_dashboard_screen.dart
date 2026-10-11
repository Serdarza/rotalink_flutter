import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/store_links.dart';
import '../billing/pro_service.dart';
import '../data/firebase_rota_repository.dart';
import '../data/hediyelik_repository.dart';
import '../models/misafirhane.dart';
import '../data/kamp_repository.dart';
import '../data/recent_search_store.dart';
import '../l10n/app_strings.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../theme/app_colors.dart';
import '../theme/system_ui.dart';
import '../utils/main_map_search.dart';
import '../widgets/custom_search_bar.dart';
import '../widgets/drawer_social_section.dart';
import '../widgets/emergency_bottom_sheet.dart';
import '../widgets/map_weather_chip.dart';
import '../widgets/nationwide_price_sheet.dart';
import '../widgets/rotalink_pro_chip.dart';
import '../widgets/weather_bottom_sheet.dart';

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
    unawaited(
      RotalinkSystemUi.applyEdgeToEdge(),
    );
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

  Future<void> _openEmergency() => showEmergencyBottomSheet(context);

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
        backgroundColor: AppColors.canvasOf(context),
        drawer: _HomeMenu(
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    sliver: SliverList.list(
                      children: [
                        _WelcomeHeader(
                          controller: _searchController,
                          ilOptionsSorted: iller,
                          onSubmitted: _submitSearch,
                        ),
                        const SizedBox(height: 24),
                        const _SectionTitle(title: 'Ne arıyorsunuz?'),
                        const SizedBox(height: 12),
                        _CategoryGrid(
                          data: data,
                          onSelected: widget.onOpenCategory,
                        ),
                        const SizedBox(height: 16),
                        _MapDiscoverCard(onTap: widget.onOpenMap),
                        const SizedBox(height: 24),
                        _SectionTitle(
                          title: 'Hızlı işlemler',
                          actionLabel: 'Kampanyalar',
                          onAction: widget.onOpenDiscover,
                        ),
                        const SizedBox(height: 12),
                        _QuickActions(
                          onRoute: widget.onOpenRoutePlan,
                          onPrice: () => unawaited(_openPriceBrowse(data)),
                          onWeather: () => unawaited(_openWeather()),
                          onHolidays: () => widget.onOpenNamedRoute(
                            RotalinkShellRoutes.holidays,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _RecentSearches(onSelect: widget.onSubmitQuery),
                        const SizedBox(height: 18),
                        _AssistantCard(onTap: widget.onOpenKami),
                        const SizedBox(height: 12),
                        _EmergencyCard(onTap: () => unawaited(_openEmergency())),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: AppStrings.menuOpen,
            child: IconButton(
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded),
              color: AppColors.textStrongOf(context),
              tooltip: AppStrings.menuOpen,
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: 32,
              height: 32,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.appName,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontSize: 22),
            ),
          ),
          const SizedBox(width: 8),
          MapWeatherChip(compact: true, rotaData: data),
          const SizedBox(width: 8),
          RotalinkProChip(
            onTap: () => widget.onOpenNamedRoute(RotalinkShellRoutes.pro),
          ),
        ],
      ),
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
        const SizedBox(height: 2),
        Text(
          'Bugün nereye gidiyoruz?',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 18),
        CustomSearchBar(
          controller: controller,
          ilOptionsSorted: ilOptionsSorted,
          onSubmitted: onSubmitted,
          ignoreKeyboardInset: true,
          emphasized: true,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
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
              hediyelikCount: HediyelikRepository.instance.forIller(const {}).length,
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
    final items = [
      (
        'Konaklama',
        'Misafirhane ve orduevi',
        Icons.bed_rounded,
        data?.misafirhaneler.length,
        const Color(0xFF007B8F),
        const Color(0xFFD4F3F6),
      ),
      (
        'Gezi',
        'Gezilecek yerler',
        Icons.landscape_rounded,
        data?.gezi.length,
        const Color(0xFF2E7D32),
        const Color(0xFFDFF3E3),
      ),
      (
        'Yemek',
        'Yerel lezzetler',
        Icons.restaurant_rounded,
        data?.yemek.length,
        const Color(0xFFE65100),
        const Color(0xFFFFE8D6),
      ),
      (
        'Sosyal tesisler',
        'Yakınındaki tesisler',
        Icons.apartment_rounded,
        data?.sosyal.length,
        const Color(0xFF5E35B1),
        const Color(0xFFEEE6FA),
      ),
      (
        'Hediyelik',
        'Yöresel ürünler',
        Icons.card_giftcard_rounded,
        hediyelikCount == 0 ? null : hediyelikCount,
        const Color(0xFFAD1457),
        const Color(0xFFFCE4EC),
      ),
      (
        'Kamp yerleri',
        'Çadır ve karavan',
        Icons.park_rounded,
        kampCount == 0 ? null : kampCount,
        const Color(0xFF558B2F),
        const Color(0xFFF1F8E9),
      ),
    ];

    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 112,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final cardBg = AppColors.isDark(context)
            ? Color.alphaBlend(item.$5.withValues(alpha: 0.22), AppColors.darkSurface)
            : item.$6;
        return Material(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          elevation: 0,
          child: InkWell(
            onTap: () => onSelected(index),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: item.$5.withValues(alpha: 0.22)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: item.$5,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          item.$3,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const Spacer(),
                      if (item.$4 != null)
                        Text(
                          '${item.$4}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    item.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 142,
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF007B8F), Color(0xFF00A3B8)],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Haritada keşfet',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Yakınındaki yerleri ve tesisleri haritada görün.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                    const Spacer(),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Haritayı aç',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 112,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.map_rounded, color: Colors.white, size: 60),
                    Positioned(
                      top: 28,
                      right: 27,
                      child: Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFFFFD54F),
                        size: 27,
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
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.alt_route_rounded,
            label: 'Rota',
            color: const Color(0xFF1565C0),
            background: const Color(0xFFE3F0FF),
            onTap: onRoute,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: ProService.instance.isPro,
            builder: (_, _, _) {
              final pro = ProService.instance.hasProAccess;
              return _QuickAction(
                icon: Icons.payments_rounded,
                label: 'Fiyat',
                color: dark ? const Color(0xFFF2C14E) : const Color(0xFFB8860B),
                background:
                    dark ? const Color(0xFF3A2E14) : const Color(0xFFFFF3D0),
                badge: pro ? null : 'Pro',
                onTap: onPrice,
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            icon: Icons.cloud_rounded,
            label: 'Hava',
            color: const Color(0xFF00838F),
            background: const Color(0xFFD7F4F7),
            onTap: onWeather,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            icon: Icons.calendar_month_rounded,
            label: 'Tatiller',
            color: const Color(0xFFEF6C00),
            background: const Color(0xFFFFE8CC),
            onTap: onHolidays,
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 23),
                    const SizedBox(height: 7),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF2C14E), Color(0xFFB8860B)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
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

class _AssistantCard extends StatelessWidget {
  const _AssistantCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InfoActionCard(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.asset(
          'assets/images/kami_logo.png',
          width: 46,
          height: 46,
          fit: BoxFit.cover,
        ),
      ),
      title: 'KAMİ’ye sor',
      subtitle: 'Gezi, yemek ve rota önerilerini keşfet.',
      actionLabel: 'Asistanı aç',
      background: const Color(0xFFDFF4F6),
      borderColor: const Color(0xFF007B8F).withValues(alpha: 0.22),
      onTap: onTap,
    );
  }
}

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InfoActionCard(
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const EmergencyHilalIcon(color: Colors.white, size: 26),
      ),
      title: 'Acil durumda hızlı erişim',
      subtitle: 'Yardım numaraları ve önemli bilgilere ulaşın.',
      actionLabel: 'Acil yardım',
      actionColor: AppColors.danger,
      background: const Color(0xFFFFE8E9),
      borderColor: AppColors.danger.withValues(alpha: 0.22),
      onTap: onTap,
    );
  }
}

class _InfoActionCard extends StatelessWidget {
  const _InfoActionCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    this.actionColor = AppColors.primary,
    this.background = AppColors.surface,
    this.borderColor = AppColors.border,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String actionLabel;
  final Color actionColor;
  final Color background;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Text(
                actionLabel,
                style: TextStyle(
                  color: actionColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeMenu extends StatelessWidget {
  const _HomeMenu({required this.onOpenRoute, required this.onOpenWeather});

  final ValueChanged<String> onOpenRoute;
  final VoidCallback onOpenWeather;

  Future<void> _openWebsite(BuildContext context) async {
    Navigator.pop(context);
    final uri = Uri.parse('https://rotalink.tr/?web=1');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Web sitesi açılamadı.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    void openRoute(String route) {
      Navigator.pop(context);
      onOpenRoute(route);
    }

    return Drawer(
      width: 300,
      backgroundColor: AppColors.surfaceOf(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.appName,
                          style: TextStyle(
                            color: AppColors.textStrong,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          AppStrings.drawerSubtitle,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _MenuTile(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Rotalink Pro',
                    onTap: () => openRoute(RotalinkShellRoutes.pro),
                  ),
                  _MenuTile(
                    icon: Icons.wb_sunny_outlined,
                    title: AppStrings.drawerWeather,
                    onTap: () {
                      Navigator.pop(context);
                      onOpenWeather();
                    },
                  ),
                  _MenuTile(
                    icon: Icons.calendar_month_outlined,
                    title: AppStrings.drawerHolidays,
                    onTap: () => openRoute(RotalinkShellRoutes.holidays),
                  ),
                  _MenuTile(
                    icon: Icons.send_outlined,
                    title: AppStrings.drawerSuggestion,
                    onTap: () => openRoute(RotalinkShellRoutes.suggestion),
                  ),
                  _MenuTile(
                    icon: Icons.language_outlined,
                    title: AppStrings.drawerWebsite,
                    onTap: () => unawaited(_openWebsite(context)),
                  ),
                  _MenuTile(
                    icon: Icons.share_outlined,
                    title: AppStrings.drawerShareApp,
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(Share.share(StoreLinks.drawerShareMessage()));
                    },
                  ),
                  const DrawerSocialSection(),
                  _MenuTile(
                    icon: Icons.info_outline_rounded,
                    title: AppStrings.drawerAbout,
                    onTap: () => openRoute(RotalinkShellRoutes.about),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, color: AppColors.primary),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textStrong,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textMuted,
      ),
      onTap: onTap,
    );
  }
}
