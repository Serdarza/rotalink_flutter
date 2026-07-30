import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../ads/ad_service.dart';
import '../ads/price_unlock_store.dart';
import '../ads/rewarded_unlock_result.dart';
import '../billing/pro_service.dart';
import '../constants/facility_pricing.dart';
import '../data/facility_price_repository.dart';
import '../models/misafirhane.dart';
import '../services/network_service.dart';
import '../theme/app_colors.dart';
import 'facility_price_report_sheet.dart';

/// `fiyatlar.json` kaydını il+isim ile eşleyip gösterir.
///
/// Fiyat varsa: her tesis için 1 ödüllü reklam (Pro = reklamsız).
/// Eşleşme yoksa: "Fiyat Bildir"; açık fiyatta "Yanlış bildir".
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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ProService.instance.isPro.addListener(_onProChanged);
    if (AdService.adsEnabled && !kIsWeb && !ProService.instance.isAdFree) {
      unawaited(AdService.instance.preloadRewarded());
    }
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

  bool get _unlocked {
    if (!AdService.adsEnabled || kIsWeb) return true;
    if (ProService.instance.isAdFree) return true;
    return PriceUnlockStore.isUnlocked(widget.facility.il, widget.facility.isim);
  }

  Future<void> _onUnlockTap() async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      final online = await NetworkService.instance.isConnected();
      if (!mounted) return;

      // İnternet yok → kullanıcıyı kilitleme; bu tesisi ücretsiz aç.
      if (!online) {
        PriceUnlockStore.graceUnlockFacility(
          widget.facility.il,
          widget.facility.isim,
        );
        setState(() {});
        _toast(FacilityPricing.unlockOfflineGrace);
        return;
      }

      unawaited(AdService.instance.preloadRewarded());
      final result = await AdService.instance.showRewardedForPriceUnlock();
      if (!mounted) return;

      switch (result) {
        case RewardedUnlockResult.earned:
        case RewardedUnlockResult.bypass:
          PriceUnlockStore.unlockFacility(
            widget.facility.il,
            widget.facility.isim,
          );
          setState(() {});
        case RewardedUnlockResult.unavailable:
          PriceUnlockStore.graceUnlockFacility(
            widget.facility.il,
            widget.facility.isim,
          );
          setState(() {});
          _toast(FacilityPricing.unlockAdUnavailableGrace);
        case RewardedUnlockResult.dismissed:
          _toast(FacilityPricing.unlockDismissed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
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
      final buttonIcon = _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.play_circle_outline_rounded, size: 20);

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
                            FacilityPricing.lockedBodyNoCredit,
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
                  onPressed: _busy ? null : _onUnlockTap,
                  icon: buttonIcon,
                  label: Text(
                    _busy
                        ? FacilityPricing.unlockLoading
                        : FacilityPricing.unlockWithAdButton,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.55),
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
                      backgroundColor: AppColors.primary.withValues(alpha: 0.06),
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
