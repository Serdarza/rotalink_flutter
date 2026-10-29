import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../billing/price_access.dart';
import '../billing/pro_service.dart';
import '../constants/facility_pricing.dart';
import '../constants/store_links.dart';
import '../data/facility_address_repository.dart';
import '../data/facility_price_repository.dart';
import '../data/favorites_repository.dart';
import '../map_location_state.dart';
import '../models/misafirhane.dart';
import '../navigator_keys.dart';
import '../screens/yorum_screen.dart';
import '../services/review_repository.dart';
import '../services/simple_location_service.dart';
import '../theme/app_colors.dart';
import '../utils/best_value_facility.dart';
import '../utils/facility_phone_dialer.dart';
import '../utils/il_ilce.dart';
import '../utils/maps_launch.dart';
import '../utils/search_normalize.dart';
import 'facility_detail_card.dart';
import 'facility_sort_bar.dart';

const _gold = Color(0xFFF2C14E);
const _goldDeep = Color(0xFFB8860B);
const _distance = Distance();

enum _PriceSort { lowToHigh, highToLow, nearToFar }

Future<void> showNationwidePriceSheet(
  BuildContext context, {
  required List<Misafirhane> facilities,
  required VoidCallback onOpenPro,
}) async {
  await FacilityPriceRepository.instance.ensureLocalDataReady();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return _NationwidePriceSheet(
        facilities: facilities,
        onOpenPro: () {
          Navigator.of(ctx).pop();
          onOpenPro();
        },
      );
    },
  );
}

class _NationwidePriceSheet extends StatefulWidget {
  const _NationwidePriceSheet({
    required this.facilities,
    required this.onOpenPro,
  });

  final List<Misafirhane> facilities;
  final VoidCallback onOpenPro;

  @override
  State<_NationwidePriceSheet> createState() => _NationwidePriceSheetState();
}

class _NationwidePriceSheetState extends State<_NationwidePriceSheet> {
  final _favoritesRepo = FavoritesRepository();
  final _location = MapLocationState();
  BestValueBasis _basis = BestValueBasis.sivil;
  _PriceSort _sort = _PriceSort.lowToHigh;
  Misafirhane? _detail;
  List<Misafirhane> _favorites = const [];

  @override
  void initState() {
    super.initState();
    ProService.instance.isPro.addListener(_refresh);
    FacilityPriceRepository.instance.updates.addListener(_refresh);
    _location.addListener(_refresh);
    unawaited(_loadFavorites());
    unawaited(_hydrateLocation(request: false));
  }

  @override
  void dispose() {
    ProService.instance.isPro.removeListener(_refresh);
    FacilityPriceRepository.instance.updates.removeListener(_refresh);
    _location.removeListener(_refresh);
    _location.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFavorites() async {
    final list = await _favoritesRepo.load();
    if (mounted) setState(() => _favorites = list);
  }

  Future<void> _hydrateLocation({required bool request}) async {
    final granted = request
        ? await SimpleLocationService.ensureLocationPermissionFromUserAction()
        : await SimpleLocationService.isLocationGranted();
    if (!granted) {
      _location.update(null, false);
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
      _location.update(LatLng(pos.latitude, pos.longitude), true);
    } catch (_) {
      _location.update(null, true);
    }
  }

  List<(Misafirhane, FacilityNightPrice)> _ordered() {
    final priced = sortFacilitiesByPrice(widget.facilities, _basis).priced;
    switch (_sort) {
      case _PriceSort.lowToHigh:
        return priced;
      case _PriceSort.highToLow:
        return priced.reversed.toList();
      case _PriceSort.nearToFar:
        final user = _location.userLocation;
        if (user == null) return priced;
        final copy = [...priced];
        copy.sort((a, b) {
          final da = _distance.as(
            LengthUnit.Meter,
            user,
            LatLng(a.$1.latitude, a.$1.longitude),
          );
          final db = _distance.as(
            LengthUnit.Meter,
            user,
            LatLng(b.$1.latitude, b.$1.longitude),
          );
          return da.compareTo(db);
        });
        return copy;
    }
  }

  Future<void> _selectSort(_PriceSort sort) async {
    if (!PriceAccess.unlocked) {
      widget.onOpenPro();
      return;
    }
    setState(() => _sort = sort);
    if (sort == _PriceSort.nearToFar && _location.userLocation == null) {
      await _hydrateLocation(request: true);
    }
  }

  Future<void> _dial(Misafirhane facility) async {
    await FacilityPhoneDialer.open(context, facility);
  }

  Future<void> _share(Misafirhane m) async {
    final phone = m.telefonNumaralari.join(' / ');
    await Share.share(
      StoreLinks.shareMessage(m.isim, [
        if (phone.isNotEmpty) 'Telefon: $phone',
      ]),
    );
  }

  Future<void> _toggleFavorite(Misafirhane m) async {
    final wasFav = _favorites.any((f) => f.sameFavoriteIdentity(m));
    await _favoritesRepo.toggle(m);
    await _loadFavorites();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasFav ? 'Favorilerden çıkarıldı' : 'Favorilere eklendi'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = PriceAccess.unlocked;
    final priced = _ordered();
    final stats = _pricedStats(widget.facilities);
    final height = MediaQuery.sizeOf(context).height * 0.92;
    final detail = _detail;

    return SizedBox(
      height: height,
      child: Material(
        color: AppColors.canvasOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: detail != null
              ? FacilityDetailCard(
                  misafirhane: detail,
                  mapLocationState: _location,
                  isFavorite: _favorites.any(
                    (f) => f.sameFavoriteIdentity(detail),
                  ),
                  onBack: () => setState(() => _detail = null),
                  onCall: () => unawaited(_dial(detail)),
                  onShare: () => unawaited(_share(detail)),
                  onFavorite: () => unawaited(_toggleFavorite(detail)),
                  onInspect: () => unawaited(
                    openMapSearch(context, detail.il, detail.isim),
                  ),
                  onReview: () => unawaited(
                    pushOnShellNavigator<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => YorumScreen(
                          facilityId: ReviewRepository.sanitizeFacilityId(
                            detail.stableFacilityId,
                          ),
                          facilityName: detail.isim,
                        ),
                      ),
                    ),
                  ),
                  onShowOnMap: () => unawaited(
                    openMapSearch(context, detail.il, detail.isim),
                  ),
                  onRequestLocation: () => _hydrateLocation(request: true),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.borderOf(context),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  FacilityPricing.nationwideTitle,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textStrongOf(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  FacilityPricing.nationwideSubtitle,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textMutedOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Kapat',
                          ),
                        ],
                      ),
                    ),
                    _SortRow(
                      sort: _sort,
                      basis: _basis,
                      unlocked: unlocked,
                      onSort: (s) => unawaited(_selectSort(s)),
                      onBasis: (b) {
                        if (!unlocked) {
                          widget.onOpenPro();
                          return;
                        }
                        setState(() => _basis = b);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        unlocked
                            ? '${priced.length} tesis'
                            : FacilityPricing.nationwideTeaserCount(
                                stats.tesis,
                                stats.il,
                              ),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMutedOf(context),
                        ),
                      ),
                    ),
                    Expanded(
                      child: unlocked
                          ? _FacilityList(
                              items: priced,
                              showDistance: _sort == _PriceSort.nearToFar,
                              user: _location.userLocation,
                              onOpen: (m) => setState(() => _detail = m),
                            )
                          : _BlurredPreview(
                              items: priced,
                              onOpenPro: widget.onOpenPro,
                            ),
                    ),
                  ],
                ),
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.sort,
    required this.basis,
    required this.unlocked,
    required this.onSort,
    required this.onBasis,
  });

  final _PriceSort sort;
  final BestValueBasis basis;
  final bool unlocked;
  final ValueChanged<_PriceSort> onSort;
  final ValueChanged<BestValueBasis> onBasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SortChip(
                  label: FacilityPricing.nationwideSortLow,
                  selected: sort == _PriceSort.lowToHigh,
                  locked: !unlocked,
                  onTap: () => onSort(_PriceSort.lowToHigh),
                ),
                const SizedBox(width: 6),
                _SortChip(
                  label: FacilityPricing.nationwideSortHigh,
                  selected: sort == _PriceSort.highToLow,
                  locked: !unlocked,
                  onTap: () => onSort(_PriceSort.highToLow),
                ),
                const SizedBox(width: 6),
                _SortChip(
                  label: FacilityPricing.nationwideSortNear,
                  selected: sort == _PriceSort.nearToFar,
                  locked: !unlocked,
                  onTap: () => onSort(_PriceSort.nearToFar),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<BestValueBasis>(
            segments: const [
              ButtonSegment(
                value: BestValueBasis.sivil,
                label: Text(FacilityPricing.sivilLabel),
              ),
              ButtonSegment(
                value: BestValueBasis.kamu,
                label: Text(FacilityPricing.kamuLabel),
              ),
            ],
            selected: {basis},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onBasis(s.first),
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
              selectedBackgroundColor: AppColors.primary.withValues(alpha: 0.12),
              selectedForegroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.primary;
    return Material(
      color: selected
          ? AppColors.primary
          : AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (locked) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_gold, _goldDeep]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'PRO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FacilityList extends StatelessWidget {
  const _FacilityList({
    required this.items,
    required this.showDistance,
    required this.user,
    required this.onOpen,
  });

  final List<(Misafirhane, FacilityNightPrice)> items;
  final bool showDistance;
  final LatLng? user;
  final ValueChanged<Misafirhane> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          FacilityPricing.nationwideEmpty,
          style: TextStyle(color: AppColors.textMutedOf(context)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final (m, price) = items[i];
        String? distanceLabel;
        if (showDistance && user != null) {
          final meters = _distance.as(
            LengthUnit.Meter,
            user!,
            LatLng(m.latitude, m.longitude),
          );
          distanceLabel = meters >= 1000
              ? '${(meters / 1000).toStringAsFixed(1)} km'
              : '${meters.round()} m';
        }
        return _PricedRow(
          facility: m,
          price: price,
          rank: i + 1,
          distanceLabel: distanceLabel,
          onTap: () => onOpen(m),
        );
      },
    );
  }
}

class _BlurredPreview extends StatelessWidget {
  const _BlurredPreview({
    required this.items,
    required this.onOpenPro,
  });

  final List<(Misafirhane, FacilityNightPrice)> items;
  final VoidCallback onOpenPro;

  @override
  Widget build(BuildContext context) {
    final preview = items.take(8).toList();
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              itemCount: preview.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final (m, price) = preview[i];
                return _PricedRow(
                  facility: m,
                  price: price,
                  rank: i + 1,
                  onTap: () {},
                );
              },
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0E5C68), Color(0xFF083E46)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _gold.withValues(alpha: 0.7)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      FacilityPricing.nationwideTeaserTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      FacilityPricing.nationwideTeaserBody,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onOpenPro,
                        style: FilledButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: const Color(0xFF3A2A00),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        child: const Text(FacilityPricing.nationwideTeaserCta),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

({int tesis, int il}) _pricedStats(List<Misafirhane> facilities) {
  final cities = <String>{};
  var tesis = 0;
  for (final m in facilities) {
    final has = singleNightPriceFor(m, BestValueBasis.sivil) != null ||
        singleNightPriceFor(m, BestValueBasis.kamu) != null;
    if (!has) continue;
    tesis++;
    cities.add(normalizeForSearch(m.il));
  }
  return (tesis: tesis, il: cities.length);
}

class _PricedRow extends StatelessWidget {
  const _PricedRow({
    required this.facility,
    required this.price,
    required this.rank,
    required this.onTap,
    this.distanceLabel,
  });

  final Misafirhane facility;
  final FacilityNightPrice price;
  final int rank;
  final VoidCallback onTap;
  final String? distanceLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = FacilityAddressRepository.instance.resolveFacility(facility);
    final konum = IlIlce.label(resolved.il, resolved.ilce);
    final sub = [
      if (konum.isNotEmpty) konum,
      if (distanceLabel != null) distanceLabel!,
    ].join(' · ');
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primarySoftOf(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resolved.isim,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppColors.textStrongOf(context),
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMutedOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              FacilityNightPriceTag(price: price),
            ],
          ),
        ),
      ),
    );
  }
}
