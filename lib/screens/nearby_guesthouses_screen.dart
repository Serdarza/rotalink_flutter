import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../data/firebase_rota_repository.dart';
import '../data/facility_address_repository.dart';
import '../data/facility_price_repository.dart';
import '../kami/engine/city_resolver.dart';
import '../kami/recommendation/distance_service.dart';
import '../models/misafirhane.dart';
import '../providers/facility_filter_provider.dart';
import '../services/nearby_guesthouses.dart';
import '../services/nearby_location_access.dart';
import '../services/simple_location_service.dart';
import '../theme/app_colors.dart';
import '../utils/main_map_search.dart';
import '../utils/best_value_facility.dart';
import '../widgets/best_value_pro_card.dart';
import '../widgets/facility_type_filter_chips.dart';
import '../widgets/nearby_guesthouse_card.dart';

/// Uses the shared cache and the existing GPS-to-province resolver.
class NearbyGuesthousesScreen extends StatefulWidget {
  const NearbyGuesthousesScreen({
    super.key,
    required this.repository,
    required this.onOpenFacility,
    this.location = const NearbyLocationAccess(),
  });
  final FirebaseRotaRepository repository;
  final ValueChanged<Misafirhane> onOpenFacility;
  final NearbyLocationAccess location;
  @override
  State<NearbyGuesthousesScreen> createState() =>
      _NearbyGuesthousesScreenState();
}

class _NearbyGuesthousesScreenState extends State<NearbyGuesthousesScreen>
    with WidgetsBindingObserver {
  late final _stream = widget.repository.watchRoot();
  Position? _position;
  bool _busy = false;
  bool _settings = false;
  bool _gpsOff = false;
  bool _dialogOpen = false;
  bool _waitingForSettings = false;
  String _message = '';
  bool _usingRecentPosition = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_locate(requestPermission: true));
    });
    unawaited(_prepareAddresses());
    unawaited(_preparePrices());
  }

  Future<void> _preparePrices() async {
    if (FacilityPriceRepository.instance.isReady) return;
    try {
      await FacilityPriceRepository.instance.ensureLocalDataReady();
      if (mounted) setState(() {});
    } catch (_) {
      // The list remains available even when prices cannot be loaded.
    }
  }

  Future<void> _prepareAddresses() async {
    if (FacilityAddressRepository.instance.count > 0) return;
    try {
      await FacilityAddressRepository.instance.ensureLocalDataReady();
      if (mounted) setState(() {});
    } catch (_) {
      // Cached/root address fields remain usable without the overlay.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _waitingForSettings &&
        !_busy &&
        !_dialogOpen) {
      _waitingForSettings = false;
      unawaited(_locate(requestPermission: true, showPrompt: false));
    }
  }

  Future<void> _openSettings() async {
    _waitingForSettings = true;
    try {
      final opened = _gpsOff
          ? await widget.location.openLocationSettings()
          : await widget.location.openAppSettings();
      if (!mounted || opened) return;
      _waitingForSettings = false;
      setState(
        () => _message =
            'Ayarlar açılamadı. Telefon ayarlarından konumu açıp tekrar deneyin.',
      );
    } catch (_) {
      _waitingForSettings = false;
      if (mounted) {
        setState(
          () => _message =
              'Ayarlar açılamadı. Telefon ayarlarından konumu açıp tekrar deneyin.',
        );
      }
    }
  }

  Future<void> _showLocationPrompt() async {
    if (!mounted || _dialogOpen) return;
    _dialogOpen = true;
    bool? open;
    try {
      open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.location_on_outlined,
            color: AppColors.primary,
          ),
          title: Text(_gpsOff ? 'Konumunuz kapalı' : 'Konum izni gerekli'),
          content: Text(
            _gpsOff
                ? 'Yakınınızdaki misafirhaneleri gösterebilmek için telefonunuzun konumunu açın.'
                : 'Yakınınızdaki misafirhaneleri gösterebilmek için uygulama ayarlarından konum izni verin.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Şimdi değil'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_gpsOff ? 'Konumu aç' : 'Ayarlara git'),
            ),
          ],
        ),
      );
    } finally {
      _dialogOpen = false;
    }
    if (open == true && mounted) await _openSettings();
  }

  Future<void> _locate({
    required bool requestPermission,
    bool showPrompt = true,
  }) async {
    if (!mounted || _busy) return;
    setState(() {
      _busy = true;
      if (!NearbyLocationAccess.isRecent(_position)) _position = null;
      _message = '';
    });
    bool gpsOff = false, settings = false;
    Position? position = _position;
    String message = '';
    try {
      gpsOff = !await widget.location.isEnabled().timeout(
        const Duration(seconds: 3),
      );
      if (gpsOff) {
        position = null;
        message = 'Misafirhaneleri görmek için konumunuzu açın.';
      } else {
        var granted = await widget.location.isGranted().timeout(
          const Duration(seconds: 3),
        );
        if (!granted && requestPermission) {
          final outcome = await widget.location.requestPermission().timeout(
            const Duration(seconds: 30),
          );
          granted = outcome == PermissionRequestOutcome.granted;
          settings = outcome == PermissionRequestOutcome.deniedForever;
        }
        if (granted) {
          try {
            final recent = await widget.location.lastKnownPosition().timeout(
              const Duration(milliseconds: 800),
              onTimeout: () => null,
            );
            if (NearbyLocationAccess.isRecent(recent)) position = recent;
          } catch (_) {}
          if (!mounted) return;
          if (position != null) {
            setState(() {
              _position = position;
              _usingRecentPosition = true;
            });
          }
          try {
            final fresh = await widget.location.currentPosition().timeout(
              const Duration(seconds: 8),
            );
            if (!NearbyLocationAccess.hasValidCoordinates(fresh)) {
              throw const FormatException('Invalid coordinates');
            }
            position = fresh;
            _usingRecentPosition = false;
          } catch (_) {
            if (!NearbyLocationAccess.isRecent(position)) position = null;
            message = position == null
                ? 'Konum henüz alınamadı. Açık bir alanda tekrar deneyebilirsiniz.'
                : 'Güncel konum alınamadı; yakın zamanda alınan konumunuz gösteriliyor.';
          }
        } else {
          position = null;
          message =
              'Yakın misafirhaneleri listelemek için konum izni gerekiyor.';
        }
      }
    } catch (_) {
      position = null;
      message = 'Konum alınamadı. Lütfen tekrar deneyin.';
    }
    if (!mounted) return;
    setState(() {
      _position = position;
      _message = message;
      _gpsOff = gpsOff;
      _settings = settings;
      _busy = false;
    });
    if (showPrompt && (gpsOff || settings)) await _showLocationPrompt();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      facilityTypeFilterProvider.overrideWith((ref) => kFacilityFilterAll),
    ],
    child: Scaffold(
      backgroundColor: AppColors.canvasOf(context),
      appBar: AppBar(
        title: const Text(
          'Yakınımdaki Misafirhaneler',
          maxLines: 2,
          style: TextStyle(fontSize: 18),
        ),
      ),
      body: StreamBuilder<RotaDataState>(
        stream: _stream,
        initialData: widget.repository.currentState,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final loadingData = data == null || !data.initialLoadCompleted;
          final facilities = data == null
              ? <Misafirhane>[]
              : MainMapSearch.tesisKaynagiArama(
                  aramaIcinTumTesisler: data.aramaIcinTumTesisler,
                  misafirhaneler: data.misafirhaneler,
                );
          final position = _position;
          final city = position == null
              ? null
              : KamiDistanceService.nearestProvinceName(
                  LatLng(position.latitude, position.longitude),
                );
          final inCity = city == null
              ? <Misafirhane>[]
              : facilities
                    .where((f) => KamiCityResolver.sameCity(f.il, city))
                    .toList();
          final cityLabel = inCity.isEmpty ? city : inCity.first.il;
          return Consumer(
            builder: (context, ref, _) {
              final type = ref.watch(facilityTypeFilterProvider);
              final eligible = inCity
                  .where((f) => facilityMatchesTypeFilter(f.tip, type))
                  .toList();
              final nearby = position == null
                  ? <NearbyGuesthouse>[]
                  : NearbyGuesthouses.find(
                      eligible,
                      position.latitude,
                      position.longitude,
                      radiusKm: double.infinity,
                    );
              // Missing coordinates never receive an invented distance; show last.
              final seen = nearby
                  .map((n) => n.facility.stableFacilityId)
                  .toSet();
              final withoutDistance =
                  eligible.where((f) => seen.add(f.stableFacilityId)).toList()
                    ..sort((a, b) => a.isim.compareTo(b.isim));
              final rows = [
                ...nearby.map((n) => n.facility),
                ...withoutDistance,
              ];
              final bestValue = position == null
                  ? null
                  : pickBestValueFacility(
                      rows.map(NearbyGuesthouseCard.displayFacility).toList(),
                    );
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if ((_busy && position == null) || loadingData)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: LinearProgressIndicator(),
                            ),
                          if (_message.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(_message),
                            ),
                          if (cityLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '$cityLabel · Yakından uzağa',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () {
                                    if (_gpsOff || _settings) {
                                      unawaited(_showLocationPrompt());
                                    } else {
                                      unawaited(
                                        _locate(requestPermission: true),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.my_location),
                            label: Text(
                              _busy && position == null
                                  ? 'Konum alınıyor…'
                                  : _gpsOff
                                  ? 'Konumu aç'
                                  : _settings
                                  ? 'Konum izni ayarları'
                                  : position == null
                                  ? 'Tekrar dene'
                                  : 'Konumumu yenile',
                            ),
                          ),
                          if (_busy && position != null)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'Konumunuz arka planda yenileniyor.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          if (_usingRecentPosition && position != null)
                            Text(
                              'Son 2 dakika içinde alınan konum',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMutedOf(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (position != null) ...[
                    const SliverToBoxAdapter(child: FacilityTypeFilterChips()),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('${rows.length} tesis · Mesafe (Kuş Uçuşu)'),
                      ),
                    ),
                  ],
                  if (position != null &&
                      rows.isEmpty &&
                      !_busy &&
                      !loadingData)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Bulunduğunuz ilde seçili türde kayıtlı misafirhane bulunamadı.',
                        ),
                      ),
                    ),
                  if (bestValue != null)
                    SliverToBoxAdapter(
                      child: BestValueProCard(
                        pick: bestValue,
                        onOpenFacility: () =>
                            widget.onOpenFacility(bestValue.facility),
                      ),
                    ),
                  SliverList.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final f = rows[index];
                      return NearbyGuesthouseCard(
                        facility: FacilityAddressRepository.instance
                            .resolveFacility(f),
                        distanceKm: index < nearby.length
                            ? nearby[index].km
                            : null,
                        onTap: () => widget.onOpenFacility(f),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 72)),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}
