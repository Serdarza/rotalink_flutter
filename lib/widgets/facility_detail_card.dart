import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/facility_address_repository.dart';
import '../map_location_state.dart';
import '../models/misafirhane.dart';
import '../services/calendar_event_service.dart';
import '../services/view_counter_service.dart';
import '../theme/app_colors.dart';
import '../utils/il_ilce.dart';
import '../data/facility_compare_selection.dart';
import '../billing/price_access.dart';
import '../utils/geo_helpers.dart';
import '../utils/safe_map_coordinates.dart';
import 'facility_detail_action.dart';
import 'facility_weather_badge.dart';
import 'view_count_label.dart';
import 'facility_compare_widgets.dart';
import 'facility_info_error_report.dart';
import 'facility_overnight_price_box.dart';
import 'facility_stay_eligibility_card.dart';

/// Tesis listesinden açılan profesyonel detay kartı (Geri ile listeye dönüş).
class FacilityDetailCard extends StatelessWidget {
  const FacilityDetailCard({
    super.key,
    required this.misafirhane,
    required this.mapLocationState,
    required this.isFavorite,
    required this.onBack,
    required this.onCall,
    required this.onShare,
    required this.onFavorite,
    required this.onInspect,
    required this.onReview,
    required this.onShowOnMap,
    required this.onRequestLocation,
    this.fromMap = false,
    this.showInfoReport = true,
  });

  final Misafirhane misafirhane;
  final MapLocationState mapLocationState;
  final bool isFavorite;
  final VoidCallback onBack;
  final VoidCallback onCall;
  final VoidCallback onShare;
  final VoidCallback onFavorite;
  final VoidCallback onInspect;
  final VoidCallback onReview;
  final VoidCallback onShowOnMap;
  final Future<void> Function() onRequestLocation;
  final bool fromMap;
  final bool showInfoReport;

  @override
  Widget build(BuildContext context) {
    final m = FacilityAddressRepository.instance.resolveFacility(misafirhane);
    final validPoint =
        m.latitude != 0 &&
        m.longitude != 0 &&
        isValidWgs84LatLng(m.latitude, m.longitude);
    final distance = mapLocationState.locationPermissionGranted && validPoint
        ? distanceMetersBetween(
            mapLocationState.userLocation,
            LatLng(m.latitude, m.longitude),
          )
        : null;
    final distanceLabel = distance == null
        ? null
        : 'Size uzaklık: ${distance >= 1000 ? '${(distance / 1000).toStringAsFixed(1).replaceAll('.', ',')} km' : '${distance.round()} m'} (Kuş Uçuşu)';
    return ViewRecorder(
      viewId: ViewCounterService.keyFor(
        ViewCategory.konaklama,
        misafirhane.il,
        misafirhane.isim,
      ),
      child: Material(
        color: AppColors.canvasOf(context),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Geri',
                      onPressed: onBack,
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        width: 30,
                        height: 30,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Rotalink',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 5, 12, 12),
                  children: [
                    _FacilityHero(facility: m),
                    const SizedBox(height: 10),
                    _Surface(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (m.adres.trim().isNotEmpty)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.location_on_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      m.adres.trim(),
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (m.adres.trim().isNotEmpty &&
                                distanceLabel != null)
                              const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (distanceLabel != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.09,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      distanceLabel,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Surface(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: FacilityDetailAction(
                                    icon: isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    label: 'Favori',
                                    color: isFavorite
                                        ? const Color(0xFFE53935)
                                        : AppColors.primary,
                                    selected: isFavorite,
                                    onTap: onFavorite,
                                  ),
                                ),
                                Expanded(
                                  child: FacilityDetailAction(
                                    icon: Icons.event_available_outlined,
                                    label: 'Takvim',
                                    onTap: () => unawaited(
                                      _addToCalendar(
                                        context,
                                        m.isim.trim().isEmpty
                                            ? 'Tesis'
                                            : m.isim.trim(),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: FacilityDetailAction(
                                    icon: Icons.chat_bubble_outline_rounded,
                                    label: 'Yorum',
                                    onTap: onReview,
                                  ),
                                ),
                                Expanded(
                                  child: FacilityCompareButton(
                                    facility: misafirhane,
                                    userLocation: mapLocationState.userLocation,
                                    compactAction: true,
                                  ),
                                ),
                                Expanded(
                                  child: FacilityDetailAction(
                                    icon: Icons.ios_share_rounded,
                                    label: 'Paylaş',
                                    onTap: onShare,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ValueListenableBuilder<List<Misafirhane>>(
                            valueListenable: FacilityCompareSelection.instance,
                            builder: (context, selected, _) =>
                                PriceAccess.unlocked && selected.length >= 2
                                ? TextButton.icon(
                                    onPressed: () => openFacilityCompare(
                                      context,
                                      userLocation:
                                          mapLocationState.userLocation,
                                    ),
                                    icon: const Icon(
                                      Icons.compare_arrows_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      'Seçilenleri karşılaştır (${selected.length})',
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    FacilityOvernightPriceBox(
                      facility: m,
                      detailPresentation: true,
                    ),
                    const SizedBox(height: 10),
                    FacilityStayEligibilityCard(facility: m, compact: true),
                    if (showInfoReport) ...[
                      const SizedBox(height: 10),
                      FacilityInfoErrorReportCard(facility: m),
                    ],
                    const SizedBox(height: 6),
                  ],
                ),
              ),
              Material(
                color: AppColors.surfaceOf(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _PrimaryAction(
                          icon: Icons.my_location_rounded,
                          label: 'Haritada göster',
                          color: AppColors.primary,
                          onTap: onShowOnMap,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PrimaryAction(
                          icon: Icons.call_rounded,
                          label: 'Ara',
                          color: const Color(0xFF32A818),
                          onTap: onCall,
                        ),
                      ),
                    ],
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

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.borderOf(context)),
      boxShadow: AppColors.isDark(context)
          ? null
          : [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.045),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
    ),
    child: child,
  );
}

class _FacilityHero extends StatelessWidget {
  const _FacilityHero({required this.facility});
  final Misafirhane facility;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Color(0xFF005965), Color(0xFF007F8F), Color(0xFF22AEB4)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow =
              constraints.maxWidth < 310 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                facility.isim.trim().isEmpty ? 'Tesis' : facility.isim.trim(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                ),
              ),
              if (facility.tip.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      facility.tip,
                      style: const TextStyle(
                        color: Color(0xFF007F8F),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              if (facility.il.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    IlIlce.label(facility.il, facility.ilce),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          );
          final weather = ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: narrow ? double.infinity : 91,
            ),
            child: FacilityWeatherBadge(
              key: ValueKey(facility.stableFacilityId),
              facility: facility,
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 54,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.bed_rounded,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(child: title),
                  if (!narrow) ...[const SizedBox(width: 10), weather],
                ],
              ),
              if (narrow)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: weather,
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

Future<void> _addToCalendar(BuildContext context, String title) async {
  final now = DateTime.now();
  const tr = Locale('tr', 'TR');
  final date = await showDatePicker(
    context: context,
    locale: tr,
    initialDate: DateUtils.dateOnly(now).add(const Duration(days: 1)),
    firstDate: DateUtils.dateOnly(now),
    lastDate: now.add(const Duration(days: 730)),
    helpText: 'Tarih seçin',
    cancelText: 'Vazgeç',
    confirmText: 'Tamam',
  );
  if (date == null || !context.mounted) return;
  final time = await showTimePicker(
    context: context,
    initialTime: const TimeOfDay(hour: 14, minute: 0),
    helpText: 'Saat seçin',
    cancelText: 'Vazgeç',
    confirmText: 'Tamam',
    builder: (context, child) {
      return Localizations.override(context: context, locale: tr, child: child);
    },
  );
  if (time == null || !context.mounted) return;
  final begin = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  final ok = await CalendarEventService.openEditor(title: title, begin: begin);
  if (!ok && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Takvim uygulaması açılamadı.')),
    );
  }
}
