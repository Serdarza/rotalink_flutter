import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads/ad_service.dart';
import '../screens/yorum_screen.dart';
import '../services/review_repository.dart';
import '../ads/discover_native_merge.dart';
import '../data/favorites_repository.dart';
import '../data/firebase_rota_repository.dart';
import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
import '../models/sosyal_item.dart';
import '../map_location_state.dart';
import '../services/nominatim_geocode_cache.dart';
import '../theme/app_colors.dart';
import 'distance_permission_chip.dart';
import '../utils/maps_launch.dart';
import '../utils/safe_map_coordinates.dart';
import '../utils/search_normalize.dart';

/// Arama sonucu alt paneli: en fazla ekranın yarısı; daha yukarı sürüklenemez.
const double kMisafirhaneSearchSheetOpenExtent = 0.5;

/// [Scaffold.bottomNavigationBar] yüksekliğine yakın — liste alt boşluğu (dış [Padding] yok).
const double kMisafirhaneSearchSheetMainBottomBarReserve = 56;

/// Kotlin [MisafirhaneBottomSheet] (arama modu): Tesis / Gezi / Yemek / Sosyal sekmeleri.
/// Ana harita gövdesindeki [Stack] içine yerleştirilir; üstteki toolbar ve arama çubuğu sheet’ten sonra
/// çizilerek her zaman önde kalır.
class MisafirhaneSearchResultsPanel extends StatefulWidget {
  const MisafirhaneSearchResultsPanel({
    super.key,
    required this.sheetExtentController,
    required this.facilities,
    required this.rotaData,
    required this.mapLocationState,
    this.highlightTarget,
    required this.favoritesRepo,
    required this.onFavoritesChanged,
    required this.onTesisSelect,
    this.onRequestLocationPermission,
    required this.onClosePanel,
  });

  final DraggableScrollableController sheetExtentController;

  final List<Misafirhane> facilities;
  final RotaDataState rotaData;
  final MapLocationState mapLocationState;
  final Misafirhane? highlightTarget;
  final FavoritesRepository favoritesRepo;
  final Future<void> Function() onFavoritesChanged;
  final Future<void> Function(Misafirhane m) onTesisSelect;

  final Future<void> Function()? onRequestLocationPermission;

  /// Tesis satırı seçilmeden hemen önce panel kapatılır (önceden [Navigator.pop] ile sheet kapatılıyordu).
  final VoidCallback onClosePanel;

  @override
  State<MisafirhaneSearchResultsPanel> createState() => _MisafirhaneSearchResultsPanelState();
}

class _MisafirhaneSearchResultsPanelState extends State<MisafirhaneSearchResultsPanel> {
  int _tabIndex = 0;
  List<Misafirhane> _favorites = const [];

  /// [DraggableScrollableSheet] dış denetleyicisi — ömrü [MainMapScreen] tarafından sheet kapanınca dispose edilir.
  ScrollController? _listScroll;

  /// İl [ExpansionTile] içindeki satırlar için — vurgu kaydırması.
  final Map<String, GlobalKey> _facilityRowKeys = {};

  /// Nominatim ile çözülen koordinatlar (gezi/yemek ortak anahtar: isim+il).
  final Map<String, LatLng> _geocodeGeziYemek = {};

  /// Sosyal satırlar için çözülen koordinatlar.
  final Map<String, LatLng> _geocodeSosyal = {};

  /// Sekme değişince önceki Nominatim döngüsünü iptal et.
  int _geocodeGen = 0;

  int _nativeAdGen = 0;
  List<NativeAd> _nativeAdsGezi = [];
  List<NativeAd> _nativeAdsYemek = [];
  List<NativeAd> _nativeAdsSosyal = [];

  static const _rotalinkStoreUrl =
      'https://play.google.com/store/apps/details?id=com.serdarza.rotalink';

  static String _shareAppDownloadFooter() =>
      'Uygulamamızı buradan indirebilirsiniz:\n$_rotalinkStoreUrl';

  /// Sosyal satırında gösterilen alt metin (ilçe + açıklama).
  static String _sosyalRowSubtitle(SosyalItem s) {
    final ilce = s.ilce.trim();
    final ac = s.aciklama.trim();
    if (ilce.isEmpty && ac.isEmpty) return '';
    if (ilce.isEmpty) return ac;
    if (ac.isEmpty) return ilce;
    return '$ilce - $ac';
  }

  void _onMapLocationChanged() {
    if (!mounted) return;
    if (widget.mapLocationState.userLocation == null) return;
    switch (_tabIndex) {
      case 1:
        unawaited(_hydrateGeziYemekCoords(_geziFiltered));
        break;
      case 2:
        unawaited(_hydrateGeziYemekCoords(_yemekFiltered));
        break;
      case 3:
        unawaited(_hydrateSosyalCoords());
        break;
      default:
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.mapLocationState.addListener(_onMapLocationChanged);
    unawaited(_loadFavorites());
    // Alt sayfa + CustomScrollView layout’u oturduktan sonra kaydır (tek kare yetmeyebilir).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_expandSheetAndScrollToHighlight());
      });
    });
  }

  @override
  void didUpdateWidget(covariant MisafirhaneSearchResultsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.facilities.length != widget.facilities.length) {
      _facilityRowKeys.clear();
    }
    final ho = oldWidget.highlightTarget;
    final hn = widget.highlightTarget;
    final hlChanged = (ho == null) != (hn == null) ||
        (ho != null && hn != null && !ho.sameFavoriteIdentity(hn));
    if (hlChanged || oldWidget.facilities.length != widget.facilities.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_expandSheetAndScrollToHighlight());
      });
    }
    if (oldWidget.facilities.length != widget.facilities.length ||
        oldWidget.rotaData.gezi.length != widget.rotaData.gezi.length ||
        oldWidget.rotaData.yemek.length != widget.rotaData.yemek.length ||
        oldWidget.rotaData.sosyal.length != widget.rotaData.sosyal.length) {
      _scheduleNativesForTab(_tabIndex);
    }
  }

  @override
  void dispose() {
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
    if (!AdService.adsEnabled || kIsWeb) return;
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
      if (!mounted || gen != _nativeAdGen) {
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
    if (ads.isEmpty || !AdService.adsEnabled || kIsWeb) {
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
    if (ads.isEmpty || !AdService.adsEnabled || kIsWeb) {
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
      if (rowKey.currentContext != null) return;
      if (_listScroll == null || !_listScroll!.hasClients) return;
      final pos = _listScroll!.position;
      final next = (_listScroll!.offset + 160.0).clamp(0.0, pos.maxScrollExtent);
      if (next <= _listScroll!.offset + 0.5) break;
      _listScroll!.jumpTo(next);
      await Future<void>.delayed(const Duration(milliseconds: 24));
      await animateVisible();
    }
  }

  Future<void> _loadFavorites() async {
    final list = await widget.favoritesRepo.load();
    if (!mounted) return;
    setState(() => _favorites = list);
  }

  Set<String> get _facilityIllerNorm => widget.facilities
      .map((e) => normalizeForSearch(e.il))
      .where((s) => s.isNotEmpty)
      .toSet();

  List<GeziYemekItem> get _geziFiltered {
    final raw = widget.rotaData.gezi;
    final want = _facilityIllerNorm;
    if (want.isEmpty) return raw;
    return raw.where((g) => want.contains(normalizeForSearch(g.il))).toList();
  }

  List<GeziYemekItem> get _yemekFiltered {
    final raw = widget.rotaData.yemek;
    final want = _facilityIllerNorm;
    if (want.isEmpty) return raw;
    return raw.where((g) => want.contains(normalizeForSearch(g.il))).toList();
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
    if (cached != null && !isValidWgs84LatLng(cached.latitude, cached.longitude)) return null;
    return cached;
  }

  LatLng? _latLngSosyal(SosyalItem s) {
    if (s.enlem != null && s.boylam != null) {
      if (!isValidWgs84LatLng(s.enlem!, s.boylam!)) return null;
      return LatLng(s.enlem!, s.boylam!);
    }
    final cached = _geocodeSosyal[_keySosyal(s)];
    if (cached != null && !isValidWgs84LatLng(cached.latitude, cached.longitude)) return null;
    return cached;
  }

  double _distanceMetersToUser(LatLng? point) {
    final u = widget.mapLocationState.userLocation;
    if (u == null || point == null) return double.infinity;
    if (!isValidWgs84LatLng(u.latitude, u.longitude)) return double.infinity;
    if (!isValidWgs84LatLng(point.latitude, point.longitude)) return double.infinity;
    const d = Distance();
    final m = d.as(LengthUnit.Meter, u, point);
    return m.isFinite ? m : double.infinity;
  }

  List<GeziYemekItem> _sortedGezi(List<GeziYemekItem> list) {
    final out = List<GeziYemekItem>.from(list);
    out.sort((a, b) {
      return _distanceMetersToUser(_latLngGeziYemek(a)).compareTo(
        _distanceMetersToUser(_latLngGeziYemek(b)),
      );
    });
    return out;
  }

  List<SosyalItem> _sortedSosyal(List<SosyalItem> list) {
    final out = List<SosyalItem>.from(list);
    out.sort((a, b) {
      return _distanceMetersToUser(_latLngSosyal(a)).compareTo(
        _distanceMetersToUser(_latLngSosyal(b)),
      );
    });
    return out;
  }

  void _onTabChanged(int index) {
    setState(() => _tabIndex = index);
    _scheduleNativesForTab(index);
    if (index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_expandSheetAndScrollToHighlight());
      });
    }
    switch (index) {
      case 1:
        unawaited(_hydrateGeziYemekCoords(_geziFiltered));
        break;
      case 2:
        unawaited(_hydrateGeziYemekCoords(_yemekFiltered));
        break;
      case 3:
        unawaited(_hydrateSosyalCoords());
        break;
    }
  }

  Future<void> _hydrateGeziYemekCoords(List<GeziYemekItem> items) async {
    // Kullanıcı konumu olmasa da Gezi/Yemek satırlarında mesafe için tesis koordinatı gerekir;
    // Nominatim doldurulunca izin verildiğinde anında "Size uzaklık" gösterilir.
    final gen = ++_geocodeGen;
    for (final g in items) {
      if (!mounted || gen != _geocodeGen) return;
      if (g.enlem != null && g.boylam != null) continue;
      final key = _keyGeziYemek(g);
      if (_geocodeGeziYemek.containsKey(key)) continue;
      final ll = await NominatimGeocodeCache.search('${g.isim}, ${g.il}, Turkey');
      if (!mounted || gen != _geocodeGen) return;
      if (ll != null) {
        setState(() => _geocodeGeziYemek[key] = ll);
      }
    }
  }

  Future<void> _hydrateSosyalCoords() async {
    final gen = ++_geocodeGen;
    for (final s in _sosyalFiltered) {
      if (!mounted || gen != _geocodeGen) return;
      if (s.enlem != null && s.boylam != null) continue;
      final key = _keySosyal(s);
      if (_geocodeSosyal.containsKey(key)) continue;
      final query = s.ilce.trim().isNotEmpty
          ? '${s.isim}, ${s.ilce}, ${s.il}, Turkey'
          : '${s.isim}, ${s.il}, Turkey';
      final ll = await NominatimGeocodeCache.search(query);
      if (!mounted || gen != _geocodeGen) return;
      if (ll != null) {
        setState(() => _geocodeSosyal[key] = ll);
      }
    }
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
      await launchUrl(uri);
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
    final sub = _sosyalRowSubtitle(s);
    final body = StringBuffer(name);
    if (sub.isNotEmpty) {
      body.write('\n\n');
      body.write(sub);
    }
    body.write('\n\n');
    body.write(_shareAppDownloadFooter());
    await Share.share(body.toString());
  }

  Future<void> _openGoogleImages(String query) async {
    final uri = Uri.parse(
      'https://www.google.com/search?tbm=isch&q=${Uri.encodeComponent(query)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  SliverToBoxAdapter _listBottomInset(BuildContext context) {
    final sys = MediaQuery.paddingOf(context).bottom;
    final h = sys + kMisafirhaneSearchSheetMainBottomBarReserve + 24;
    return SliverToBoxAdapter(child: SizedBox(height: h));
  }

  @override
  Widget build(BuildContext context) {
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
                        maxChildSize: kMisafirhaneSearchSheetOpenExtent,
                        builder: (context, scrollController) {
                          _listScroll = scrollController;
                          return Material(
                            color: Colors.white,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            clipBehavior: Clip.antiAlias,
                            child: CustomScrollView(
                              controller: scrollController,
                              physics: const ClampingScrollPhysics(),
                              slivers: [
                                SliverPersistentHeader(
                                  pinned: true,
                                  delegate: _TabBarHeaderDelegate(
                                    tabIndex: _tabIndex,
                                    onTabChanged: _onTabChanged,
                                    counts: [
                                      widget.facilities.length,
                                      _geziFiltered.length,
                                      _yemekFiltered.length,
                                      _sosyalFiltered.length,
                                    ],
                                  ),
                                ),
                                ..._tabSlivers(context),
                              ],
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
        return _tesisTabSlivers(context);
      case 1:
        return _geziTabSlivers(context, _sortedGezi(_geziFiltered));
      case 2:
        return _yemekTabSlivers(context, _sortedGezi(_yemekFiltered));
      case 3:
        return _sosyalTabSlivers(context, _sortedSosyal(_sosyalFiltered));
      default:
        return const [];
    }
  }


  List<Widget> _tesisTabSlivers(BuildContext context) {
    if (widget.facilities.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: const Center(
              child: Text('Kayıt yok', style: TextStyle(color: AppColors.textPrimary)),
            ),
          ),
        ),
      ];
    }

    final n = widget.facilities.length;
    final childCount = n * 2 - 1;
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, index) {
            if (index.isOdd) return const Divider(height: 1);
            final i = index ~/ 2;
            return _tesisFacilityRow(context, widget.facilities[i]);
          },
          childCount: childCount,
        ),
      ),
      _listBottomInset(context),
    ];
  }

  Widget _tesisFacilityRow(BuildContext context, Misafirhane m) {
    final isFav = _favorites.any((f) => f.sameFavoriteIdentity(m));
    final flash = widget.highlightTarget != null && m.sameFavoriteIdentity(widget.highlightTarget!);
    final row = InkWell(
      onTap: () async {
        widget.onClosePanel();
        await widget.onTesisSelect(m);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
            Expanded(
              child: Text(
                m.isim,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.15,
                ),
              ),
            ),
            _actionColumn(
              icon: Icons.call,
              color: const Color(0xFF2E7D32),
              label: 'Ara',
              onTap: () => _dialPhone(context, m.telefon),
            ),
            _actionColumn(
              icon: Icons.share,
              color: const Color(0xFF039BE5),
              label: 'Paylaş',
              onTap: () => _shareMisafirhane(m),
            ),
            _actionColumn(
              icon: isFav ? Icons.favorite : Icons.favorite_border,
              color: const Color(0xFFC2185B),
              label: 'Favori',
              onTap: () => unawaited(_toggleFavorite(m)),
            ),
            _actionColumn(
              icon: Icons.map_outlined,
              color: AppColors.primary,
              label: 'İncele',
              onTap: () => unawaited(openMapSearch(context, m.il, m.isim)),
            ),
            _actionColumn(
              icon: Icons.chat_bubble_outline,
              color: const Color(0xFFE65100),
              label: 'Yorum',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => YorumScreen(
                    facilityId: ReviewRepository.sanitizeFacilityId(m.stableFacilityId),
                    facilityName: m.isim,
                  ),
                ),
              ),
            ),
              ],
            ),
            DistancePermissionChip(
              userLocation: widget.mapLocationState.userLocation,
              locationPermissionGranted: widget.mapLocationState.locationPermissionGranted,
              facilityPoint: LatLng(m.latitude, m.longitude),
              onRequestLocation: widget.onRequestLocationPermission ?? () async {},
              spacingAbove: 4,
              fullWidthSingleLine: true,
            ),
          ],
        ),
      ),
    );
    final wrapped = flash ? _SearchHighlightFlash(child: row) : row;
    return KeyedSubtree(
      key: _keyForFacility(m),
      child: wrapped,
    );
  }

  Widget _actionColumn({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: SizedBox(
          width: 44,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labeledSideAction({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, top: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

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
            child: const Center(
              child: Text('Kayıt yok', style: TextStyle(color: AppColors.textPrimary)),
            ),
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
            if (index.isOdd) return const Divider(height: 1);
            final i = index ~/ 2;
            final e = merged[i];
            if (e is NativeAd) {
              return _nativeAdTile(e);
            }
            final g = e as GeziYemekItem;
            final ll = _latLngGeziYemek(g);
            Future<void> openMap() => openMapSearch(context, g.il, g.isim);
            return InkWell(
              onTap: () => unawaited(openMap()),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                g.isim,
                                softWrap: true,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (g.aciklama.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  g.aciklama,
                                  softWrap: true,
                                  overflow: TextOverflow.visible,
                                  maxLines: 12,
                                  style: const TextStyle(fontSize: 12, color: AppColors.campaignSummaryMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _labeledSideAction(
                              context: context,
                              icon: Icons.map_outlined,
                              color: AppColors.primary,
                              label: 'İncele',
                              onTap: () => unawaited(openMap()),
                            ),
                            _labeledSideAction(
                              context: context,
                              icon: Icons.share,
                              color: const Color(0xFF039BE5),
                              label: 'Paylaş',
                              onTap: () => unawaited(_shareGeziYemek(g)),
                            ),
                            _labeledSideAction(
                              context: context,
                              icon: Icons.chat_bubble_outline,
                              color: const Color(0xFFE65100),
                              label: 'Yorum',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => YorumScreen(
                                    facilityId: ReviewRepository.sanitizeFacilityId('gezi_${g.il}\u0001${g.isim}'),
                                    facilityName: g.isim,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    DistancePermissionChip(
                      userLocation: widget.mapLocationState.userLocation,
                      locationPermissionGranted: widget.mapLocationState.locationPermissionGranted,
                      facilityPoint: ll,
                      onRequestLocation: widget.onRequestLocationPermission ?? () async {},
                      spacingAbove: 6,
                      fullWidthSingleLine: true,
                    ),
                  ],
                ),
              ),
            );
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
            child: const Center(
              child: Text('Kayıt yok', style: TextStyle(color: AppColors.textPrimary)),
            ),
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
            if (index.isOdd) return const Divider(height: 1);
            final i = index ~/ 2;
            final e = merged[i];
            if (e is NativeAd) {
              return _nativeAdTile(e);
            }
            final g = e as GeziYemekItem;
            final ll = _latLngGeziYemek(g);
            Future<void> openImages() => _openGoogleImages('${g.il} ${g.isim}'.trim());
            Future<void> openNativeMapSearch() async {
              final q = '${g.il} ${g.isim}'.trim();
              if (q.isEmpty) return;
              await openInNativeMaps(context, query: q);
            }
            return InkWell(
              onTap: () => unawaited(openImages()),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                g.isim,
                                softWrap: true,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (g.aciklama.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  g.aciklama,
                                  softWrap: true,
                                  overflow: TextOverflow.visible,
                                  maxLines: 12,
                                  style: const TextStyle(fontSize: 12, color: AppColors.campaignSummaryMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _labeledSideAction(
                              context: context,
                              icon: Icons.image_search,
                              color: AppColors.primary,
                              label: 'İncele',
                              onTap: () => unawaited(openImages()),
                            ),
                            _labeledSideAction(
                              context: context,
                              icon: Icons.map_rounded,
                              color: const Color(0xFF2E7D32),
                              label: 'Git',
                              onTap: () => unawaited(openNativeMapSearch()),
                            ),
                            _labeledSideAction(
                              context: context,
                              icon: Icons.share,
                              color: const Color(0xFF039BE5),
                              label: 'Paylaş',
                              onTap: () => unawaited(_shareGeziYemek(g)),
                            ),
                            _labeledSideAction(
                              context: context,
                              icon: Icons.chat_bubble_outline,
                              color: const Color(0xFFE65100),
                              label: 'Yorum',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => YorumScreen(
                                    facilityId: ReviewRepository.sanitizeFacilityId('yemek_${g.il}\u0001${g.isim}'),
                                    facilityName: g.isim,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    DistancePermissionChip(
                      userLocation: widget.mapLocationState.userLocation,
                      locationPermissionGranted: widget.mapLocationState.locationPermissionGranted,
                      facilityPoint: ll,
                      onRequestLocation: widget.onRequestLocationPermission ?? () async {},
                      spacingAbove: 6,
                      fullWidthSingleLine: true,
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: childCount,
        ),
      ),
      _listBottomInset(context),
    ];
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
            child: const Center(
              child: Text('Kayıt yok', style: TextStyle(color: AppColors.textPrimary)),
            ),
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
            if (index.isOdd) return const Divider(height: 1);
            final i = index ~/ 2;
            final e = merged[i];
            if (e is NativeAd) {
              return _nativeAdTile(e);
            }
            final s = e as SosyalItem;
            final sub = _sosyalRowSubtitle(s);
            final ll = _latLngSosyal(s);
            Future<void> openMap() => openMapSearch(context, s.il, s.isim);
            return InkWell(
              onTap: () => unawaited(openMap()),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.isim,
                                softWrap: true,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (sub.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  sub,
                                  softWrap: true,
                                  overflow: TextOverflow.visible,
                                  maxLines: 12,
                                  style: const TextStyle(fontSize: 12, color: AppColors.campaignSummaryMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _labeledSideAction(
                              context: context,
                              icon: Icons.map_outlined,
                              color: AppColors.primary,
                              label: 'İncele',
                              onTap: () => unawaited(openMap()),
                            ),
                            _labeledSideAction(
                              context: context,
                              icon: Icons.share,
                              color: const Color(0xFF039BE5),
                              label: 'Paylaş',
                              onTap: () => unawaited(_shareSosyal(s)),
                            ),
                            _labeledSideAction(
                              context: context,
                              icon: Icons.chat_bubble_outline,
                              color: const Color(0xFFE65100),
                              label: 'Yorum',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => YorumScreen(
                                    facilityId: ReviewRepository.sanitizeFacilityId('sosyal_${s.il}\u0001${s.isim}'),
                                    facilityName: s.isim,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    DistancePermissionChip(
                      userLocation: widget.mapLocationState.userLocation,
                      locationPermissionGranted: widget.mapLocationState.locationPermissionGranted,
                      facilityPoint: ll,
                      onRequestLocation: widget.onRequestLocationPermission ?? () async {},
                      spacingAbove: 6,
                      fullWidthSingleLine: true,
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: childCount,
        ),
      ),
      _listBottomInset(context),
    ];
  }
}

/// İki yavaş "nefes" döngüsü (~10 sn): çeyrekler easeInOut ile belirgin sarı vurgu.
class _SearchHighlightFlash extends StatefulWidget {
  const _SearchHighlightFlash({required this.child});

  final Widget child;

  @override
  State<_SearchHighlightFlash> createState() => _SearchHighlightFlashState();
}

class _SearchHighlightFlashState extends State<_SearchHighlightFlash>
    with SingleTickerProviderStateMixin {
  static const _totalMs = 10000;

  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _totalMs),
    )..forward();
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// [t] ∈ [0,1]: dört çeyrek, her biri 1,5 sn — easeInOut ile 0→1→0→1→0.
  static double _breathingMix(double t) {
    final x = t.clamp(0.0, 1.0);
    const q = 0.25;
    if (x <= q) {
      return Curves.easeInOut.transform(x / q);
    }
    if (x <= 2 * q) {
      return Curves.easeInOut.transform(1 - (x - q) / q);
    }
    if (x <= 3 * q) {
      return Curves.easeInOut.transform((x - 2 * q) / q);
    }
    return Curves.easeInOut.transform(1 - (x - 3 * q) / q);
  }

  @override
  Widget build(BuildContext context) {
    final mix = _breathingMix(_c.value);
    final peak = Colors.amber.shade400.withValues(alpha: 0.38);
    final bg = Color.lerp(Colors.transparent, peak, mix)!;
    return ColoredBox(color: bg, child: widget.child);
  }
}

/// Tab barını [CustomScrollView] içinde en üstte sabit tutan [SliverPersistentHeaderDelegate].
/// [pinned: true] ile içerik kaydırıldığında sekmeler görünür kalır.
/// Her sekme başlığı altında o kategoriye ait dinamik sonuç sayısını gösterir.
class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarHeaderDelegate({
    required this.tabIndex,
    required this.onTabChanged,
    required this.counts,
  });

  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  /// [Tesis, Gezi, Yemek, Sosyal] sırasında sonuç sayıları.
  final List<int> counts;

  // padding-top(10) + pill(56) + padding-bot(4) + divider(1)
  static const double _height = 71.0;

  static const _tabTesis = Color(0xFF0288D1);
  static const _tabGezi = Color(0xFF388E3C);
  static const _tabYemek = Color(0xFFFBC02D);
  static const _tabSosyal = Color(0xFFE64A19);

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

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
      elevation: overlapsContent ? 2.0 : 0.0,
      shadowColor: Colors.black26,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
            child: Row(
              children: [
                _pill(context, 'Tesis', 0, _tabTesis),
                _pill(context, 'Gezi', 1, _tabGezi),
                _pill(context, 'Yemek', 2, _tabYemek),
                _pill(context, 'Sosyal', 3, _tabSosyal),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String label, int index, Color active) {
    final sel = tabIndex == index;
    final count = (index < counts.length) ? counts[index] : 0;
    final countLabel = '$count Sonuç';

    final labelColor = sel ? Colors.white : const Color(0xFF616161);
    final countColor = sel
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF9E9E9E);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: sel ? active : const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onTabChanged(index),
            child: SizedBox(
              height: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    countLabel,
                    style: TextStyle(
                      color: countColor,
                      fontWeight: FontWeight.w400,
                      fontSize: 10,
                      height: 1.1,
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
