import 'dart:async';

import 'package:flutter/material.dart';

import '../data/campaign_filter_prefs.dart';
import '../data/campaign_repository.dart';
import '../l10n/app_strings.dart';
import '../models/campaign.dart';
import '../models/campaign_insights.dart';
import '../theme/app_colors.dart';
import '../widgets/campaign_smart_icon.dart';
import 'campaign_detail_screen.dart';

const _headerTop = Color(0xFF005F6B);
const _headerBottom = Color(0xFF008898);

/// Kotlin [DiscoverActivity] + [DiscoverComposeScreen].
class DiscoverScreen extends StatefulWidget {
  DiscoverScreen({
    super.key,
    CampaignRepository? repository,
    this.embeddedInShell = false,
    this.showBackButton = true,
  }) : repository = repository ?? CampaignRepository();

  final CampaignRepository repository;

  /// [RotalinkMainShell] içinde — alt menü dışarıda kalır.
  final bool embeddedInShell;

  /// Alt menü sekmesinden açıldığında geri oku gizlenir.
  final bool showBackButton;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _search = TextEditingController();
  final ValueNotifier<String> _debouncedFilter = ValueNotifier<String>('');
  final ValueNotifier<int> _discoverBodyTick = ValueNotifier<int>(0);
  final ValueNotifier<CampaignAudience?> _audience =
      ValueNotifier<CampaignAudience?>(null);
  Timer? _searchDebounce;
  StreamSubscription<List<Campaign>>? _campaignSub;

  List<Campaign> _allCampaigns = const [];
  String? _loadError;
  bool _streamWaiting = true;

  void _onSearchTextChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _debouncedFilter.value = _search.text.trim();
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(
      CampaignFilterPrefs.getAudience().then((a) {
        if (mounted && a != null) _audience.value = a;
      }),
    );
    if (widget.repository.isReady) {
      _allCampaigns = widget.repository.currentCampaigns;
      _streamWaiting = false;
    }
    _search.addListener(_onSearchTextChanged);
    _campaignSub = widget.repository.watchCampaignsOrdered().listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _allCampaigns = list;
          _loadError = null;
          _streamWaiting = false;
        });
        _discoverBodyTick.value++;
      },
      onError: (Object? _, StackTrace? stackTrace) {
        if (!mounted) return;
        setState(() {
          _loadError = 'Kampanyalar yüklenemedi.';
          _allCampaigns = const [];
          _streamWaiting = false;
        });
        _discoverBodyTick.value++;
      },
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _debouncedFilter.dispose();
    _discoverBodyTick.dispose();
    _audience.dispose();
    _campaignSub?.cancel();
    _search.removeListener(_onSearchTextChanged);
    _search.dispose();
    super.dispose();
  }

  List<Campaign> _filtered(
    List<Campaign> all,
    String query,
    CampaignAudience? audience,
  ) {
    final q = foldTr(query);
    if (q.isEmpty && audience == null) return all;
    return all.where((c) {
      if (audience != null && !CampaignInsights.of(c).matches(audience)) {
        return false;
      }
      if (q.isEmpty) return true;
      return foldTr(c.title).contains(q) ||
          foldTr(c.organization).contains(q) ||
          foldTr(c.summary).contains(q) ||
          c.tags.any((t) => foldTr(t).contains(q));
    }).toList();
  }

  void _selectAudience(CampaignAudience? a) {
    if (_audience.value == a) return;
    _audience.value = a;
    unawaited(CampaignFilterPrefs.setAudience(a));
  }

  String _emptyMessage({
    required bool overlayLoading,
    required List<Campaign> all,
    required List<Campaign> filtered,
    required CampaignAudience? audience,
    required String query,
  }) {
    if (_loadError != null) return _loadError!;
    if (overlayLoading) return '';
    if (filtered.isNotEmpty) return '';
    if (all.isEmpty) return 'Henüz kampanya yok.';
    if (audience != null && query.isEmpty) {
      return '${audience.label} için şu an kampanya bulunmuyor.\n'
          'Yeni kampanyalar her gün otomatik eklenir.';
    }
    return 'Aramana uygun kampanya bulunamadı.';
  }

  bool _overlayLoading() => _streamWaiting && _loadError == null;

  Widget _buildBody({
    required BuildContext context,
    required bool overlay,
    required List<Campaign> campaigns,
    required String emptyMsg,
  }) {
    if (overlay) {
      return const _DiscoverLoadingBody();
    }
    if (campaigns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMsg,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppColors.primary),
          ),
        ),
      );
    }
    final ime = MediaQuery.viewInsetsOf(context).bottom;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: widget.repository.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + ime),
        itemCount: campaigns.length,
        itemBuilder: (context, index) {
          final c = campaigns[index];
          return _CampaignDiscoverCard(
            campaign: c,
            onOpenDetail: () {
              Navigator.of(context, rootNavigator: false).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => CampaignDetailScreen(campaign: c),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.backgroundMain,
      // Üst şerit status bar’a taşsın; alt gest / üç tuş hep üstte kalsın (viewPadding klavyede de doğru).
      body: SafeArea(
        top: false,
        bottom: !widget.embeddedInShell,
        child: Padding(
          padding: widget.embeddedInShell
              ? EdgeInsets.zero
              : EdgeInsets.only(
                  bottom: MediaQuery.viewPaddingOf(context).bottom,
                ),
          child: Column(
            children: [
              _DiscoverHeader(
                searchController: _search,
                headerTop: _headerTop,
                headerBottom: _headerBottom,
                showBackButton: widget.showBackButton,
                onBack: () => Navigator.of(context).pop(),
              ),
              AnimatedBuilder(
                animation: Listenable.merge([_audience, _discoverBodyTick]),
                builder: (context, _) => _AudienceFilterBar(
                  campaigns: _loadError != null ? const [] : _allCampaigns,
                  selected: _audience.value,
                  onSelected: _selectAudience,
                ),
              ),
              _DisclaimerBanner(),
              Expanded(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _debouncedFilter,
                    _discoverBodyTick,
                    _audience,
                  ]),
                  builder: (context, _) {
                    final filterQuery = _debouncedFilter.value;
                    final audience = _audience.value;
                    final filtered = _loadError != null
                        ? const <Campaign>[]
                        : _filtered(_allCampaigns, filterQuery, audience);
                    final overlay = _overlayLoading();
                    final emptyMsg = _emptyMessage(
                      overlayLoading: overlay,
                      all: _allCampaigns,
                      filtered: filtered,
                      audience: audience,
                      query: filterQuery,
                    );
                    return _buildBody(
                      context: context,
                      overlay: overlay,
                      campaigns: filtered,
                      emptyMsg: emptyMsg,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kamu personeli grubu seçimi: tek dokunuşla filtre, her grupta kampanya sayısı.
class _AudienceFilterBar extends StatelessWidget {
  const _AudienceFilterBar({
    required this.campaigns,
    required this.selected,
    required this.onSelected,
  });

  final List<Campaign> campaigns;
  final CampaignAudience? selected;
  final ValueChanged<CampaignAudience?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (campaigns.isEmpty) return const SizedBox(height: 8);
    final counts = <CampaignAudience, int>{
      for (final a in CampaignAudience.values)
        a: campaigns.where((c) => CampaignInsights.of(c).matches(a)).length,
    };
    // "Tüm Kamu" yalnızca genel kampanyaları sayar; diğer gruplara da dahil oldukları için
    // kendi sayısı gruba özel olanlardan küçük olabilir.
    final visible = CampaignAudience.values
        .where((a) => (counts[a] ?? 0) > 0 || a == selected)
        .toList();

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        children: [
          _AudienceChip(
            label: 'Tümü',
            icon: Icons.apps_rounded,
            count: campaigns.length,
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final a in visible)
            _AudienceChip(
              label: a.label,
              icon: a.icon,
              count: counts[a] ?? 0,
              selected: selected == a,
              onTap: () => onSelected(selected == a ? null : a),
            ),
        ],
      ),
    );
  }
}

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.white : _headerTop;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label, $count kampanya',
        child: Material(
          color: selected ? _headerTop : AppColors.white,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? _headerTop : const Color(0x33005F6B),
            ),
          ),
          elevation: selected ? 2 : 0,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: fg),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0x33FFFFFF)
                          : const Color(0x14005F6B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
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

class _DisclaimerBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF8E1),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 15, color: Color(0xFFE65100)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Kampanyalar bağımsız kaynaklardan derlenmektedir. '
              'Rotalink hiçbir devlet kuruluşunu temsil etmemektedir.',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF5D4037),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoverHeader extends StatelessWidget {
  const _DiscoverHeader({
    required this.searchController,
    required this.headerTop,
    required this.headerBottom,
    required this.onBack,
    this.showBackButton = true,
  });

  final TextEditingController searchController;
  final Color headerTop;
  final Color headerBottom;
  final VoidCallback onBack;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      elevation: 10,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(28),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [headerTop, headerBottom],
          ),
        ),
        padding: EdgeInsets.fromLTRB(4, top + 4, 4, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showBackButton)
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, color: AppColors.white),
                    tooltip: 'Geri',
                  ),
                const Text(
                  AppStrings.bottomDiscover,
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _DiscoverSearchField(controller: searchController),
          ],
        ),
      ),
    );
  }
}

/// Keşfet arama satırı — klavye inset’i yalnızca bu şeride uygulanır ([resizeToAvoidBottomInset] kapalıyken).
class _DiscoverSearchField extends StatelessWidget {
  const _DiscoverSearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final ime = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: ime),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.white),
          cursorColor: AppColors.white,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, color: Color(0xD9FFFFFF)),
            hintText: AppStrings.discoverSearchHint,
            hintStyle: TextStyle(color: Color(0xA6FFFFFF)),
            filled: true,
            fillColor: Color(0x1FFFFFFF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: Color(0x80FFFFFF)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: Color(0x80FFFFFF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: AppColors.white),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ),
    );
  }
}

class _DiscoverLoadingBody extends StatelessWidget {
  const _DiscoverLoadingBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            AppStrings.discoverLoadingTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.discoverLoadingSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.campaignSummaryMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// İndirim oranı, yeni eklenme ve bitiş tarihi rozetleri (yalnızca metinde varsa).
class _CampaignBadges extends StatelessWidget {
  const _CampaignBadges({required this.insights});

  final CampaignInsights insights;

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final pct = insights.maxDiscountPercent;
    final left = insights.daysLeft(now);
    final badges = <Widget>[
      if (pct != null)
        _Badge(
          text: '%$pct indirim',
          icon: Icons.local_offer_outlined,
          fg: const Color(0xFF1B5E20),
          bg: const Color(0xFFE8F5E9),
        ),
      if (insights.isNew(now))
        const _Badge(
          text: 'Yeni',
          icon: Icons.fiber_new_outlined,
          fg: Color(0xFF0D47A1),
          bg: Color(0xFFE3F2FD),
        ),
      if (left != null && left >= 0)
        left == 0
            ? const _Badge(
                text: 'Bugün son gün',
                icon: Icons.timer_outlined,
                fg: Color(0xFFB71C1C),
                bg: Color(0xFFFFEBEE),
              )
            : left <= 7
            ? _Badge(
                text: 'Son $left gün',
                icon: Icons.timer_outlined,
                fg: const Color(0xFFE65100),
                bg: const Color(0xFFFFF3E0),
              )
            : _Badge(
                text: 'Son gün ${_date(insights.endDate!)}',
                icon: Icons.event_outlined,
                fg: const Color(0xFF546E7A),
                bg: const Color(0xFFF1F4F6),
              ),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: badges),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.icon,
    required this.fg,
    required this.bg,
  });

  final String text;
  final IconData icon;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _CampaignDiscoverCard extends StatelessWidget {
  const _CampaignDiscoverCard({
    required this.campaign,
    required this.onOpenDetail,
  });

  final Campaign campaign;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final title = campaign.title;
    final summary = campaign.summary;
    final tags = campaign.tags;
    final icon = campaignSmartIconData(title, summary);
    final bg = campaignSmartIconBackground(title, summary);
    final tint = campaignSmartIconTint(title, summary);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        elevation: 5,
        borderRadius: BorderRadius.circular(16),
        color: AppColors.white,
        child: InkWell(
          onTap: onOpenDetail,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(icon, color: tint, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      _CampaignBadges(insights: CampaignInsights.of(campaign)),
                      const SizedBox(height: 6),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.campaignSummaryMuted,
                        ),
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: tags
                              .where((t) => t.trim().isNotEmpty)
                              .map(
                                (t) => Chip(
                                  label: Text(
                                    t.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onOpenDetail,
                          child: const Text(AppStrings.campaignDetailCta),
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
    );
  }
}
