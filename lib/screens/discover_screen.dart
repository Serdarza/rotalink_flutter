import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_service.dart';
import '../ads/discover_native_merge.dart';
import '../data/campaign_repository.dart';
import '../l10n/app_strings.dart';
import '../models/campaign.dart';
import '../theme/app_colors.dart';
import '../widgets/campaign_smart_icon.dart';
import '../widgets/rotalink_banner_ad.dart';
import 'campaign_detail_screen.dart';

const _headerTop = Color(0xFF005F6B);
const _headerBottom = Color(0xFF008898);

/// Kotlin [DiscoverActivity] + [DiscoverComposeScreen] (liste arası native + banner).
class DiscoverScreen extends StatefulWidget {
  DiscoverScreen({super.key, CampaignRepository? repository})
    : repository = repository ?? CampaignRepository();

  final CampaignRepository repository;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _search = TextEditingController();
  final ValueNotifier<String> _debouncedFilter = ValueNotifier<String>('');
  final ValueNotifier<int> _discoverBodyTick = ValueNotifier<int>(0);
  Timer? _searchDebounce;
  StreamSubscription<List<Campaign>>? _campaignSub;

  List<Campaign> _allCampaigns = const [];
  String? _firestoreError;
  bool _streamWaiting = true;

  List<NativeAd> _nativeAds = const [];
  bool _nativeBusy = false;
  int _nativeGen = 0;

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
    _search.addListener(_onSearchTextChanged);
    _campaignSub = widget.repository.watchCampaignsOrdered().listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _allCampaigns = list;
          _firestoreError = null;
          _streamWaiting = false;
        });
        _discoverBodyTick.value++;
        _onCampaignsDataChanged();
      },
      onError: (Object? _, StackTrace? stackTrace) {
        if (!mounted) return;
        _nativeGen++;
        _disposeNatives();
        setState(() {
          _firestoreError = 'Kampanyalar yüklenemedi.';
          _allCampaigns = const [];
          _streamWaiting = false;
          _nativeBusy = false;
        });
        _discoverBodyTick.value++;
      },
    );
  }

  void _disposeNatives() {
    for (final a in _nativeAds) {
      a.dispose();
    }
    _nativeAds = const [];
  }

  void _onCampaignsDataChanged() {
    if (_firestoreError != null) return;

    if (!AdService.adsEnabled || kIsWeb) {
      _disposeNatives();
      if (mounted) {
        setState(() => _nativeBusy = false);
        _discoverBodyTick.value++;
      }
      return;
    }

    final needed = DiscoverNativeMerge.nativeSlotsNeeded(_allCampaigns.length);
    if (needed == 0) {
      _disposeNatives();
      if (mounted) {
        setState(() => _nativeBusy = false);
        _discoverBodyTick.value++;
      }
      return;
    }

    if (_nativeAds.length >= needed) {
      if (mounted) {
        setState(() => _nativeBusy = false);
        _discoverBodyTick.value++;
      }
      return;
    }

    unawaited(_reloadNativeAds(needed));
  }

  Future<void> _reloadNativeAds(int needed) async {
    _disposeNatives();
    final gen = ++_nativeGen;
    if (mounted) {
      setState(() => _nativeBusy = true);
      _discoverBodyTick.value++;
    }

    final loaded = await DiscoverNativeMerge.loadPool(needed);

    if (!mounted || gen != _nativeGen) {
      for (final a in loaded) {
        a.dispose();
      }
      return;
    }

    setState(() {
      _nativeAds = loaded;
      _nativeBusy = false;
    });
    _discoverBodyTick.value++;
  }

  @override
  void dispose() {
    _nativeGen++;
    _searchDebounce?.cancel();
    _debouncedFilter.dispose();
    _discoverBodyTick.dispose();
    _campaignSub?.cancel();
    _search.removeListener(_onSearchTextChanged);
    _search.dispose();
    _disposeNatives();
    super.dispose();
  }

  List<Campaign> _filtered(List<Campaign> all, String query) {
    final q = query.toLowerCase();
    if (q.isEmpty) return all;
    return all.where((c) {
      return c.title.toLowerCase().contains(q) ||
          c.organization.toLowerCase().contains(q) ||
          c.summary.toLowerCase().contains(q);
    }).toList();
  }

  String _emptyMessage({
    required bool overlayLoading,
    required List<Campaign> all,
    required List<Campaign> filtered,
  }) {
    if (_firestoreError != null) return _firestoreError!;
    if (overlayLoading) return '';
    if (filtered.isNotEmpty) return '';
    if (all.isEmpty) return 'Henüz kampanya yok.';
    return 'Aramana uygun kampanya bulunamadı.';
  }

  bool _overlayLoading() {
    if (_streamWaiting) return true;
    if (_firestoreError != null) return false;
    if (!AdService.adsEnabled || kIsWeb) return false;
    final needed = DiscoverNativeMerge.nativeSlotsNeeded(_allCampaigns.length);
    return needed > 0 && _nativeBusy;
  }

  Widget _buildBody({
    required BuildContext context,
    required bool overlay,
    required List<Object> merged,
    required int campaignOnly,
    required String emptyMsg,
  }) {
    if (overlay) {
      return const _DiscoverLoadingBody();
    }
    if (campaignOnly == 0) {
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
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + ime),
      itemCount: merged.length,
      itemBuilder: (context, index) {
        final item = merged[index];
        if (item is Campaign) {
          final c = item;
          return _CampaignDiscoverCard(
            campaign: c,
            onOpenDetail: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => CampaignDetailScreen(campaign: c),
                ),
              );
            },
          );
        }
        if (item is NativeAd) {
          return Padding(
            key: ValueKey<Object>('native-$index-${item.hashCode}'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 320,
                width: double.infinity,
                child: AdWidget(ad: item),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
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
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            children: [
              _DiscoverHeader(
                searchController: _search,
                headerTop: _headerTop,
                headerBottom: _headerBottom,
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _debouncedFilter,
                    _discoverBodyTick,
                  ]),
                  builder: (context, _) {
                    final filterQuery = _debouncedFilter.value;
                    final filtered = _firestoreError != null
                        ? const <Campaign>[]
                        : _filtered(_allCampaigns, filterQuery);
                    final merged = DiscoverNativeMerge.mergeFiltered(
                      filtered,
                      _nativeAds,
                    );
                    final overlay = _overlayLoading();
                    final campaignOnly = merged.whereType<Campaign>().length;
                    final emptyMsg = _emptyMessage(
                      overlayLoading: overlay,
                      all: _allCampaigns,
                      filtered: filtered,
                    );
                    return _buildBody(
                      context: context,
                      overlay: overlay,
                      merged: merged,
                      campaignOnly: campaignOnly,
                      emptyMsg: emptyMsg,
                    );
                  },
                ),
              ),
              RotalinkBannerAd(adsEnabled: AdService.adsEnabled),
            ],
          ),
        ),
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
  });

  final TextEditingController searchController;
  final Color headerTop;
  final Color headerBottom;
  final VoidCallback onBack;

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
