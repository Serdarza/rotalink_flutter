import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../billing/price_access.dart';
import '../billing/pro_service.dart';
import '../constants/facility_pricing.dart';
import '../constants/store_links.dart';
import '../data/facility_compare_selection.dart';
import '../data/facility_sort_prefs.dart';
import '../providers/facility_filter_provider.dart';
import '../navigator_keys.dart';
import '../screens/yorum_screen.dart';
import '../services/review_repository.dart';
import '../services/view_counter_service.dart';
import '../data/favorites_repository.dart';
import '../data/facility_address_repository.dart';
import '../data/facility_price_repository.dart';
import '../data/firebase_rota_repository.dart';
import '../data/gezi_yemek_repository.dart';
import '../data/hediyelik_repository.dart';
import '../data/kamp_repository.dart';
import '../data/sosyal_menu_repository.dart';
import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
import '../models/sosyal_item.dart';
import '../map_location_state.dart';
import '../services/nominatim_geocode_cache.dart';
import '../theme/app_colors.dart';
import 'kamp_rotalari_view.dart';
import '../utils/geo_helpers.dart';
import '../utils/il_ilce.dart';
import '../utils/main_map_search.dart';
import '../utils/maps_launch.dart';
import '../utils/safe_map_coordinates.dart';
import '../utils/best_value_facility.dart';
import '../utils/search_normalize.dart';
import '../theme/ara_ui.dart';
import 'ara_action_button.dart';
import 'view_count_label.dart';
import 'best_value_pro_card.dart';
import 'distance_permission_chip.dart';
import 'facility_compare_widgets.dart';
import 'facility_detail_card.dart';
import 'facility_location_filter_bar.dart';
import 'facility_sort_bar.dart';
import 'sosyal_menu_sheet.dart';

/// Kotlin [MisafirhaneBottomSheet] (arama modu): Tesis / Gezi / Yemek / Sosyal sekmeleri.
/// Ana harita gövdesindeki [Stack] içine yerleştirilir; üstteki toolbar ve arama çubuğu sheet’ten sonra
/// çizilerek her zaman önde kalır.
class MisafirhaneSearchResultsPanel extends ConsumerStatefulWidget {
  const MisafirhaneSearchResultsPanel({
    super.key,
    required this.listVisible,
    required this.topInset,
    required this.onViewModeChanged,
    required this.rotaData,
    required this.mapLocationState,
    this.highlightTarget,
    this.initialTabIndex = 0,
    this.geziYemekHighlight,
    required this.favoritesRepo,
    required this.onFavoritesChanged,
    required this.onTesisSelect,
    this.onRequestLocationPermission,
    required this.onClosePanel,
    this.onSelectIl,
  });

  /// `true`: liste görünümü (harita gizli); `false`: harita görünümü.
  final bool listVisible;

  /// Liste yüzeyinin başladığı üst boşluk (başlık + arama çubuğu + tür filtreleri).
  final double topInset;

  /// Liste / Harita geçişi (`true` = liste).
  final ValueChanged<bool> onViewModeChanged;

  final RotaDataState rotaData;
  final MapLocationState mapLocationState;
  final Misafirhane? highlightTarget;
  final int initialTabIndex;
  final String? geziYemekHighlight;
  final FavoritesRepository favoritesRepo;
  final Future<void> Function() onFavoritesChanged;
  final Future<void> Function(Misafirhane m) onTesisSelect;

  final Future<void> Function()? onRequestLocationPermission;

  /// Detay kartındaki "Haritada göster" sonrası panel kapatılır.
  final VoidCallback onClosePanel;

  /// Filtre çubuğundan il seçilince o il için arama yapılır.
  final ValueChanged<String>? onSelectIl;

  @override
  MisafirhaneSearchResultsPanelState createState() =>
      MisafirhaneSearchResultsPanelState();
}

class MisafirhaneSearchResultsPanelState
    extends ConsumerState<MisafirhaneSearchResultsPanel> {
  int _tabIndex = 0;
  List<Misafirhane> _favorites = const [];

  /// Tesis (misafirhane) satırına tıklanınca açılan detay kartı; null = liste.
  Misafirhane? _detailFacility;

  /// Detay kapanınca liste kaydırma konumunu geri yüklemek için.
  double? _savedListScrollOffset;

  /// Sistem geri tuşu: detay açıksa kapatır ve `true` döner.
  bool closeDetailIfOpen() {
    if (_detailFacility != null) {
      unawaited(_closeFacilityDetail());
      return true;
    }
    return false;
  }

  bool get isDetailOpen => _detailFacility != null;

  /// Dışarıdan (ör. rotalink.tr tesis linki) tesis detayını açar.
  void openFacilityDetail(Misafirhane m) {
    if (!mounted) return;
    unawaited(_openFacilityDetail(m));
  }

  void _rememberListScroll() {
    final scroll = _listScroll;
    if (scroll != null && scroll.hasClients) {
      _savedListScrollOffset = scroll.offset;
    }
  }

  Future<void> _openFacilityDetail(Misafirhane m) async {
    _rememberListScroll();
    setState(() => _detailFacility = m);
    // Haritadan (marker / önizleme) açıldıysa detay liste yüzeyinde gösterilir.
    if (!widget.listVisible) widget.onViewModeChanged(true);
  }

  Future<void> _closeFacilityDetail() async {
    if (_detailFacility == null) return;
    final returnTo = _detailFacility!;
    if (mounted) setState(() => _detailFacility = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_restoreListScrollAfterDetail(returnTo));
    });
  }

  /// Detay kapanınca aynı tesis satırına kaydırır (liste başa sıfırlanmasın).
  Future<void> _restoreListScrollAfterDetail(Misafirhane facility) async {
    for (var i = 0; i < 40; i++) {
      if (_listScroll != null && _listScroll!.hasClients) break;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
    }
    final scroll = _listScroll;
    if (scroll == null || !scroll.hasClients) return;

    final saved = _savedListScrollOffset;
    if (saved != null) {
      final max = scroll.position.maxScrollExtent;
      scroll.jumpTo(saved.clamp(0.0, max));
    }

    await Future<void>.delayed(const Duration(milliseconds: 48));
    if (!mounted) return;

    final rowKey = _keyForFacility(facility);
    var ctx = rowKey.currentContext;
    if (ctx == null) {
      // Lazy list: satır henüz build edilmediyse yaklaşık ofsete git.
      final facilities = ref.read(filteredTesisListProvider);
      final idx = facilities.indexWhere(
        (f) => f.sameFavoriteIdentity(facility),
      );
      if (idx >= 0 && scroll.hasClients) {
        const kTabBarH = _TabBarHeaderDelegate.height;
        const kApproxItemH = 92.0;
        final approx = (kTabBarH + idx * kApproxItemH).clamp(
          0.0,
          scroll.position.maxScrollExtent,
        );
        scroll.jumpTo(approx);
        await Future<void>.delayed(const Duration(milliseconds: 64));
        if (!mounted) return;
        ctx = rowKey.currentContext;
      }
    }
    if (ctx != null && ctx.mounted) {
      try {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.12,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    }
  }

  /// Sabit tam yükseklik liste kaydırma denetleyicisi (harita görünümünde de korunur).
  ScrollController? _listScroll = ScrollController();

  /// İl [ExpansionTile] içindeki satırlar için — vurgu kaydırması.
  final Map<String, GlobalKey> _facilityRowKeys = {};

  /// Kaydırma bittikten sonra sarı ripple (aranan misafirhane).
  Misafirhane? _flashFacility;
  int _flashGen = 0;

  /// Gezi/Yemek vurgu satırları için anahtar.
  final Map<String, GlobalKey> _geziYemekRowKeys = {};

  /// Geocode ile çözülen koordinatlar (gezi/yemek ortak anahtar: isim+il).
  final Map<String, LatLng> _geocodeGeziYemek = {};
  final Set<String> _geocodeMissGeziYemek = {};

  /// Sosyal satırlar için çözülen koordinatlar.
  final Map<String, LatLng> _geocodeSosyal = {};
  final Set<String> _geocodeMissSosyal = {};

  /// Filtre (aranan iller) değişince önceki geocode döngüsünü iptal et.
  /// Sekme değişimi iptal etmez — tüm sekmeler arka planda doldurulur.
  int _geocodeGen = 0;

  String _illlerFingerprint = '';
  bool _prefetchRunning = false;
  int _geocodeErrorRetries = 0;
  int _geocodeMissRetries = 0;

  /// Pro: konaklama listesi fiyata göre (ucuzdan pahalıya) sıralı mı.
  bool _sortByPrice = false;
  BestValueBasis _priceBasis = BestValueBasis.sivil;

  /// Pro: tek kişi / gece fiyatı için üst limit (TL); null ise bütçe filtresi kapalı.
  double? _budgetMax;

  /// Sosyal satırında ilçe satırı (açıklama ayrı gösterilir).
  static String _sosyalIlceLine(SosyalItem s) {
    final ilce = s.ilce.trim();
    final adres = s.adres.trim();
    if (ilce.isNotEmpty) return ilce;
    return adres;
  }

  void _onMapLocationChanged() {
    if (!mounted) return;
    // Konum gelince tüm sekmelerde mesafe anında güncellensin.
    setState(() {});
    unawaited(_prefetchDistancesForAllTabs());
  }

  @override
  void initState() {
    super.initState();
    ProService.instance.isPro.addListener(_onProChanged);
    FacilityCompareSelection.instance.addListener(_onCompareChanged);
    widget.mapLocationState.addListener(_onMapLocationChanged);
    HediyelikRepository.instance.byIl.addListener(_onHediyelikChanged);
    unawaited(HediyelikRepository.instance.ensureLoaded());
    KampRepository.instance.items.addListener(_onKampChanged);
    unawaited(KampRepository.instance.ensureLoaded());
    unawaited(_loadFavorites());
    unawaited(_loadSortPrefs());
    // initState içinde setState çağırmaktan kaçın: sekme doğrudan set et.
    _tabIndex = widget.initialTabIndex;
    if (widget.highlightTarget != null && widget.initialTabIndex == 0) {
      _flashFacility = widget.highlightTarget;
      _flashGen = 1;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Arama açılır açılmaz tüm sekmeler için mesafe hazırlığı.
      unawaited(_prefetchDistancesForAllTabs());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (widget.initialTabIndex == 0) {
            unawaited(_expandSheetAndScrollToHighlight());
          } else {
            unawaited(_expandSheetAndScrollToGeziYemek());
          }
        }
      });
    });
  }

  Future<void> _loadSortPrefs() async {
    final prefs = await FacilitySortPrefs.load();
    if (!mounted) return;
    setState(() {
      _priceBasis = prefs.basis;
      _sortByPrice = prefs.byPrice && PriceAccess.unlocked;
    });
  }

  void _selectDistanceSort() {
    if (!_sortByPrice) return;
    setState(() => _sortByPrice = false);
    unawaited(FacilitySortPrefs.save(byPrice: false, basis: _priceBasis));
  }

  void _selectPriceSort(List<Misafirhane> facilities) {
    if (!PriceAccess.unlocked) {
      unawaited(
        showPriceSortProTeaser(
          context,
          countFacilitiesWithNightPrice(facilities),
        ),
      );
      return;
    }
    if (_sortByPrice) return;
    setState(() => _sortByPrice = true);
    final scroll = _listScroll;
    if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
    unawaited(FacilitySortPrefs.save(byPrice: true, basis: _priceBasis));
  }

  void _selectPriceBasis(BestValueBasis basis) {
    if (basis == _priceBasis) return;
    setState(() => _priceBasis = basis);
    unawaited(FacilitySortPrefs.save(byPrice: _sortByPrice, basis: basis));
  }

  Future<void> _openBudgetPicker(List<Misafirhane> facilities) async {
    if (!PriceAccess.unlocked) {
      unawaited(
        showProFeatureTeaser(
          context,
          icon: Icons.account_balance_wallet_outlined,
          title: FacilityPricing.budgetTeaserTitle,
          headline: FacilityPricing.budgetTeaserCount(
            countFacilitiesWithNightPrice(facilities),
          ),
          perks: FacilityPricing.budgetTeaserPerks,
        ),
      );
      return;
    }
    var basis = _priceBasis;
    var range = nightPriceRange(facilities, basis);
    if (range == null) {
      basis = basis == BestValueBasis.sivil
          ? BestValueBasis.kamu
          : BestValueBasis.sivil;
      range = nightPriceRange(facilities, basis);
    }
    if (range == null) return;
    final picked = await showBudgetPicker(
      context,
      range: range,
      current: _budgetMax,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _budgetMax = picked.isNaN ? null : picked;
      _priceBasis = basis;
    });
    unawaited(FacilitySortPrefs.save(byPrice: _sortByPrice, basis: basis));
    final scroll = _listScroll;
    if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
  }

  void _onCompareChanged() {
    if (mounted) setState(() {});
  }

  Widget? _compareBarSliver() {
    final selected = FacilityCompareSelection.instance.value;
    if (selected.isEmpty || !PriceAccess.unlocked) return null;
    return SliverToBoxAdapter(
      child: FacilityCompareBar(
        selected: selected,
        userLocation: widget.mapLocationState.userLocation,
      ),
    );
  }

  void _clearBudget() {
    if (_budgetMax == null) return;
    setState(() => _budgetMax = null);
  }

  void _onProChanged() {
    if (!mounted) return;
    if (!PriceAccess.unlocked) _budgetMax = null;
    if (_sortByPrice && !PriceAccess.unlocked) {
      setState(() => _sortByPrice = false);
    } else if (!_sortByPrice && PriceAccess.unlocked) {
      unawaited(_loadSortPrefs());
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant MisafirhaneSearchResultsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ho = oldWidget.highlightTarget;
    final hn = widget.highlightTarget;
    final hlChanged =
        (ho == null) != (hn == null) ||
        (ho != null && hn != null && !ho.sameFavoriteIdentity(hn));
    if (hlChanged) {
      if (hn == null) {
        _flashFacility = null;
      } else {
        // Satır görünür olmasa da vurgula; kaydırma bitince yeniden başlar.
        _flashFacility = hn;
        _flashGen++;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_expandSheetAndScrollToHighlight());
      });
    }
  }

  @override
  void dispose() {
    _listScroll?.dispose();
    _listScroll = null;
    ProService.instance.isPro.removeListener(_onProChanged);
    FacilityCompareSelection.instance.removeListener(_onCompareChanged);
    widget.mapLocationState.removeListener(_onMapLocationChanged);
    HediyelikRepository.instance.byIl.removeListener(_onHediyelikChanged);
    KampRepository.instance.items.removeListener(_onKampChanged);
    super.dispose();
  }

  GlobalKey _keyForFacility(Misafirhane m) =>
      _facilityRowKeys.putIfAbsent(m.stableFacilityId, GlobalKey.new);

  /// Gerekirse kademeli scroll; sonra [Scrollable.ensureVisible].
  GlobalKey _keyForGeziYemek(GeziYemekItem g) =>
      _geziYemekRowKeys.putIfAbsent('${g.isim}\x01${g.il}', GlobalKey.new);

  bool _isGeziYemekHighlight(GeziYemekItem g) {
    final hl = widget.geziYemekHighlight;
    if (hl == null) return false;
    return normalizeForSearch(g.isim).contains(normalizeForSearch(hl));
  }

  Future<void> _expandSheetAndScrollToGeziYemek() async {
    final hl = widget.geziYemekHighlight;
    if (hl == null || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    for (var w = 0; w < 50; w++) {
      if (_listScroll != null && _listScroll!.hasClients) break;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final hlNorm = normalizeForSearch(hl);
    final sortedItems = _sortedGezi(
      _tabIndex == 1 ? _geziFiltered : _yemekFiltered,
    );
    GeziYemekItem? target;
    var targetIdx = 0;
    for (var i = 0; i < sortedItems.length; i++) {
      if (normalizeForSearch(sortedItems[i].isim).contains(hlNorm)) {
        target = sortedItems[i];
        targetIdx = i;
        break;
      }
    }
    if (target == null) return;
    final scroll = _listScroll;
    if (scroll == null || !scroll.hasClients) return;
    // SliverChildBuilderDelegate lazy: öğe görünür değilse context null.
    // Önce tahmini ofsete kaydır, sonra kesin konumlandırma yap.
    final rowKey = _keyForGeziYemek(target);
    if (rowKey.currentContext == null) {
      const kTabBarH = _TabBarHeaderDelegate.height;
      const kApproxItemH = 88.0;
      final approx = (kTabBarH + targetIdx * kApproxItemH).clamp(
        0.0,
        scroll.position.maxScrollExtent,
      );
      await scroll.animateTo(
        approx,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
    }
    final ctx = rowKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.04,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _expandSheetAndScrollToHighlight() async {
    if (!mounted || widget.highlightTarget == null || _tabIndex != 0) return;
    final hl = widget.highlightTarget!;
    final rowKey = _keyForFacility(hl);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted || widget.highlightTarget == null || _tabIndex != 0) return;

    for (var w = 0; w < 50; w++) {
      if (_listScroll != null && _listScroll!.hasClients) break;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
    }
    if (_listScroll == null || !_listScroll!.hasClients) return;

    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted || widget.highlightTarget == null || _tabIndex != 0) return;

    Future<void> animateVisible() async {
      final ctx = rowKey.currentContext;
      if (ctx != null && mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.04,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
        );
      }
    }

    await animateVisible();
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!mounted) return;
      if (rowKey.currentContext != null) break;
      if (_listScroll == null || !_listScroll!.hasClients) return;
      final pos = _listScroll!.position;
      final next = (_listScroll!.offset + 160.0).clamp(
        0.0,
        pos.maxScrollExtent,
      );
      if (next <= _listScroll!.offset + 0.5) break;
      _listScroll!.jumpTo(next);
      await Future<void>.delayed(const Duration(milliseconds: 24));
      await animateVisible();
    }

    // Kaydırma bittikten sonra 5 sn sarı ripple — kullanıcı satırı görsün.
    if (!mounted || widget.highlightTarget == null) return;
    if (!widget.highlightTarget!.sameFavoriteIdentity(hl)) return;
    setState(() {
      _flashFacility = hl;
      _flashGen++;
    });
  }

  Future<void> _loadFavorites() async {
    final list = await widget.favoritesRepo.load();
    if (!mounted) return;
    setState(() => _favorites = list);
  }

  Set<String> get _facilityIllerNorm => ref
      .read(searchPanelFacilitiesSourceProvider)
      .map((e) => normalizeForSearch(e.il))
      .where((s) => s.isNotEmpty)
      .toSet();

  List<GeziYemekItem> get _geziFiltered {
    final merged = GeziYemekRepository.instance.mergeWithMaster(
      widget.rotaData.gezi,
      gezi: true,
    );
    final want = _facilityIllerNorm;
    if (want.isEmpty) return merged;
    return merged
        .where((g) => want.contains(normalizeForSearch(g.il)))
        .toList();
  }

  List<GeziYemekItem> get _yemekFiltered {
    final merged = GeziYemekRepository.instance.mergeWithMaster(
      widget.rotaData.yemek,
      gezi: false,
    );
    final want = _facilityIllerNorm;
    if (want.isEmpty) return merged;
    return merged
        .where((g) => want.contains(normalizeForSearch(g.il)))
        .toList();
  }

  void _onHediyelikChanged() {
    if (mounted) setState(() {});
  }

  List<HediyelikItem> get _hediyelikFiltered =>
      HediyelikRepository.instance.forIller(_facilityIllerNorm);

  void _onKampChanged() {
    if (mounted) setState(() {});
  }

  List<KampAlani> get _kampFiltered =>
      KampRepository.instance.forIller(_facilityIllerNorm);

  List<SosyalItem> get _sosyalFiltered {
    final raw = widget.rotaData.sosyal;
    final want = _facilityIllerNorm;
    if (want.isEmpty) return raw;
    return raw.where((s) => want.contains(normalizeForSearch(s.il))).toList();
  }

  final Map<String, String> _inferredIlce = {};

  /// "İlçesi belirsiz" seçimi sekme bazında tutulur: sekme → seçildiği il.
  final Map<int, String> _unknownIlceTabs = {};

  String _ilceOfGezi(GeziYemekItem g) => _inferredIlce.putIfAbsent(
    'g\u0001${g.il}\u0001${g.isim}\u0001${g.adres}',
    () => IlIlce.inferIlce(g.il, adres: g.adres),
  );

  String _ilceOfSosyal(SosyalItem s) => _inferredIlce.putIfAbsent(
    's\u0001${s.il}\u0001${s.ilce}\u0001${s.isim}\u0001${s.adres}',
    () => IlIlce.inferIlce(s.il, ilce: s.ilce, adres: s.adres),
  );

  /// Gezi / sosyal sekmesinde aktif ilçe; null → tüm ilçeler.
  String? _listIlceFor(int tab) {
    final il = ref.watch(searchPanelLocationSummaryProvider).il;
    if (il == null) return null;
    if (_unknownIlceTabs[tab] == il) return kIlceUnknown;
    final sel = ref.watch(facilityIlceFilterProvider);
    return sel != null && IlIlce.sameIl(sel.il, il) ? sel.ilce : null;
  }

  List<T> _byIlce<T>(List<T> items, String? ilce, String Function(T) ilceOf) {
    if (ilce == null) return items;
    final want = ilce == kIlceUnknown ? '' : ilce;
    return items.where((e) => ilceOf(e) == want).toList();
  }

  List<GeziYemekItem> get _geziShown =>
      _byIlce(_geziFiltered, _listIlceFor(1), _ilceOfGezi);

  List<SosyalItem> get _sosyalShown =>
      _byIlce(_sosyalFiltered, _listIlceFor(3), _ilceOfSosyal);

  /// Gerçek ilçe seçimi konaklama sekmesiyle ortaktır; "belirsiz" yalnız o sekmede.
  void _setListIlce(int tab, String il, String? value) {
    setState(() {
      if (value == kIlceUnknown) {
        _unknownIlceTabs[tab] = il;
      } else {
        _unknownIlceTabs.clear();
      }
    });
    ref
        .read(facilityIlceFilterProvider.notifier)
        .state = value == null || value == kIlceUnknown
        ? null
        : IlceSelection(il: il, ilce: value);
  }

  Widget _listLocationBar<T>({
    required int tab,
    required String noun,
    required List<T> inIl,
    required List<T> all,
    required String Function(T) ilOf,
    required String Function(T) ilceOf,
    required int shown,
  }) {
    final il = ref.watch(searchPanelLocationSummaryProvider).il;
    final ilceCounts = <String, int>{};
    var unknown = 0;
    if (il != null) {
      for (final d in IlIlce.ilceleri(il)) {
        ilceCounts[d] = 0;
      }
      for (final e in inIl) {
        final d = ilceOf(e);
        if (d.isEmpty) {
          unknown++;
        } else {
          ilceCounts[d] = (ilceCounts[d] ?? 0) + 1;
        }
      }
    }
    final ilCounts = <String, int>{};
    for (final e in all) {
      final c = IlIlce.canonicalIl(ilOf(e));
      if (c != null) ilCounts[c] = (ilCounts[c] ?? 0) + 1;
    }
    return ListLocationFilterBar(
      il: il,
      ilce: _listIlceFor(tab),
      count: shown,
      noun: noun,
      total: inIl.length,
      ilceCounts: ilceCounts,
      unknownCount: unknown,
      ilCounts: ilCounts,
      onSelectIl: widget.onSelectIl,
      onSelectIlce: (v) {
        if (il != null) _setListIlce(tab, il, v);
      },
    );
  }

  /// İlçe süzgeci boş sonuç verdiyse il geneline dönme düğmeli boş durum.
  Widget _listEmptyState(int tab, String ilMsg, String ilceMsg) {
    final il = ref.watch(searchPanelLocationSummaryProvider).il;
    if (il == null || _listIlceFor(tab) == null) return _emptyTabState(ilMsg);
    return _emptyTabState(
      ilceMsg,
      actionLabel: 'İl genelini göster',
      onAction: () => _setListIlce(tab, il, null),
    );
  }

  String _keyGeziYemek(GeziYemekItem g) => '${g.isim}\u0001${g.il}';

  String _keySosyal(SosyalItem s) => '${s.isim}\u0001${s.il}\u0001${s.ilce}';

  LatLng? _latLngGeziYemek(GeziYemekItem g) {
    if (g.enlem != null && g.boylam != null) {
      if (!isValidWgs84LatLng(g.enlem!, g.boylam!)) return null;
      return LatLng(g.enlem!, g.boylam!);
    }
    final cached = _geocodeGeziYemek[_keyGeziYemek(g)];
    if (cached == null) return null;
    if (!isValidWgs84LatLng(cached.latitude, cached.longitude)) return null;
    return cached;
  }

  LatLng? _latLngSosyal(SosyalItem s) {
    if (s.enlem != null && s.boylam != null) {
      if (!isValidWgs84LatLng(s.enlem!, s.boylam!)) return null;
      return LatLng(s.enlem!, s.boylam!);
    }
    final cached = _geocodeSosyal[_keySosyal(s)];
    if (cached == null) return null;
    if (!isValidWgs84LatLng(cached.latitude, cached.longitude)) return null;
    return cached;
  }

  double _distanceMetersToUser(LatLng? point) {
    final u = widget.mapLocationState.userLocation;
    if (u == null || point == null) return double.infinity;
    final m = distanceMetersBetween(u, point);
    return m ?? double.infinity;
  }

  List<GeziYemekItem> _sortedGezi(List<GeziYemekItem> list) {
    final u = widget.mapLocationState.userLocation;
    if (u == null || !isValidWgs84LatLng(u.latitude, u.longitude)) {
      return List<GeziYemekItem>.from(list);
    }
    final keyed = <({GeziYemekItem g, double d})>[];
    for (final g in list) {
      keyed.add((g: g, d: _distanceMetersToUser(_latLngGeziYemek(g))));
    }
    keyed.sort((a, b) => a.d.compareTo(b.d));
    return [for (final e in keyed) e.g];
  }

  List<SosyalItem> _sortedSosyal(List<SosyalItem> list) {
    final u = widget.mapLocationState.userLocation;
    if (u == null || !isValidWgs84LatLng(u.latitude, u.longitude)) {
      return List<SosyalItem>.from(list);
    }
    final keyed = <({SosyalItem s, double d})>[];
    for (final s in list) {
      keyed.add((s: s, d: _distanceMetersToUser(_latLngSosyal(s))));
    }
    keyed.sort((a, b) => a.d.compareTo(b.d));
    return [for (final e in keyed) e.s];
  }

  void _onTabChanged(int index) {
    setState(() {
      _tabIndex = index;
      _detailFacility = null;
    });
    // Kategori değişince kaydırma başa döner; harita görünümündeysek listeye geç.
    final scroll = _listScroll;
    if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
    if (!widget.listVisible) widget.onViewModeChanged(true);
    if (index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_expandSheetAndScrollToHighlight());
      });
    }
    // Mesafe: sekme beklemeden zaten prefetch çalışıyor; yine de hatırlat.
    unawaited(_prefetchDistancesForAllTabs());
  }

  /// İl araması açılınca Gezi / Yemek / Sosyal mesafelerini hazırla.
  Future<void> _prefetchDistancesForAllTabs() async {
    if (!mounted) return;
    final fp = _facilityIllerNorm.toList()..sort();
    final fingerprint = fp.join('|');
    final filterChanged = fingerprint != _illlerFingerprint;
    if (filterChanged) {
      _illlerFingerprint = fingerprint;
      _geocodeGen++;
      _geocodeMissGeziYemek.clear();
      _geocodeMissSosyal.clear();
      _geocodeErrorRetries = 0;
      _geocodeMissRetries = 0;
    } else if (_prefetchRunning) {
      return;
    }
    final gen = _geocodeGen;
    _prefetchRunning = true;

    // Gezi + Tesisler (belediye/sosyal) mesafe; yemek yok; konaklama kendi lat/lng.
    if (mounted) setState(() {});

    try {
      // Önce açık sekme — kullanıcı bekleyen satırları önce görsün.
      Future<void> gezi() => _hydrateGeziYemekCoords(_geziFiltered, gen: gen);
      // Yemek: mesafe yok → geocode yok. Konaklama: dokunulmaz.
      Future<void> sosyal() => _hydrateSosyalCoords(gen: gen);

      final ordered = switch (_tabIndex) {
        1 => [gezi, sosyal],
        3 => [sosyal, gezi],
        _ => [gezi, sosyal],
      };

      for (final step in ordered) {
        if (!mounted || gen != _geocodeGen) return;
        await step();
      }
    } finally {
      if (gen == _geocodeGen) {
        _prefetchRunning = false;
        // Ağ hatası veya henüz çözülemeyen satırlar: arka planda tekrar dene.
        final unresolvedGezi = _geziFiltered.any((g) {
          if (g.enlem != null && g.boylam != null) return false;
          return !_geocodeGeziYemek.containsKey(_keyGeziYemek(g));
        });
        final unresolvedSosyal = _sosyalFiltered.any((s) {
          if (s.enlem != null && s.boylam != null) return false;
          return !_geocodeSosyal.containsKey(_keySosyal(s));
        });
        if ((unresolvedGezi || unresolvedSosyal) && mounted) {
          final hadOnlyErrors =
              _geziFiltered.any((g) {
                if (g.enlem != null && g.boylam != null) return false;
                final k = _keyGeziYemek(g);
                return !_geocodeGeziYemek.containsKey(k) &&
                    !_geocodeMissGeziYemek.contains(k);
              }) ||
              _sosyalFiltered.any((s) {
                if (s.enlem != null && s.boylam != null) return false;
                final k = _keySosyal(s);
                return !_geocodeSosyal.containsKey(k) &&
                    !_geocodeMissSosyal.contains(k);
              });

          if (hadOnlyErrors && _geocodeErrorRetries < 4) {
            _geocodeErrorRetries++;
            Future<void>.delayed(
              Duration(seconds: 2 * _geocodeErrorRetries),
              () {
                if (!mounted || gen != _geocodeGen) return;
                unawaited(_prefetchDistancesForAllTabs());
              },
            );
          } else if (_geocodeMissRetries < 12) {
            // Miss: "bulunamadı" gösterme — TTL dolunca haritada yeniden ara.
            _geocodeMissRetries++;
            Future<void>.delayed(const Duration(seconds: 45), () {
              if (!mounted || gen != _geocodeGen) return;
              NominatimGeocodeCache.clearExpiredMisses();
              _geocodeMissGeziYemek.clear();
              _geocodeMissSosyal.clear();
              unawaited(_prefetchDistancesForAllTabs());
            });
          }
        }
      }
    }
  }

  String _geocodeQueryGeziYemek(GeziYemekItem g, {int attempt = 0}) {
    final isim = g.isim.trim();
    final il = g.il.trim();
    final adres = g.adres.trim();
    // Photon virgülsüz sorguyu daha iyi çözer; il her zaman eklenir.
    // Tekrar denemelerde sadeleştirilmiş sorgu dene.
    if (attempt > 0) {
      return '$isim $il Türkiye';
    }
    if (adres.isNotEmpty &&
        adres.toLowerCase() != il.toLowerCase() &&
        !adres.toLowerCase().contains('tüm') &&
        adres.length < 60) {
      return '$isim $adres $il Türkiye';
    }
    return '$isim $il Türkiye';
  }

  String _geocodeQuerySosyal(SosyalItem s, {int attempt = 0}) {
    final isim = s.isim.trim();
    final il = s.il.trim();
    final ilce = s.ilce.trim();
    if (attempt > 0 || ilce.isEmpty) {
      return '$isim $il Türkiye';
    }
    return '$isim $ilce $il Türkiye';
  }

  Future<void> _hydrateGeziYemekCoords(
    List<GeziYemekItem> items, {
    required int gen,
  }) async {
    // Photon paralel tolere eder; 3'lü gruplar.
    const chunk = 3;
    var resolved = 0;
    final need = <GeziYemekItem>[];
    for (final g in items) {
      if (g.enlem != null && g.boylam != null) continue;
      final key = _keyGeziYemek(g);
      if (_geocodeGeziYemek.containsKey(key) ||
          _geocodeMissGeziYemek.contains(key)) {
        continue;
      }
      need.add(g);
    }

    for (var i = 0; i < need.length; i += chunk) {
      if (!mounted || gen != _geocodeGen) return;
      final slice = need.sublist(i, math.min(i + chunk, need.length));
      final results = await Future.wait(
        slice.map((g) async {
          final key = _keyGeziYemek(g);
          var o = await NominatimGeocodeCache.searchDetailed(
            _geocodeQueryGeziYemek(g),
          );
          if (o.status == GeocodeStatus.miss) {
            final alt = _geocodeQueryGeziYemek(g, attempt: 1);
            if (alt != _geocodeQueryGeziYemek(g)) {
              o = await NominatimGeocodeCache.searchDetailed(alt);
            }
          }
          return (key: key, outcome: o);
        }),
      );
      if (!mounted || gen != _geocodeGen) return;
      var changed = false;
      for (final r in results) {
        switch (r.outcome.status) {
          case GeocodeStatus.hit:
            _geocodeGeziYemek[r.key] = r.outcome.point!;
            _geocodeMissGeziYemek.remove(r.key);
            resolved++;
            changed = true;
          case GeocodeStatus.miss:
            _geocodeMissGeziYemek.add(r.key);
            changed = true;
          case GeocodeStatus.error:
            // Sonra tekrar dene; UI'da "Mesafe hesaplanıyor" kalsın.
            break;
        }
      }
      if (changed && mounted) setState(() {});
    }
    if (mounted && resolved > 0) setState(() {});
  }

  Future<void> _hydrateSosyalCoords({required int gen}) async {
    const chunk = 3;
    var resolved = 0;
    final need = <SosyalItem>[];
    for (final s in _sosyalFiltered) {
      if (s.enlem != null && s.boylam != null) continue;
      final key = _keySosyal(s);
      if (_geocodeSosyal.containsKey(key) || _geocodeMissSosyal.contains(key)) {
        continue;
      }
      need.add(s);
    }

    for (var i = 0; i < need.length; i += chunk) {
      if (!mounted || gen != _geocodeGen) return;
      final slice = need.sublist(i, math.min(i + chunk, need.length));
      final results = await Future.wait(
        slice.map((s) async {
          final key = _keySosyal(s);
          var o = await NominatimGeocodeCache.searchDetailed(
            _geocodeQuerySosyal(s),
          );
          if (o.status == GeocodeStatus.miss) {
            final alt = _geocodeQuerySosyal(s, attempt: 1);
            if (alt != _geocodeQuerySosyal(s)) {
              o = await NominatimGeocodeCache.searchDetailed(alt);
            }
          }
          return (key: key, outcome: o);
        }),
      );
      if (!mounted || gen != _geocodeGen) return;
      var changed = false;
      for (final r in results) {
        switch (r.outcome.status) {
          case GeocodeStatus.hit:
            _geocodeSosyal[r.key] = r.outcome.point!;
            _geocodeMissSosyal.remove(r.key);
            resolved++;
            changed = true;
          case GeocodeStatus.miss:
            _geocodeMissSosyal.add(r.key);
            changed = true;
          case GeocodeStatus.error:
            break;
        }
      }
      if (changed && mounted) setState(() {});
    }
    if (mounted && resolved > 0) setState(() {});
  }

  Future<void> _toggleFavorite(Misafirhane m) async {
    final wasFav = _favorites.any((f) => f.sameFavoriteIdentity(m));
    await widget.favoritesRepo.toggle(m);
    await widget.onFavoritesChanged();
    await _loadFavorites();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasFav ? 'Favorilerden çıkarıldı' : 'Favorilere eklendi'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _dialPhone(BuildContext ctx, String phone) async {
    final p = phone.trim();
    if (p.isEmpty) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(const SnackBar(content: Text('Telefon numarası yok')));
      return;
    }
    final uri = Uri(scheme: 'tel', path: p.replaceAll(RegExp(r'\s'), ''));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(const SnackBar(content: Text('Arama başlatılamadı')));
      }
    }
  }

  Future<void> _shareMisafirhane(Misafirhane m) async {
    final phone = m.telefon.trim();
    await Share.share(
      StoreLinks.shareMessage(m.isim, [
        if (phone.isNotEmpty) 'Telefon: $phone',
      ]),
    );
  }

  Future<void> _openGoogleImages(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final uri = Uri.parse(
      'https://www.google.com/search?tbm=isch&q=${Uri.encodeComponent(q)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareGeziYemek(GeziYemekItem g) async {
    await Share.share(
      StoreLinks.shareMessage(g.isim.trim(), [
        if (g.aciklama.trim().isNotEmpty) g.aciklama.trim(),
      ]),
    );
  }

  Future<void> _shareSosyal(SosyalItem s) async {
    await Share.share(
      StoreLinks.shareMessage(s.isim.trim(), [
        _sosyalIlceLine(s),
        s.aciklama.trim(),
      ]),
    );
  }

  SliverToBoxAdapter _listBottomInset(BuildContext context) {
    // Liste gövdesi alt menünün üstünde biter; yalnızca küçük nefes payı.
    return const SliverToBoxAdapter(child: SizedBox(height: 16));
  }

  @override
  Widget build(BuildContext context) {
    final tesisFacilities = ref.watch(filteredTesisListProvider);
    ref.listen<List<Misafirhane>>(filteredTesisListProvider, (prev, next) {
      if (prev == null || prev.length != next.length) {
        _facilityRowKeys.clear();
      }
      unawaited(_prefetchDistancesForAllTabs());
    });

    return ListenableBuilder(
      listenable: widget.mapLocationState,
      builder: (context, _) {
        // Modal route klavye viewInsets ile her karede yeniden boyanıyordu; sıfırlayıp takılmayı azalt.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(viewInsets: EdgeInsets.zero),
          child: Builder(
            builder: (context) {
              final scrollController = _listScroll!;
              final detail = _detailFacility;
              final counts = <int>[
                tesisFacilities.length,
                _geziShown.length,
                _yemekFiltered.length,
                _sosyalShown.length,
                _hediyelikFiltered.length,
                _kampFiltered.length,
              ];
              final showViewBar =
                  detail == null && _tabIndex != _TabBarHeaderDelegate.kampTab;
              final viewBar = _ViewModeBar(
                showList: widget.listVisible,
                tabIndex: _tabIndex,
                counts: counts,
                onViewModeChanged: widget.onViewModeChanged,
                onTabChanged: _onTabChanged,
              );
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Liste görünümü: harita gizli, tam yükseklik. Harita görünümünde
                  // Offstage ile durum (sekme, kaydırma, filtre) korunur.
                  Offstage(
                    offstage: !widget.listVisible,
                    child: TickerMode(
                      enabled: widget.listVisible,
                      child: SizedBox.expand(
                        child: ColoredBox(
                          // Üst alan (arama + filtre + başlık + sekmeler) hafif turkuaz
                          // tonlu yüzey: beyaz arama kutusu ve beyaz kartlar ayrışır.
                          color: AraUi.chromeFillOf(context),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: widget.topInset),
                              if (showViewBar) viewBar,
                              Expanded(
                                child: Material(
                                  color: detail != null
                                      ? AppColors.surfaceOf(context)
                                      : AraUi.pageOf(context),
                                  clipBehavior: Clip.hardEdge,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 280),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) {
                                      final offset = Tween<Offset>(
                                        begin: const Offset(0.08, 0),
                                        end: Offset.zero,
                                      ).animate(animation);
                                      return FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: offset,
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: detail != null
                                        ? KeyedSubtree(
                                            key: ValueKey<String>(
                                              'detail-${detail.stableFacilityId}',
                                            ),
                                            child: FacilityDetailCard(
                                              misafirhane: detail,
                                              mapLocationState:
                                                  widget.mapLocationState,
                                              isFavorite: _favorites.any(
                                                (f) => f.sameFavoriteIdentity(
                                                  detail,
                                                ),
                                              ),
                                              onBack: () => unawaited(
                                                _closeFacilityDetail(),
                                              ),
                                              onCall: () => _dialPhone(
                                                context,
                                                detail.telefon,
                                              ),
                                              onShare: () => unawaited(
                                                _shareMisafirhane(detail),
                                              ),
                                              onFavorite: () => unawaited(
                                                _toggleFavorite(detail),
                                              ),
                                              onInspect: () => unawaited(
                                                openMapSearch(
                                                  context,
                                                  detail.il,
                                                  detail.isim,
                                                ),
                                              ),
                                              onReview: () => unawaited(
                                                pushOnShellNavigator<void>(
                                                  MaterialPageRoute<void>(
                                                    builder: (_) => YorumScreen(
                                                      facilityId:
                                                          ReviewRepository.sanitizeFacilityId(
                                                            detail
                                                                .stableFacilityId,
                                                          ),
                                                      facilityName: detail.isim,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              onShowOnMap: () => unawaited(
                                                openMapSearch(
                                                  context,
                                                  detail.il,
                                                  detail.isim,
                                                ),
                                              ),
                                              onRequestLocation:
                                                  widget
                                                      .onRequestLocationPermission ??
                                                  () async {},
                                            ),
                                          )
                                        : KeyedSubtree(
                                            key: const ValueKey<String>('list'),
                                            child: CustomScrollView(
                                              controller: scrollController,
                                              physics:
                                                  const ClampingScrollPhysics(),
                                              slivers: [
                                                SliverPersistentHeader(
                                                  pinned: true,
                                                  delegate:
                                                      _TabBarHeaderDelegate(
                                                        tabIndex: _tabIndex,
                                                        onTabChanged:
                                                            _onTabChanged,
                                                        counts: counts,
                                                      ),
                                                ),
                                                ..._tabSlivers(context),
                                              ],
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Harita görünümü: başlık/arama altında kompakt Liste/Harita çubuğu.
                  if (!widget.listVisible && showViewBar)
                    Positioned(
                      top: widget.topInset + 6,
                      left: 10,
                      right: 10,
                      child: Material(
                        elevation: 3,
                        shadowColor: Colors.black26,
                        borderRadius: BorderRadius.circular(14),
                        color: AppColors.surfaceOf(context),
                        clipBehavior: Clip.antiAlias,
                        child: viewBar,
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _tabSlivers(BuildContext context) {
    switch (_tabIndex) {
      case 0:
        return _tesisTabSlivers(context, ref.watch(filteredTesisListProvider));
      case 1:
        return _geziTabSlivers(context, _sortedGezi(_geziShown));
      case 2:
        return _yemekTabSlivers(context, _yemekFiltered);
      case 3:
        return _sosyalTabSlivers(context, _sortedSosyal(_sosyalShown));
      case _TabBarHeaderDelegate.hediyelikTab:
        return _hediyelikTabSlivers(context, _hediyelikFiltered);
      case _TabBarHeaderDelegate.kampTab:
        return [
          SliverFillRemaining(
            child: KampRotalariBody(iller: _facilityIllerNorm),
          ),
        ];
      default:
        return const [];
    }
  }

  List<Widget> _tesisTabSlivers(
    BuildContext context,
    List<Misafirhane> facilities,
  ) {
    final locationBar = SliverToBoxAdapter(
      child: FacilityLocationFilterBar(
        allFacilities: MainMapSearch.tesisKaynagiArama(
          aramaIcinTumTesisler: widget.rotaData.aramaIcinTumTesisler,
          misafirhaneler: widget.rotaData.misafirhaneler,
        ),
        onSelectIl: widget.onSelectIl,
      ),
    );
    if (facilities.isEmpty) {
      final ilceActive = ref.watch(facilityIlceFilterProvider) != null;
      final typeActive =
          ref.watch(facilityTypeFilterProvider) != kFacilityFilterAll;
      final Widget empty;
      if (ilceActive) {
        empty = _emptyTabState(
          typeActive
              ? 'Bu ilçede seçili türde kamu konaklama tesisi bulunamadı.'
              : 'Bu ilçede kayıtlı kamu konaklama tesisi bulunamadı.',
          actionLabel: 'İl genelindeki tesisleri göster',
          onAction: () =>
              ref.read(facilityIlceFilterProvider.notifier).state = null,
        );
      } else if (typeActive) {
        empty = _emptyTabState(
          'Bu ilde seçili türde kamu konaklama tesisi bulunamadı.',
          actionLabel: 'Tüm tesis türlerini göster',
          onAction: () => ref.read(facilityTypeFilterProvider.notifier).state =
              kFacilityFilterAll,
        );
      } else {
        empty = _emptyTabState('Bu aramada konaklama kaydı yok');
      }
      return [
        locationBar,
        _kListGap,
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: empty,
          ),
        ),
      ];
    }

    final hasAnyPrice = countFacilitiesWithNightPrice(facilities) > 0;
    final unlocked = PriceAccess.unlocked;
    final byPrice = _sortByPrice && unlocked && hasAnyPrice;
    final budget = unlocked && hasAnyPrice ? _budgetMax : null;
    final sortBar = hasAnyPrice
        ? SliverToBoxAdapter(
            child: FacilitySortBar(
              byPrice: byPrice,
              basis: _priceBasis,
              unlocked: unlocked,
              onSelectDistance: _selectDistanceSort,
              onSelectPrice: () => _selectPriceSort(facilities),
              onBasisChanged: _selectPriceBasis,
              budgetMax: budget,
              onBudgetTap: () => unawaited(_openBudgetPicker(facilities)),
              onBudgetClear: _clearBudget,
            ),
          )
        : null;
    final compareBar = _compareBarSliver();

    if (byPrice || budget != null) {
      final split = splitFacilitiesByPrice(
        facilities,
        _priceBasis,
        sortByPrice: byPrice,
        maxAmount: budget,
      );
      final priced = split.priced;
      final unpriced = split.unpriced;
      return [
        locationBar,
        _kListGap,
        ?sortBar,
        ?compareBar,
        if (budget != null && (split.overBudget > 0 || priced.isEmpty))
          SliverToBoxAdapter(
            child: FacilityBudgetInfo(
              hidden: split.overBudget,
              noneFits: priced.isEmpty,
            ),
          ),
        SliverList(
          delegate: SliverChildBuilderDelegate((ctx, index) {
            if (index.isOdd) return _kListDivider;
            final e = priced[index ~/ 2];
            return _tesisFacilityRow(context, e.$1, price: e.$2);
          }, childCount: priced.isEmpty ? 0 : priced.length * 2 - 1),
        ),
        if (unpriced.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: FacilityUnpricedHeader(count: unpriced.length),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((ctx, index) {
              if (index.isOdd) return _kListDivider;
              return _tesisFacilityRow(context, unpriced[index ~/ 2]);
            }, childCount: unpriced.length * 2 - 1),
          ),
        ],
        _listBottomInset(context),
      ];
    }

    final n = facilities.length;
    final childCount = n * 2 - 1;
    final bestValue = pickBestValueFacility(facilities);
    return [
      locationBar,
      _kListGap,
      ?sortBar,
      ?compareBar,
      if (bestValue != null)
        SliverToBoxAdapter(
          child: BestValueProCard(
            key: ValueKey<String>(
              'best-${bestValue.facility.stableFacilityId}',
            ),
            pick: bestValue,
            onOpenFacility: () =>
                unawaited(_openFacilityDetail(bestValue.facility)),
          ),
        ),
      SliverList(
        delegate: SliverChildBuilderDelegate((ctx, index) {
          if (index.isOdd) return _kListDivider;
          final i = index ~/ 2;
          return _tesisFacilityRow(context, facilities[i]);
        }, childCount: childCount),
      ),
      _listBottomInset(context),
    ];
  }

  Widget _tesisFacilityRow(
    BuildContext context,
    Misafirhane m, {
    FacilityNightPrice? price,
  }) {
    final resolved = FacilityAddressRepository.instance.resolveFacility(m);
    final flash =
        _flashFacility != null && m.sameFavoriteIdentity(_flashFacility!);
    final konum = IlIlce.label(resolved.il, resolved.ilce);
    final row = _searchListTile(
      icon: Icons.hotel_rounded,
      title: resolved.isim,
      showFiyatBilgisi:
          FacilityPriceRepository.instance.lookup(m.il, m.isim)?.hasFiyatBilgisi ==
              true,
      subtitle: konum.isEmpty ? null : konum,
      distance: DistancePermissionChip(
        userLocation: widget.mapLocationState.userLocation,
        locationPermissionGranted:
            widget.mapLocationState.locationPermissionGranted,
        facilityPoint: LatLng(m.latitude, m.longitude),
        onRequestLocation: widget.onRequestLocationPermission ?? () async {},
        spacingAbove: 8,
        fullWidthSingleLine: true,
      ),
      footer: ViewCountLabel(
        viewId: ViewCounterService.keyFor(ViewCategory.konaklama, m.il, m.isim),
      ),
      onTap: () => unawaited(_openFacilityDetail(m)),
      trailingCue: price != null ? FacilityNightPriceTag(price: price) : null,
    );
    final wrapped = flash
        ? _SearchHighlightFlash(
            key: ValueKey<String>('hl-$_flashGen-${m.stableFacilityId}'),
            child: row,
          )
        : row;
    return KeyedSubtree(key: _keyForFacility(m), child: wrapped);
  }

  Widget _geziYemekCompactRow(
    BuildContext context,
    GeziYemekItem g, {
    required bool isGezi,
  }) {
    final ll = isGezi ? _latLngGeziYemek(g) : null;
    final isHl = _isGeziYemekHighlight(g);
    // Ayrı ilçe alanı yok; adres çoğu kayıtta ilçe / mahalle bilgisi taşır.
    final locationLine = () {
      final adres = g.adres.trim();
      if (adres.isNotEmpty) return adres;
      return g.il.trim();
    }();
    final aciklama = g.aciklama.trim();
    final mapsQuery = '${g.il} ${g.isim}'.trim();
    final row = _rowCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _categoryIcon(
                  isGezi ? Icons.landscape_rounded : Icons.restaurant_rounded,
                  isGezi ? AraUi.gezi : AraUi.yemek,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.isim,
                        style: TextStyle(
                          color: AppColors.textStrongOf(context),
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (locationLine.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          locationLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMutedOf(context),
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (aciklama.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                aciklama,
                softWrap: true,
                style: TextStyle(
                  color: AppColors.textMutedOf(context),
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
            if (isGezi)
              DistancePermissionChip(
                userLocation: widget.mapLocationState.userLocation,
                locationPermissionGranted:
                    widget.mapLocationState.locationPermissionGranted,
                facilityPoint: ll,
                onRequestLocation:
                    widget.onRequestLocationPermission ?? () async {},
                spacingAbove: 10,
                fullWidthSingleLine: true,
              ),
            const SizedBox(height: 12),
            AraActionRow(
              children: [
                _sosyalActionChip(
                  icon: Icons.map_outlined,
                  label: 'Harita',
                  primary: isGezi,
                  onTap: () => unawaited(openMapSearch(context, g.il, g.isim)),
                ),
                if (!isGezi)
                  _sosyalActionChip(
                    icon: Icons.image_search,
                    label: 'Fotoğraf',
                    primary: true,
                    onTap: () {
                      if (mapsQuery.isEmpty) return;
                      unawaited(_openGoogleImages(mapsQuery));
                    },
                  ),
                _sosyalActionChip(
                  icon: Icons.ios_share_rounded,
                  label: 'Paylaş',
                  onTap: () => unawaited(_shareGeziYemek(g)),
                ),
                _sosyalActionChip(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Yorum',
                  onTap: () => unawaited(
                    pushOnShellNavigator<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => YorumScreen(
                          facilityId: ReviewRepository.sanitizeFacilityId(
                            '${isGezi ? 'gezi' : 'yemek'}_${g.il}\u0001${g.isim}',
                          ),
                          facilityName: g.isim,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final wrapped = isHl ? _SearchHighlightFlash(child: row) : row;
    return KeyedSubtree(key: _keyForGeziYemek(g), child: wrapped);
  }

  /// Ortak arama listesi satırı — ikon + başlık + alt metin + mesafe.
  Widget _searchListTile({
    required IconData icon,
    required String title,
    bool showFiyatBilgisi = false,
    String? subtitle,
    Widget? distance,
    Widget? footer,
    required VoidCallback onTap,
    List<Widget> trailingActions = const [],
    Widget? trailingCue,
  }) {
    return _rowCard(
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primary.withValues(alpha: 0.06),
        highlightColor: AppColors.primary.withValues(alpha: 0.03),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _categoryIcon(icon, AraUi.stay),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textStrongOf(context),
                              fontSize: 16,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (showFiyatBilgisi) ...[
                          const SizedBox(width: 8),
                          const _UcretBilgisiLabel(),
                        ],
                      ],
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textMutedOf(context),
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (distance != null) distance,
                    ?footer,
                  ],
                ),
              ),
              ...trailingActions,
              trailingCue ??
                  Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: AppColors.textMutedOf(context),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kartlar arası boşluk (zemin [AraUi.pageOf(context)] görünür).
  static const _kListDivider = SizedBox(height: 10);
  static const _kListGap = SliverToBoxAdapter(child: SizedBox(height: 10));

  /// Liste satırı kartı: beyaz yüzey + ince çerçeve + yuvarlak köşe; canvas üzerinde ayrışır.
  Widget _rowCard({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: AppColors.surfaceOf(context),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AraUi.cardBorderOf(context)),
        ),
        child: child,
      ),
    );
  }

  List<Widget> _geziTabSlivers(
    BuildContext context,
    List<GeziYemekItem> items,
  ) {
    final locationBar = SliverToBoxAdapter(
      child: _listLocationBar<GeziYemekItem>(
        tab: 1,
        noun: 'yer',
        inIl: _geziFiltered,
        all: GeziYemekRepository.instance.mergeWithMaster(
          widget.rotaData.gezi,
          gezi: true,
        ),
        ilOf: (g) => g.il,
        ilceOf: _ilceOfGezi,
        shown: items.length,
      ),
    );
    if (items.isEmpty) {
      return [
        locationBar,
        _kListGap,
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: _listEmptyState(
              1,
              'Bu ilde gezi kaydı yok',
              'Bu seçimde gezilecek yer kaydı yok',
            ),
          ),
        ),
      ];
    }
    return [
      locationBar,
      _kListGap,
      SliverList(
        delegate: SliverChildBuilderDelegate((ctx, index) {
          if (index.isOdd) return _kListDivider;
          return _geziYemekCompactRow(context, items[index ~/ 2], isGezi: true);
        }, childCount: items.length * 2 - 1),
      ),
      _listBottomInset(context),
    ];
  }

  List<Widget> _yemekTabSlivers(
    BuildContext context,
    List<GeziYemekItem> items,
  ) {
    if (items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: _emptyTabState('Bu ilde yemek kaydı yok'),
          ),
        ),
      ];
    }
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate((ctx, index) {
          if (index.isOdd) return _kListDivider;
          return _geziYemekCompactRow(
            context,
            items[index ~/ 2],
            isGezi: false,
          );
        }, childCount: items.length * 2 - 1),
      ),
      _listBottomInset(context),
    ];
  }

  List<Widget> _hediyelikTabSlivers(
    BuildContext context,
    List<HediyelikItem> items,
  ) {
    if (items.isEmpty) {
      final loaded = HediyelikRepository.instance.byIl.value.isNotEmpty;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: _emptyTabState(
              loaded
                  ? 'Bu il için hediyelik kaydı yok'
                  : 'Hediyelik listesi yüklenemedi. İnternet bağlantınızı kontrol edin.',
            ),
          ),
        ),
      ];
    }
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate((ctx, index) {
          if (index.isOdd) return _kListDivider;
          return _hediyelikRow(context, items[index ~/ 2]);
        }, childCount: items.length * 2 - 1),
      ),
      _listBottomInset(context),
    ];
  }

  static IconData _hediyelikIcon(String kategori) {
    final k = kategori.toLowerCase();
    if (k.contains('el sanat')) return Icons.palette_outlined;
    if (k.contains('tatlı')) return Icons.cake_outlined;
    if (k.contains('bal') || k.contains('peynir'))
      return Icons.egg_alt_outlined;
    if (k.contains('meyve')) return Icons.eco_outlined;
    if (k.contains('yağ') || k.contains('baharat')) return Icons.spa_outlined;
    if (k.contains('içecek')) return Icons.local_cafe_outlined;
    return Icons.card_giftcard_rounded;
  }

  Future<void> _shareHediyelik(HediyelikItem h) async {
    await Share.share(
      StoreLinks.shareMessage(h.ad, [
        h.il.trim(),
        h.aciklama.trim(),
      ]),
    );
  }

  Widget _hediyelikRow(BuildContext context, HediyelikItem h) {
    final meta = [h.il, if (h.kategori.isNotEmpty) h.kategori].join(' · ');
    return _rowCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _categoryIcon(_hediyelikIcon(h.kategori), AraUi.hediyelik),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.ad,
                        style: TextStyle(
                          color: AppColors.textStrongOf(context),
                          fontSize: 15,
                          height: 1.28,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6B7C82),
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (h.cografiIsaret) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_outlined,
                                size: 12,
                                color: Color(0xFF2E7D32),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Coğrafi işaretli',
                                style: TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (h.aciklama.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                h.aciklama,
                softWrap: true,
                style: const TextStyle(
                  color: Color(0xFF455A64),
                  fontSize: 13,
                  height: 1.45,
                  letterSpacing: -0.05,
                ),
              ),
            ],
            const SizedBox(height: 12),
            AraActionRow(
              children: [
                _sosyalActionChip(
                  icon: Icons.image_search,
                  label: 'Fotoğraf',
                  primary: true,
                  onTap: () => unawaited(_openGoogleImages('${h.ad} ${h.il}')),
                ),
                _sosyalActionChip(
                  icon: Icons.ios_share_rounded,
                  label: 'Paylaş',
                  onTap: () => unawaited(_shareHediyelik(h)),
                ),
                _sosyalActionChip(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Yorum',
                  onTap: () => unawaited(
                    pushOnShellNavigator<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => YorumScreen(
                          facilityId: ReviewRepository.sanitizeFacilityId(
                            'hediyelik_${h.il}\u0001${h.ad}',
                          ),
                          facilityName: h.ad,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyTabState(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5F6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 26,
                color: Color(0xFF9AABB0),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6B7C82),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
                letterSpacing: -0.1,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Kart eylemi. [primary]: karttaki ana eylem (açık turkuaz yüzey, güçlü yazı);
  /// diğerleri beyaz yüzey + ince çerçeve (ikincil).
  Widget _sosyalActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return AraActionButton(
      icon: icon,
      label: label,
      onTap: onTap,
      primary: primary,
    );
  }

  Widget _sosyalFacilityRow(BuildContext context, SosyalItem s) {
    final ilce = _sosyalIlceLine(s);
    final aciklama = s.aciklama.trim();
    final ll = _latLngSosyal(s);
    final menu = SosyalMenuRepository.instance.lookup(s.il, s.isim);
    return _rowCard(
      child: InkWell(
        onTap: () => unawaited(openMapSearch(context, s.il, s.isim)),
        splashColor: AppColors.primary.withValues(alpha: 0.06),
        highlightColor: AppColors.primary.withValues(alpha: 0.03),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _categoryIcon(Icons.apartment_rounded, AraUi.tesis),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.isim,
                          style: TextStyle(
                            color: AppColors.textStrongOf(context),
                            fontSize: 15,
                            height: 1.28,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (ilce.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            ilce,
                            style: const TextStyle(
                              color: Color(0xFF6B7C82),
                              fontSize: 12.5,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (aciklama.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  aciklama,
                  softWrap: true,
                  style: const TextStyle(
                    color: Color(0xFF455A64),
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.05,
                  ),
                ),
              ],
              DistancePermissionChip(
                userLocation: widget.mapLocationState.userLocation,
                locationPermissionGranted:
                    widget.mapLocationState.locationPermissionGranted,
                facilityPoint: ll,
                onRequestLocation:
                    widget.onRequestLocationPermission ?? () async {},
                spacingAbove: 10,
                fullWidthSingleLine: true,
              ),
              if (menu != null) ...[
                const SizedBox(height: 10),
                Text(
                  '${menu.tesisMenusu ? 'Menü' : 'Belediye tarifesi'}: '
                  '${menu.urunSayisi} ürün · ${sosyalMenuKaynakSatiri(menu)}',
                  style: const TextStyle(
                    color: Color(0xFF6B7C82),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              AraActionRow(
                children: [
                  if (menu != null)
                    _sosyalActionChip(
                      icon: Icons.restaurant_menu_rounded,
                      label: 'Menü',
                      primary: true,
                      onTap: () =>
                          unawaited(showSosyalMenuSheet(context, menu)),
                    ),
                  _sosyalActionChip(
                    icon: Icons.map_outlined,
                    label: 'Harita',
                    primary: menu == null,
                    onTap: () =>
                        unawaited(openMapSearch(context, s.il, s.isim)),
                  ),
                  _sosyalActionChip(
                    icon: Icons.ios_share_rounded,
                    label: 'Paylaş',
                    onTap: () => unawaited(_shareSosyal(s)),
                  ),
                  _sosyalActionChip(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Yorum',
                    onTap: () => unawaited(
                      pushOnShellNavigator<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => YorumScreen(
                            facilityId: ReviewRepository.sanitizeFacilityId(
                              'sosyal_${s.il}\u0001${s.isim}',
                            ),
                            facilityName: s.isim,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sosyalTabSlivers(BuildContext context, List<SosyalItem> items) {
    final locationBar = SliverToBoxAdapter(
      child: _listLocationBar<SosyalItem>(
        tab: 3,
        noun: 'tesis',
        inIl: _sosyalFiltered,
        all: widget.rotaData.sosyal,
        ilOf: (s) => s.il,
        ilceOf: _ilceOfSosyal,
        shown: items.length,
      ),
    );
    if (items.isEmpty) {
      return [
        locationBar,
        _kListGap,
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: _listEmptyState(
              3,
              'Bu ilde belediye / tesis kaydı yok',
              'Bu seçimde belediye sosyal tesisi kaydı yok',
            ),
          ),
        ),
      ];
    }
    return [
      locationBar,
      _kListGap,
      SliverList(
        delegate: SliverChildBuilderDelegate((ctx, index) {
          if (index.isOdd) return _kListDivider;
          return _sosyalFacilityRow(context, items[index ~/ 2]);
        }, childCount: items.length * 2 - 1),
      ),
      _listBottomInset(context),
    ];
  }
}

/// Eşleşen liste satırında yumuşak, yavaş sarı vurgu.
class _SearchHighlightFlash extends StatefulWidget {
  const _SearchHighlightFlash({
    super.key,
    required this.child,
    this.totalMs = 7000,
  });

  final Widget child;
  final int totalMs;

  @override
  State<_SearchHighlightFlash> createState() => _SearchHighlightFlashState();
}

class _SearchHighlightFlashState extends State<_SearchHighlightFlash>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.totalMs),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Yavaş 2.5 nefes; sonda yumuşak sönme.
  static double _softPulse(double t) {
    final x = t.clamp(0.0, 1.0);
    // Son %12'de tamamen sön.
    if (x >= 0.88) {
      final fade = (1.0 - x) / 0.12;
      return Curves.easeOut.transform(fade.clamp(0.0, 1.0)) * 0.35;
    }
    // 0–0.88 arası ~2.5 yavaş nefes
    final local = x / 0.88;
    final cycle = (local * 2.5) % 1.0;
    final wave = cycle <= 0.5
        ? Curves.easeInOutCubic.transform(cycle / 0.5)
        : Curves.easeInOutCubic.transform(1 - (cycle - 0.5) / 0.5);
    // Taban + hafif dalga — hiç “flashbang” olmasın.
    return 0.28 + wave * 0.72;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final mix = _softPulse(_c.value);
        final fill = Color.lerp(
          Colors.transparent,
          const Color(0xFFFFF59D).withValues(alpha: 0.38),
          mix,
        )!;
        final accent = Color.lerp(
          Colors.transparent,
          const Color(0xFFFBC02D).withValues(alpha: 0.70),
          mix,
        )!;
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fill,
                    border: Border(left: BorderSide(color: accent, width: 3)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// Kart başındaki küçük kategori ikonu (yalnız ikon alanında kategori tonu).
Widget _categoryIcon(IconData icon, AraTone tone) {
  return Container(
    width: 42,
    height: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: tone.bg,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, size: 20, color: tone.fg),
  );
}

/// Sonuç sayısı + Liste / Harita geçişi (liste ve harita görünümünde aynı çubuk).
///
/// Harita görünümünde kategori adı açılır menü olur; seçim yapınca liste görünümüne dönülür.
class _ViewModeBar extends StatelessWidget {
  const _ViewModeBar({
    required this.showList,
    required this.tabIndex,
    required this.counts,
    required this.onViewModeChanged,
    required this.onTabChanged,
  });

  final bool showList;
  final int tabIndex;
  final List<int> counts;
  final ValueChanged<bool> onViewModeChanged;
  final ValueChanged<int> onTabChanged;

  static const double height = 46;
  static const _labels = [
    'Konaklama',
    'Gezi',
    'Yemek',
    'Tesisler',
    'Hediyelik',
    'Kamp',
  ];

  @override
  Widget build(BuildContext context) {
    final i = tabIndex.clamp(0, _labels.length - 1);
    final count = i < counts.length ? counts[i] : 0;
    // Bilgi başlığı: buton değil; kategori koyu, sonuç sayısı daha hafif.
    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: _labels[i],
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AraUi.inactiveForegroundOf(context),
            ),
          ),
          TextSpan(
            text: '  $count sonuç',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AraUi.mutedTextOf(context),
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final Widget left = showList
        ? title
        : PopupMenuButton<int>(
            tooltip: 'Kategori',
            position: PopupMenuPosition.under,
            color: AppColors.surfaceOf(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: onTabChanged,
            itemBuilder: (_) => [
              for (var k = 0; k < _labels.length; k++)
                PopupMenuItem<int>(
                  value: k,
                  child: Row(
                    children: [
                      Expanded(child: Text(_labels[k])),
                      Text(
                        '${k < counts.length ? counts[k] : 0}',
                        style: const TextStyle(color: Color(0xFF8A9A9F)),
                      ),
                    ],
                  ),
                ),
            ],
            child: Row(
              children: [
                Flexible(child: title),
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 22,
                  color: AppColors.primary,
                ),
              ],
            ),
          );
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: 8),
            _ViewToggle(showList: showList, onChanged: onViewModeChanged),
          ],
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.showList, required this.onChanged});

  final bool showList;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AraUi.secondaryActionBorderOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segment(
              context,
              icon: Icons.view_list_rounded,
              label: 'Liste',
              selected: showList,
              onTap: () => onChanged(true),
            ),
            _segment(
              context,
              icon: Icons.map_rounded,
              label: 'Harita',
              selected: !showList,
              onTap: () => onChanged(false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final fg = selected ? AraUi.activeForeground : AraUi.inactiveForegroundOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: selected ? AraUi.activeFill : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tab barını [CustomScrollView] içinde en üstte sabit tutan [SliverPersistentHeaderDelegate].
class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarHeaderDelegate({
    required this.tabIndex,
    required this.onTabChanged,
    required this.counts,
  });

  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  /// [Konaklama, Gezi, Yemek, Tesisler, Hediyelik, Kamp] sonuç sayıları.
  final List<int> counts;

  static const double height = 60.0;
  static const _labels = ['Konaklama', 'Gezi', 'Yemek', 'Tesisler'];

  /// Açılır menüden seçilen sekmeler ([_labels] sonrası).
  static const hediyelikTab = 4;
  static const kampTab = 5;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  bool shouldRebuild(_TabBarHeaderDelegate old) =>
      old.tabIndex != tabIndex ||
      old.counts.length != counts.length ||
      !_countsEqual(old.counts, counts);

  static bool _countsEqual(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: AraUi.chromeFillOf(context),
      elevation: overlapsContent ? 1.5 : 0,
      shadowColor: Colors.black12,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AraUi.secondaryActionBorderOf(context)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    children: [
                      for (var i = 0; i < _labels.length; i++)
                        Expanded(child: _segment(context, i)),
                      _moreSegment(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ColoredBox(
            color: AraUi.secondaryActionBorderOf(context),
            child: SizedBox(height: 1, width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _moreSegment(BuildContext context) {
    final sel = tabIndex == hediyelikTab || tabIndex == kampTab;
    final selIndex = tabIndex == kampTab ? kampTab : hediyelikTab;
    final count = selIndex < counts.length ? counts[selIndex] : 0;
    final hediyelikSayisi = hediyelikTab < counts.length
        ? counts[hediyelikTab]
        : 0;
    final kampSayisi = kampTab < counts.length ? counts[kampTab] : 0;
    final fg = sel ? AraUi.activeForeground : AraUi.inactiveForegroundOf(context);
    return PopupMenuButton<int>(
      tooltip: 'Diğer sekmeler',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      color: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: onTabChanged,
      itemBuilder: (_) => [
        PopupMenuItem<int>(
          value: hediyelikTab,
          child: Row(
            children: [
              const Icon(
                Icons.card_giftcard_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Hediyelik',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textStrongOf(context),
                      ),
                    ),
                    Text(
                      'İle özgü yöresel ürünler',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7C82)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$hediyelikSayisi',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8A9A9F),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: kampTab,
          child: Row(
            children: [
              const Icon(
                Icons.park_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Kamp Rotaları',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textStrongOf(context),
                      ),
                    ),
                    Text(
                      'Çadır, karavan ve kamping',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7C82)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$kampSayisi',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8A9A9F),
                ),
              ),
            ],
          ),
        ),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: sel ? 74 : 50,
        decoration: BoxDecoration(
          color: sel ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: sel
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tabIndex == kampTab
                        ? 'Kamp'
                        : tabIndex == hediyelikTab
                        ? 'Hediyelik'
                        : 'Daha',
                    style: TextStyle(
                      color: fg,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 12.5,
                      height: 1.05,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  sel
                      ? Text(
                          '$count',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            height: 1.0,
                          ),
                        )
                      : Icon(Icons.expand_more_rounded, size: 14, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, int index) {
    final sel = tabIndex == index;
    final count = (index < counts.length) ? counts[index] : 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: sel ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: sel
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTabChanged(index),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _labels[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: sel
                            ? AraUi.activeForeground
                            : AraUi.inactiveForegroundOf(context),
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                        fontSize: 12.5,
                        height: 1.05,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: sel
                            ? Colors.white.withValues(alpha: 0.9)
                            : AraUi.mutedTextOf(context),
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fiyat kaydı olan tesis kartında, ad satırının sağındaki salt okunur etiket.
/// Kartın kendisi tıklanır; bu etiket ayrı bir düğme değildir.
class _UcretBilgisiLabel extends StatelessWidget {
  const _UcretBilgisiLabel();

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1B4D34) : const Color(0xFFE5F6EA),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            'Fiyat Bilgisi',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: dark ? const Color(0xFFB7E7C6) : const Color(0xFF146C39),
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
