import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/campaign_filter_prefs.dart';
import '../data/campaign_repository.dart';
import '../l10n/app_strings.dart';
import '../models/campaign.dart';
import '../models/campaign_insights.dart';
import '../theme/app_colors.dart';
import '../theme/system_ui.dart';
import '../widgets/campaign_smart_icon.dart';
import 'campaign_detail_screen.dart';

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
      RotalinkSystemUi.applyEdgeToEdge(),
    );
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
    required CampaignAudience? audience,
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
            audience: audience ?? CampaignInsights.of(c).primaryAudience,
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: RotalinkSystemUi.forBrightness(Theme.of(context).brightness),
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.canvasOf(context),
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
                      audience: audience,
                    );
                  },
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
            color: AppColors.primary,
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final a in visible)
            _AudienceChip(
              label: a.label,
              icon: a.icon,
              count: counts[a] ?? 0,
              color: a.color,
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
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final accent = dark ? Color.lerp(color, Colors.white, 0.22)! : color;
    final fg = selected ? Colors.white : accent;
    final bg = selected
        ? accent
        : Color.alphaBlend(
            accent.withValues(alpha: dark ? 0.22 : 0.12),
            AppColors.surfaceOf(context),
          );
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label, $count kampanya',
        child: Material(
          color: bg,
          shape: StadiumBorder(
            side: BorderSide(
              color: accent.withValues(alpha: selected ? 1 : 0.35),
            ),
          ),
          elevation: selected ? 1 : 0,
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
                          ? Colors.white.withValues(alpha: 0.22)
                          : accent.withValues(alpha: 0.16),
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
    final dark = AppColors.isDark(context);
    return Container(
      width: double.infinity,
      color: dark ? const Color(0xFF3A2C14) : const Color(0xFFFFF8E1),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 15,
            color: dark ? const Color(0xFFFFCC80) : const Color(0xFFE65100),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Kampanyalar bağımsız kaynaklardan derlenmektedir. '
              'Rotalink hiçbir devlet kuruluşunu temsil etmemektedir.',
              style: TextStyle(
                fontSize: 11,
                color: dark ? const Color(0xFFFFE0B2) : const Color(0xFF5D4037),
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
    required this.onBack,
    this.showBackButton = true,
  });

  final TextEditingController searchController;
  final VoidCallback onBack;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      elevation: 0,
      color: AppColors.surfaceOf(context),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
        ),
        padding: EdgeInsets.fromLTRB(4, top + 4, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showBackButton)
                  IconButton(
                    onPressed: onBack,
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textStrongOf(context),
                    ),
                    tooltip: 'Geri',
                  ),
                Text(
                  AppStrings.bottomDiscover,
                  style: TextStyle(
                    color: AppColors.textStrongOf(context),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
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
          style: TextStyle(color: AppColors.textStrongOf(context)),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
            hintText: AppStrings.discoverSearchHint,
            hintStyle: TextStyle(color: AppColors.textMutedOf(context)),
            filled: true,
            fillColor: AppColors.canvasOf(context),
            border: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
    required this.audience,
    required this.onOpenDetail,
  });

  final Campaign campaign;
  final CampaignAudience audience;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final title = campaign.title;
    final summary = campaign.summary;
    final tags = campaign.tags;
    final icon = campaignSmartIconData(title, summary);
    final dark = AppColors.isDark(context);
    final tint = dark
        ? Color.lerp(audience.color, Colors.white, 0.18)!
        : audience.color;
    final cardBg = Color.alphaBlend(
      tint.withValues(alpha: dark ? 0.20 : 0.10),
      AppColors.surfaceOf(context),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onOpenDetail,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tint.withValues(alpha: 0.22)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        audience.label,
                        style: TextStyle(
                          color: tint,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      _CampaignBadges(insights: CampaignInsights.of(campaign)),
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: tags
                              .where((t) => t.trim().isNotEmpty)
                              .take(3)
                              .map(
                                (t) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceOf(context)
                                        .withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.borderOf(context),
                                    ),
                                  ),
                                  child: Text(
                                    t.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textMutedOf(context),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          AppStrings.campaignDetailCta,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
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
