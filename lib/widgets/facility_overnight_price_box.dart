import 'dart:async';

import 'package:flutter/material.dart';

import '../billing/pro_service.dart';
import '../constants/facility_pricing.dart';
import '../data/facility_price_repository.dart';
import '../models/misafirhane.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../theme/app_colors.dart';
import 'facility_price_report_sheet.dart';

/// `fiyatlar.json` kaydını il+isim ile eşleyip gösterir.
///
/// Fiyat satırları yalnızca Rotalink Pro aboneliğinde açılır.
/// Eşleşme yoksa: "Fiyat Bildir"; Pro'da açık fiyatta "Fiyatı Güncelle".
class FacilityOvernightPriceBox extends StatefulWidget {
  const FacilityOvernightPriceBox({
    super.key,
    required this.facility,
    this.topSpacing = 0,
  });

  final Misafirhane facility;
  final double topSpacing;

  @override
  State<FacilityOvernightPriceBox> createState() =>
      _FacilityOvernightPriceBoxState();
}

class _FacilityOvernightPriceBoxState extends State<FacilityOvernightPriceBox> {
  @override
  void initState() {
    super.initState();
    ProService.instance.isPro.addListener(_onProChanged);
  }

  @override
  void dispose() {
    ProService.instance.isPro.removeListener(_onProChanged);
    super.dispose();
  }

  void _onProChanged() {
    if (mounted) setState(() {});
  }

  Misafirhane get _priced =>
      FacilityPriceRepository.instance.resolveFacility(widget.facility);

  bool get _unlocked => ProService.instance.isAdFree;

  Future<void> _openPro() async {
    await Navigator.of(context).pushNamed(RotalinkShellRoutes.pro);
  }

  Future<void> _openReport({required bool isCorrection}) async {
    final priced = _priced;
    await showFacilityPriceReportSheet(
      context,
      facility: widget.facility,
      isCorrection: isCorrection,
      currentSivil: priced.fiyatSivil,
      currentKamu: priced.fiyatKamuPersoneli,
      currentKurum: priced.fiyatKurumPersoneli,
    );
  }

  @override
  Widget build(BuildContext context) {
    final priced = _priced;

    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    final surface = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF3F8F9);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : AppColors.primary.withValues(alpha: 0.12);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : AppColors.textPrimary.withValues(alpha: 0.58);
    final valueColor =
        isDark ? Colors.white.withValues(alpha: 0.95) : AppColors.textPrimary;
    final unavailableColor =
        isDark ? const Color(0xFFFF8A80) : const Color(0xFFC62828);
    final titleColor =
        isDark ? Colors.white.withValues(alpha: 0.92) : AppColors.textPrimary;

    if (!priced.hasFiyatBilgisi) {
      return Padding(
        padding: EdgeInsets.only(top: widget.topSpacing),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: AppColors.primary.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            FacilityPricing.missingPriceTitle,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            FacilityPricing.missingPriceBody,
                            style: TextStyle(
                              color: labelColor,
                              fontSize: 12.5,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => unawaited(_openReport(isCorrection: false)),
                  icon: const Icon(Icons.campaign_outlined, size: 20),
                  label: const Text(FacilityPricing.reportPriceButton),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_unlocked) {
      return Padding(
        padding: EdgeInsets.only(top: widget.topSpacing),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 20,
                        color: AppColors.primary.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            FacilityPricing.lockedTitle,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            FacilityPricing.lockedBody,
                            style: TextStyle(
                              color: labelColor,
                              fontSize: 12.5,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => unawaited(_openPro()),
                  icon: const Icon(Icons.workspace_premium_outlined, size: 20),
                  label: const Text(FacilityPricing.unlockWithProButton),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: widget.topSpacing),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Fiyat bilgisi',
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_openReport(isCorrection: true)),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text(FacilityPricing.reportWrongButton),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.45),
                      ),
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.06),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                FacilityPricing.note,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              _PriceRow(
                label: FacilityPricing.sivilLabel,
                defined: priced.fiyatSivilDefined,
                value: priced.fiyatSivil,
                labelColor: labelColor,
                valueColor: valueColor,
                unavailableColor: unavailableColor,
              ),
              const SizedBox(height: 8),
              _PriceRow(
                label: FacilityPricing.kamuLabel,
                defined: priced.fiyatKamuDefined,
                value: priced.fiyatKamuPersoneli,
                labelColor: labelColor,
                valueColor: valueColor,
                unavailableColor: unavailableColor,
              ),
              const SizedBox(height: 8),
              _PriceRow(
                label: FacilityPricing.kurumLabel,
                defined: priced.fiyatKurumDefined,
                value: priced.fiyatKurumPersoneli,
                labelColor: labelColor,
                valueColor: valueColor,
                unavailableColor: unavailableColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.defined,
    required this.value,
    required this.labelColor,
    required this.valueColor,
    required this.unavailableColor,
  });

  final String label;
  final bool defined;
  final String? value;
  final Color labelColor;
  final Color valueColor;
  final Color unavailableColor;

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color color;
    if (!defined) {
      text = 'Belirtilmedi';
      color = labelColor;
    } else if (value == null) {
      text = FacilityPricing.unavailableLabel;
      color = unavailableColor;
    } else {
      text = value!;
      color = valueColor;
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: color,
              fontSize: 13.5,
              height: 1.25,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
