import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../constants/facility_pricing.dart';
import '../constants/facility_stay_rules.dart';
import '../data/facility_address_repository.dart';
import '../data/facility_compare_selection.dart';
import '../models/misafirhane.dart';
import '../theme/app_colors.dart';
import '../utils/best_value_facility.dart';
import '../widgets/facility_stay_eligibility_card.dart' show stayAccessColor, stayCivilBadge;
import '../widgets/facility_tariff_view.dart' show formatTl;

const _amber = Color(0xFFE08A00);
const _cheapest = Color(0xFF2E7D32);

/// Pro: seçilen 2–3 tesisin fiyat, uzaklık, tür ve sivil konaklama durumunu yan yana gösterir.
class FacilityCompareScreen extends StatelessWidget {
  const FacilityCompareScreen({super.key, this.userLocation});

  final LatLng? userLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFB),
      appBar: AppBar(title: const Text(FacilityPricing.compareTitle)),
      body: ValueListenableBuilder<List<Misafirhane>>(
        valueListenable: FacilityCompareSelection.instance,
        builder: (context, selected, _) {
          if (selected.length < 2) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  FacilityPricing.compareNeedTwo,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.7), fontSize: 15),
                ),
              ),
            );
          }
          final facilities = [
            for (final m in selected) FacilityAddressRepository.instance.resolveFacility(m),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _HeaderRow(facilities: facilities, originals: selected),
              const SizedBox(height: 10),
              _PriceRow(
                label: FacilityPricing.compareRowPriceSivil,
                facilities: facilities,
                basis: BestValueBasis.sivil,
              ),
              _PriceRow(
                label: FacilityPricing.compareRowPriceKamu,
                facilities: facilities,
                basis: BestValueBasis.kamu,
              ),
              if (userLocation != null)
                _TextRow(
                  label: FacilityPricing.compareRowDistance,
                  cells: [for (final m in facilities) _distanceLabel(userLocation!, m)],
                ),
              _TextRow(
                label: FacilityPricing.compareRowType,
                cells: [for (final m in facilities) m.tip.trim().isEmpty ? '—' : m.tip.trim()],
              ),
              _CivilRow(facilities: facilities),
              _TextRow(
                label: FacilityPricing.compareRowLocation,
                cells: [
                  for (final m in facilities)
                    m.ilce.trim().isEmpty ? m.il.trim() : '${m.ilce.trim()} / ${m.il.trim()}',
                ],
              ),
              const SizedBox(height: 14),
              Text(
                FacilityPricing.note,
                style: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.55), fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _distanceLabel(LatLng user, Misafirhane m) {
    final km = const Distance().as(LengthUnit.Meter, user, LatLng(m.latitude, m.longitude)) / 1000;
    if (km < 10) return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
    return '${km.round()} km';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.cells});

  final String label;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, c) in cells.indexed) ...[
                  if (i > 0)
                    VerticalDivider(width: 12, color: AppColors.primary.withValues(alpha: 0.08)),
                  Expanded(child: c),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.facilities, required this.originals});

  final List<Misafirhane> facilities;
  final List<Misafirhane> originals;

  @override
  Widget build(BuildContext context) {
    return _Section(
      label: FacilityPricing.compareTitle,
      cells: [
        for (final (i, m) in facilities.indexed)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.isim.trim(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const Spacer(),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => FacilityCompareSelection.instance.remove(originals[i]),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close_rounded, size: 15, color: Color(0xFF8A9A9F)),
                      SizedBox(width: 3),
                      Text(
                        FacilityPricing.compareRemove,
                        style: TextStyle(color: Color(0xFF8A9A9F), fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.facilities, required this.basis});

  final String label;
  final List<Misafirhane> facilities;
  final BestValueBasis basis;

  @override
  Widget build(BuildContext context) {
    final prices = [for (final m in facilities) singleNightPriceFor(m, basis)];
    final amounts = prices.whereType<FacilityNightPrice>().map((p) => p.amount).toList();
    final min = amounts.length >= 2 ? amounts.reduce((a, b) => a < b ? a : b) : null;
    return _Section(
      label: label,
      cells: [
        for (final p in prices)
          if (p == null)
            const Text(
              FacilityPricing.compareNoPrice,
              style: TextStyle(color: Color(0xFF8A9A9F), fontSize: 13, fontWeight: FontWeight.w600),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatTl(p.amount),
                  style: TextStyle(
                    color: p.amount == min ? _cheapest : AppColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (p.amount == min) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _cheapest.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      FacilityPricing.compareCheapest,
                      style: TextStyle(color: _cheapest, fontSize: 10.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
                if (!p.confirmed) ...[
                  const SizedBox(height: 4),
                  Text(
                    p.dogrulama?.label ?? FacilityPricing.unverifiedPrice,
                    style: const TextStyle(color: _amber, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
      ],
    );
  }
}

class _TextRow extends StatelessWidget {
  const _TextRow({required this.label, required this.cells});

  final String label;
  final List<String> cells;

  @override
  Widget build(BuildContext context) {
    return _Section(
      label: label,
      cells: [
        for (final c in cells)
          Text(
            c,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
      ],
    );
  }
}

class _CivilRow extends StatelessWidget {
  const _CivilRow({required this.facilities});

  final List<Misafirhane> facilities;

  @override
  Widget build(BuildContext context) {
    return _Section(
      label: FacilityPricing.compareRowCivil,
      cells: [
        for (final m in facilities)
          Builder(builder: (_) {
            final access = FacilityStayRules.forFacility(m).civilAccess;
            final color = stayAccessColor(access);
            return Text(
              stayCivilBadge(access),
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.3),
            );
          }),
      ],
    );
  }
}
