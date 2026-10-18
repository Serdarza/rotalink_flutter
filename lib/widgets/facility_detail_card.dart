import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/facility_address_repository.dart';
import '../map_location_state.dart';
import '../models/misafirhane.dart';
import '../services/calendar_event_service.dart';
import '../services/view_counter_service.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';
import '../utils/il_ilce.dart';
import 'distance_permission_chip.dart';
import 'facility_compare_widgets.dart';
import 'facility_info_error_report.dart';
import 'facility_overnight_price_box.dart';
import 'facility_stay_eligibility_card.dart';
import 'view_count_label.dart';

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

  @override
  Widget build(BuildContext context) {
    final m = FacilityAddressRepository.instance.resolveFacility(misafirhane);
    final tip = m.tip.trim();
    final il = m.il.trim();
    final ilce = m.ilce.trim();
    final adres = m.adres.trim();
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? const Color(0xFF151A1C) : AppColors.canvas;
    final cardBg = isDark ? const Color(0xFF1E2528) : Colors.white;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : AppColors.textStrongOf(context).withValues(alpha: 0.55);
    final titleColor = isDark
        ? Colors.white.withValues(alpha: 0.96)
        : AppColors.textStrongOf(context);
    final hairline = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppColors.primary.withValues(alpha: 0.08);

    return ViewRecorder(
      viewId: ViewCounterService.keyFor(
        ViewCategory.konaklama,
        misafirhane.il,
        misafirhane.isim,
      ),
      child: Material(
        color: bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: cardBg,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 14, 10),
                child: Row(
                  children: [
                    Material(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : AppColors.primary.withValues(alpha: 0.08),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onBack,
                        customBorder: const CircleBorder(),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.arrow_back_rounded,
                            size: 22,
                            color: isDark ? Colors.white : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Listeye dön',
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Konaklama detayı',
                            style: TextStyle(
                              color: muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.bed_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
            Container(height: 1, color: hairline),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                physics: const ClampingScrollPhysics(),
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: hairline),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: 0.06,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.isim.trim().isEmpty ? 'Tesis' : m.isim.trim(),
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (il.isNotEmpty ||
                              tip.isNotEmpty ||
                              ilce.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (il.isNotEmpty)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.location_city_outlined,
                                        size: 15,
                                        color: muted,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        IlIlce.label(il, ilce),
                                        style: TextStyle(
                                          color: muted,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                if (tip.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      tip,
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (adres.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 16,
                                  color: muted,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    adres,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 13,
                                      height: 1.35,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          DistancePermissionChip(
                            userLocation: mapLocationState.userLocation,
                            locationPermissionGranted:
                                mapLocationState.locationPermissionGranted,
                            facilityPoint: LatLng(m.latitude, m.longitude),
                            onRequestLocation: onRequestLocation,
                            spacingAbove: 0,
                            fullWidthSingleLine: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          _DetailAction(
                            icon: Icons.ios_share_rounded,
                            color: AppColors.primary,
                            label: 'Paylaş',
                            onTap: onShare,
                          ),
                          _DetailAction(
                            icon: isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isFavorite
                                ? AraUi.favorite
                                : AppColors.primary,
                            label: 'Favori',
                            onTap: onFavorite,
                          ),
                          _DetailAction(
                            icon: Icons.chat_bubble_outline_rounded,
                            color: AppColors.primary,
                            label: 'Yorum',
                            onTap: onReview,
                          ),
                          _DetailAction(
                            icon: Icons.event_available_outlined,
                            color: AppColors.primary,
                            label: 'Takvim',
                            onTap: () => unawaited(
                              _addToCalendar(
                                context,
                                m.isim.trim().isEmpty ? 'Tesis' : m.isim.trim(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FacilityCompareButton(
                    facility: misafirhane,
                    userLocation: mapLocationState.userLocation,
                  ),
                  const SizedBox(height: 12),
                  FacilityOvernightPriceBox(facility: m),
                  const SizedBox(height: 12),
                  FacilityStayEligibilityCard(facility: m),
                  const SizedBox(height: 12),
                  FacilityInfoErrorReportCard(facility: m),
                ],
              ),
            ),
            Material(
              color: cardBg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: SizedBox(
                  height: 50,
                  child: Row(
                    children: [
                      Expanded(
                        child: _BottomButton(
                          icon: Icons.my_location_outlined,
                          label: 'Haritada göster',
                          color: AppColors.primary,
                          filled: false,
                          onPressed: onShowOnMap,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _BottomButton(
                          icon: Icons.call_rounded,
                          label: 'Ara',
                          color: AppColors.primary,
                          onPressed: onCall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Konaklama detayı: telefonun takvimine etkinlik ekleme ekranını açar.
Future<void> _addToCalendar(BuildContext context, String title) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
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

class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.filled = true,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  /// true: dolu ana eylem. false: açık turkuaz yüzey + ince çerçeve (ikincil).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (!filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: 0.1,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AraUi.primaryActionFill,
          foregroundColor: color,
          elevation: 0,
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AraUi.primaryActionBorder),
          ),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          letterSpacing: 0.1,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size.fromHeight(50),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  // Etiket nötr koyu; renk yalnız ikonda (Booking / Airbnb düzeni).
                  color: AppColors.isDark(context)
                      ? Colors.white.withValues(alpha: 0.85)
                      : AraUi.inactiveForegroundOf(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
