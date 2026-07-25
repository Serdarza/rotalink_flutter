import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads/ad_service.dart';
import '../ads/discover_native_merge.dart';
import '../billing/pro_service.dart';
import '../providers/facility_filter_provider.dart';
import '../navigator_keys.dart';
import '../screens/yorum_screen.dart';
import '../services/review_repository.dart';
import '../data/favorites_repository.dart';
import '../data/facility_address_repository.dart';
import '../data/firebase_rota_repository.dart';
import '../data/gezi_yemek_repository.dart';
import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
import '../models/sosyal_item.dart';
import '../map_location_state.dart';
import '../services/nominatim_geocode_cache.dart';
import '../theme/app_colors.dart';
import '../utils/geo_helpers.dart';
import '../utils/maps_launch.dart';
import '../utils/safe_map_coordinates.dart';
import '../utils/search_normalize.dart';
import 'distance_permission_chip.dart';
import 'facility_detail_card.dart';
import 'rotalink_glass_bottom_nav.dart';

/// Arama sonucu alt paneli: liste için yarı ekran.
const double kMisafirhaneSearchSheetOpenExtent = 0.5;

/// Konaklama detay kartı: alt menünün hemen üstünde bitsin (çok yukarı açılmasın).
const double kMisafirhaneSearchSheetDetailExtent = 0.68;

/// [Scaffold.bottomNavigationBar] yüksekliğine yakın — liste alt boşluğu (dış [Padding] yok).
const double kMisafirhaneSearchSheetMainBottomBarReserve = 56;

/// Kotlin [MisafirhaneBottomSheet] (arama modu): Tesis / Gezi / Yemek / Sosyal sekmeleri.
/// Ana harita gövdesindeki [Stack] içine yerleştirilir; üstteki toolbar ve arama çubuğu sheet’ten sonra
/// çizilerek her zaman önde kalır.
class MisafirhaneSearchResultsPanel extends ConsumerStatefulWidget {
  const MisafirhaneSearchResultsPanel({
    super.key,
    required this.sheetExtentController,
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
  });

  final DraggableScrollableController sheetExtentController;

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
      unawaited(_closeFacilityDetail(animateSheet: false));
      return true;
    }
    return false;
  }

  bool get isDetailOpen => _detailFacility != null;

  Future<void> _animateSheetToDetail() async {
    final c = widget.sheetExtentController;
    if (!c.isAttached) return;
    try {
      await c.animateTo(
        kMisafirhaneSearchSheetDetailExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  Future<void> _animateSheetToList() async {
    final c = widget.sheetExtentController;
    if (!c.isAttached) return;
    try {
      await c.animateTo(
        kMisafirhaneSearchSheetOpenExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_animateSheetToDetail());
    });
  }

  Future<void> _closeFacilityDetail({bool animateSheet = true}) async {
    if (_detailFacility == null) return;
    final returnTo = _detailFacility!;
    if (animateSheet) await _animateSheetToList();
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
      final idx = facilities.indexWhere((f) => f.sameFavoriteIdentity(facility));
      if (idx >= 0 && scroll.hasClients) {
        const kTabBarH = _TabBarHeaderDelegate.height;
        const kApproxItemH = 92.0;
        final approx = (kTabBarH + idx * kApproxItemH)
            .clamp(0.0, scroll.position.maxScrollExtent);
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

  /// [DraggableScrollableSheet] dış denetleyicisi — ömrü [MainMapScreen] tarafından sheet kapanınca dispose edilir.
  ScrollController? _listScroll;

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

  int _nativeAdGen = 0;
  List<NativeAd> _nativeAdsGezi = [];
  List<NativeAd> _nativeAdsYemek = [];
  List<NativeAd> _nativeAdsSosyal = [];

  static const _rotalinkStoreUrl =
      'https://play.google.com/store/apps/details?id=com.serdarza.rotalink';

  static String _shareAppDownloadFooter() =>
      'Uygulamamızı buradan indirebilirsiniz:\n$_rotalinkStoreUrl';

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
    widget.mapLocationState.addListener(_onMapLocationChanged);
    unawaited(_loadFavorites());
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
      if (widget.initialTabIndex != 0) {
        _scheduleNativesForTab(widget.initialTabIndex);
      }
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

  void _onProChanged() {
    if (!mounted) return;
    if (ProService.instance.isAdFree) {
      _clearNativeAds();
      setState(() {});
    } else if (_tabIndex >= 1 && _tabIndex <= 3) {
      _scheduleNativesForTab(_tabIndex);
    }
  }

  void _clearNativeAds() {
    _nativeAdGen++;
    for (final a in _nativeAdsGezi) {
      a.dispose();
    }
    for (final a in _nativeAdsYemek) {
      a.dispose();
    }
    for (final a in _nativeAdsSosyal) {
      a.dispose();
    }
    _nativeAdsGezi = [];
    _nativeAdsYemek = [];
    _nativeAdsSosyal = [];
  }

  @override
  void didUpdateWidget(covariant MisafirhaneSearchResultsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ho = oldWidget.highlightTarget;
    final hn = widget.highlightTarget;
    final hlChanged = (ho == null) != (hn == null) ||
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
    if (oldWidget.rotaData.gezi.length != widget.rotaData.gezi.length ||
        oldWidget.rotaData.yemek.length != widget.rotaData.yemek.length ||
        oldWidget.rotaData.sosyal.length != widget.rotaData.sosyal.length) {
      _scheduleNativesForTab(_tabIndex);
    }
  }

  @override
  void dispose() {
    ProService.instance.isPro.removeListener(_onProChanged);
    widget.mapLocationState.removeListener(_onMapLocationChanged);
    for (final a in _nativeAdsGezi) {
      a.dispose();
    }
    for (final a in _nativeAdsYemek) {
      a.dispose();
    }
    for (final a in _nativeAdsSosyal) {
      a.dispose();
    }
    super.dispose();
  }

  void _scheduleNativesForTab(int tab) {
    _nativeAdGen++;
    final gen = _nativeAdGen;
    for (final a in _nativeAdsGezi) {
      a.dispose();
    }
    for (final a in _nativeAdsYemek) {
      a.dispose();
    }
    for (final a in _nativeAdsSosyal) {
      a.dispose();
    }
    _nativeAdsGezi = [];
    _nativeAdsYemek = [];
    _nativeAdsSosyal = [];
    if (mounted) setState(() {});
    if (tab < 1 || tab > 3) return;
    if (!AdService.adsEnabled ||
        kIsWeb ||
        ProService.instance.isAdFree) {
      return;
    }
    final len = switch (tab) {
      1 => _geziFiltered.length,
      2 => _yemekFiltered.length,
      3 => _sosyalFiltered.length,
      _ => 0,
    };
    final slots = DiscoverNativeMerge.nativeSlotsNeeded(len);
    if (slots <= 0) return;
    unawaited(() async {
      final pool = await DiscoverNativeMerge.loadPool(slots);
      if (!mounted ||
          gen != _nativeAdGen ||
          ProService.instance.isAdFree) {
        for (final a in pool) {
          a.dispose();
        }
        return;
      }
      setState(() {
        switch (tab) {
          case 1:
            _nativeAdsGezi = pool;
            break;
          case 2:
            _nativeAdsYemek = pool;
            break;
          case 3:
            _nativeAdsSosyal = pool;
            break;
        }
      });
    }());
  }

  List<Object> _mergeGeziEveryFive(List<GeziYemekItem> items, List<NativeAd> ads) {
    if (ads.isEmpty ||
        !AdService.adsEnabled ||
        kIsWeb ||
        ProService.instance.isAdFree) {
      return List<Object>.from(items);
    }
    final out = <Object>[];
    var ai = 0;
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if ((i + 1) % 5 == 0 && ai < ads.length) {
        out.add(ads[ai++]);
      }
    }
    return out;
  }

  List<Object> _mergeSosyalEveryFive(List<SosyalItem> items, List<NativeAd> ads) {
    if (ads.isEmpty ||
        !AdService.adsEnabled ||
        kIsWeb ||
        ProService.instance.isAdFree) {
      return List<Object>.from(items);
    }
    final out = <Object>[];
    var ai = 0;
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if ((i + 1) % 5 == 0 && ai < ads.length) {
        out.add(ads[ai++]);
      }
    }
    return out;
  }

  Widget _nativeAdTile(NativeAd ad) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        color: AppColors.white,
        child: SizedBox(
          height: 280,
          width: double.infinity,
          child: AdWidget(ad: ad),
        ),
      ),
    );
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
    final ext = widget.sheetExtentController;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    if (ext.isAttached && ext.size < 0.12) {
      await ext.animateTo(
        kMisafirhaneSearchSheetOpenExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      if (!mounted) return;
    }
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
      final approx = (kTabBarH + targetIdx * kApproxItemH)
          .clamp(0.0, scroll.position.maxScrollExtent);
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

    final ext = widget.sheetExtentController;
    if (ext.isAttached && ext.size < 0.12) {
      await ext.animateTo(
        kMisafirhaneSearchSheetOpenExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      if (!mounted || widget.highlightTarget == null || _tabIndex != 0) return;
    }

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
      final next = (_listScroll!.offset + 160.0).clamp(0.0, pos.maxScrollExtent);
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

  List<SosyalItem> get _sosyalFiltered {
    final raw = widget.rotaData.sosyal;
    final want = _facilityIllerNorm;
    if (want.isEmpty) return raw;
    return raw.where((s) => want.contains(normalizeForSearch(s.il))).toList();
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
    final c = widget.sheetExtentController;
    if (c.isAttached) {
      unawaited(
        c.animateTo(
          kMisafirhaneSearchSheetOpenExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    _scheduleNativesForTab(index);
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
      Future<void> gezi() =>
          _hydrateGeziYemekCoords(_geziFiltered, gen: gen);
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
          final hadOnlyErrors = _geziFiltered.any((g) {
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
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Telefon numarası yok')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: p.replaceAll(RegExp(r'\s'), ''));
    if (await canLaunchUrl(uri)) {
      AdService.instance.notifyLeavingToExternalApp();
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Arama başlatılamadı')),
        );
      }
    }
  }

  Future<void> _shareMisafirhane(Misafirhane m) async {
    final mapsUrl = googleMapsShareUrlForMisafirhane(m);
    final text = '${m.isim}\n$mapsUrl\n\n'
        'Telefon: ${m.telefon.isEmpty ? 'Yok' : m.telefon}\n\n'
        'Rotalink uygulamasını bu linkten indirebilirsiniz.\n'
        '$_rotalinkStoreUrl';
    await Share.share(text);
  }

  Future<void> _shareGeziYemek(GeziYemekItem g) async {
    final name = g.isim.trim();
    final desc = g.aciklama.trim();
    final body = StringBuffer(name);
    if (desc.isNotEmpty) {
      body.write('\n\n');
      body.write(desc);
    }
    body.write('\n\n');
    body.write(_shareAppDownloadFooter());
    await Share.share(body.toString());
  }

  Future<void> _shareSosyal(SosyalItem s) async {
    final name = s.isim.trim();
    final ilce = _sosyalIlceLine(s);
    final aciklama = s.aciklama.trim();
    final body = StringBuffer(name);
    if (ilce.isNotEmpty) {
      body.write('\n');
      body.write(ilce);
    }
    if (aciklama.isNotEmpty) {
      body.write('\n\n');
      body.write(aciklama);
    }
    body.write('\n\n');
    body.write(_shareAppDownloadFooter());
    await Share.share(body.toString());
  }

  SliverToBoxAdapter _listBottomInset(BuildContext context) {
    final h = RotalinkGlassBottomNav.totalHeight(context) + 24;
    return SliverToBoxAdapter(child: SizedBox(height: h));
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // [StackFit.expand] üst üste tam ekran sıkı kısıt veriyordu; sheet tüm ekranı
              // hit-test edip harita ve arama çubuğunu kilitleyordu. Alta hizalı gevşek kısıt ile
              // yalnızca panel dokunuşları sheet’e gider.
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                        maxHeight: constraints.maxHeight,
                      ),
                      child: DraggableScrollableSheet(
                        controller: widget.sheetExtentController,
                        expand: false,
                        minChildSize: 0,
                        initialChildSize: kMisafirhaneSearchSheetOpenExtent,
                        maxChildSize: isDetailOpen
                            ? kMisafirhaneSearchSheetDetailExtent
                            : kMisafirhaneSearchSheetOpenExtent,
                        builder: (context, scrollController) {
                          _listScroll = scrollController;
                          final detail = _detailFacility;
                          return Material(
                            color: Colors.white,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                            clipBehavior: Clip.antiAlias,
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
                                          (f) => f.sameFavoriteIdentity(detail),
                                        ),
                                        onBack: () => unawaited(
                                          _closeFacilityDetail(),
                                        ),
                                        onCall: () => _dialPhone(
                                          context,
                                          detail.telefon,
                                        ),
                                        onShare: () =>
                                            unawaited(_shareMisafirhane(detail)),
                                        onFavorite: () =>
                                            unawaited(_toggleFavorite(detail)),
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
                                                facilityId: ReviewRepository
                                                    .sanitizeFacilityId(
                                                  detail.stableFacilityId,
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
                                        onRequestLocation: widget
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
                                            delegate: _TabBarHeaderDelegate(
                                              tabIndex: _tabIndex,
                                              onTabChanged: _onTabChanged,
                                              counts: [
                                                tesisFacilities.length,
                                                _geziFiltered.length,
                                                _yemekFiltered.length,
                                                _sosyalFiltered.length,
                                              ],
                                            ),
                                          ),
                                          ..._tabSlivers(context),
                                        ],
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
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
        return _geziTabSlivers(context, _sortedGezi(_geziFiltered));
      case 2:
        return _yemekTabSlivers(context, _yemekFiltered);
      case 3:
        return _sosyalTabSlivers(context, _sortedSosyal(_sosyalFiltered));
      default:
        return const [];
    }
  }


  List<Widget> _tesisTabSlivers(BuildContext context, List<Misafirhane> facilities) {
    if (facilities.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: _emptyTabState('Bu aramada konaklama kaydı yok'),
          ),
        ),
      ];
    }

    final n = facilities.length;
    final childCount = n * 2 - 1;
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, index) {
            if (index.isOdd) return _kListDivider;
            final i = index ~/ 2;
            return _tesisFacilityRow(context, facilities[i]);
          },
          childCount: childCount,
        ),
      ),
      _listBottomInset(context),
    ];
  }

  Widget _tesisFacilityRow(BuildContext context, Misafirhane m) {
    final resolved = FacilityAddressRepository.instance.resolveFacility(m);
    final flash = _flashFacility != null &&
        m.sameFavoriteIdentity(_flashFacility!);
    final ilce = resolved.ilce.trim();
    final row = _searchListTile(
      icon: Icons.hotel_rounded,
      title: resolved.isim,
      subtitle: ilce.isEmpty ? null : ilce,
      distance: DistancePermissionChip(
        userLocation: widget.mapLocationState.userLocation,
        locationPermissionGranted:
            widget.mapLocationState.locationPermissionGranted,
        facilityPoint: LatLng(m.latitude, m.longitude),
        onRequestLocation: widget.onRequestLocationPermission ?? () async {},
        spacingAbove: 8,
        fullWidthSingleLine: true,
      ),
      onTap: () => unawaited(_openFacilityDetail(m)),
      trailingCue: _konaklamaDetailCue(),
    );
    final wrapped = flash
        ? _SearchHighlightFlash(
            key: ValueKey<String>(
              'hl-$_flashGen-${m.stableFacilityId}',
            ),
            child: row,
          )
        : row;
    return KeyedSubtree(key: _keyForFacility(m), child: wrapped);
  }

  /// Konaklama satırı — karta geçişin anlaşılır olması için “Detay” ipucu.
  Widget _konaklamaDetailCue() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.14),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Detay',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              height: 1,
            ),
          ),
          SizedBox(width: 2),
          Icon(
            Icons.arrow_forward_rounded,
            size: 15,
            color: AppColors.primary,
          ),
        ],
      ),
    );
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
    final row = Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.12),
                        AppColors.primary.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Icon(
                    isGezi
                        ? Icons.landscape_rounded
                        : Icons.restaurant_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.isim,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          height: 1.28,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (locationLine.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          locationLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _sosyalActionChip(
                  icon: Icons.map_outlined,
                  label: 'Harita',
                  onTap: () =>
                      unawaited(openMapSearch(context, g.il, g.isim)),
                ),
                if (!isGezi)
                  _sosyalActionChip(
                    icon: Icons.map_rounded,
                    label: 'Git',
                    onTap: () {
                      if (mapsQuery.isEmpty) return;
                      unawaited(
                        openInNativeMaps(context, query: mapsQuery),
                      );
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
    final wrapped =
        isHl ? _SearchHighlightFlash(child: row) : row;
    return KeyedSubtree(key: _keyForGeziYemek(g), child: wrapped);
  }

  /// Ortak arama listesi satırı — ikon + başlık + alt metin + mesafe.
  Widget _searchListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? distance,
    required VoidCallback onTap,
    List<Widget> trailingActions = const [],
    Widget? trailingCue,
  }) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primary.withValues(alpha: 0.06),
        highlightColor: AppColors.primary.withValues(alpha: 0.03),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.12),
                      AppColors.primary.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.08),
                  ),
                ),
                child: Icon(icon, size: 20, color: AppColors.primary),
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
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        height: 1.28,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6B7C82),
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.05,
                        ),
                      ),
                    ],
                    if (distance != null) distance,
                  ],
                ),
              ),
              ...trailingActions,
              trailingCue ??
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: Color(0xFFB0BEC5),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  static const _kListDivider = Divider(
    height: 1,
    thickness: 1,
    indent: 70,
    endIndent: 0,
    color: Color(0xFFEEF2F3),
  );

  List<Widget> _geziTabSlivers(BuildContext context, List<GeziYemekItem> items) {
    if (items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: _emptyTabState('Bu ilde gezi kaydı yok'),
          ),
        ),
      ];
    }
    final merged = _mergeGeziEveryFive(items, _nativeAdsGezi);
    final m = merged.length;
    final childCount = m == 0 ? 0 : m * 2 - 1;
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, index) {
            if (index.isOdd) return _kListDivider;
            final i = index ~/ 2;
            final e = merged[i];
            if (e is NativeAd) {
              return _nativeAdTile(e);
            }
            final g = e as GeziYemekItem;
            return _geziYemekCompactRow(context, g, isGezi: true);
          },
          childCount: childCount,
        ),
      ),
      _listBottomInset(context),
    ];
  }

  List<Widget> _yemekTabSlivers(BuildContext context, List<GeziYemekItem> items) {
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
    final merged = _mergeGeziEveryFive(items, _nativeAdsYemek);
    final m = merged.length;
    final childCount = m == 0 ? 0 : m * 2 - 1;
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, index) {
            if (index.isOdd) return _kListDivider;
            final i = index ~/ 2;
            final e = merged[i];
            if (e is NativeAd) {
              return _nativeAdTile(e);
            }
            final g = e as GeziYemekItem;
            return _geziYemekCompactRow(context, g, isGezi: false);
          },
          childCount: childCount,
        ),
      ),
      _listBottomInset(context),
    ];
  }

  Widget _emptyTabState(String message) {
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
          ],
        ),
      ),
    );
  }

  Widget _sosyalActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF3F7F8),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sosyalFacilityRow(BuildContext context, SosyalItem s) {
    final ilce = _sosyalIlceLine(s);
    final aciklama = s.aciklama.trim();
    final ll = _latLngSosyal(s);
    return Material(
      color: Colors.white,
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
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.12),
                          AppColors.primary.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.isim,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _sosyalActionChip(
                    icon: Icons.map_outlined,
                    label: 'Harita',
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
    if (items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: _emptyTabState('Bu ilde belediye / tesis kaydı yok'),
          ),
        ),
      ];
    }
    final merged = _mergeSosyalEveryFive(items, _nativeAdsSosyal);
    final m = merged.length;
    final childCount = m == 0 ? 0 : m * 2 - 1;
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, index) {
            if (index.isOdd) return _kListDivider;
            final i = index ~/ 2;
            final e = merged[i];
            if (e is NativeAd) {
              return _nativeAdTile(e);
            }
            return _sosyalFacilityRow(context, e as SosyalItem);
          },
          childCount: childCount,
        ),
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
                    border: Border(
                      left: BorderSide(color: accent, width: 3),
                    ),
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

/// Tab barını [CustomScrollView] içinde en üstte sabit tutan [SliverPersistentHeaderDelegate].
class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarHeaderDelegate({
    required this.tabIndex,
    required this.onTabChanged,
    required this.counts,
  });

  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  /// [Konaklama, Gezi, Yemek, Tesisler] sonuç sayıları.
  final List<int> counts;

  static const double height = 60.0;
  static const _labels = ['Konaklama', 'Gezi', 'Yemek', 'Tesisler'];

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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: Colors.white,
      elevation: overlapsContent ? 1.5 : 0,
      shadowColor: Colors.black12,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF4F5),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    children: [
                      for (var i = 0; i < _labels.length; i++)
                        Expanded(child: _segment(i)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const ColoredBox(
            color: Color(0xFFEEF2F3),
            child: SizedBox(height: 1, width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _segment(int index) {
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
                        color: sel ? Colors.white : const Color(0xFF5A6B70),
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
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
                            : const Color(0xFF8A9A9F),
                        fontWeight: FontWeight.w600,
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
