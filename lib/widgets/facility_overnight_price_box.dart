import 'dart:async';

import 'package:flutter/material.dart';

import '../billing/free_price_quota.dart';
import '../billing/price_access.dart';
import '../billing/pro_service.dart';
import '../constants/facility_pricing.dart';
import '../data/facility_price_repository.dart';
import '../models/facility_price_entry.dart';
import '../models/facility_tariff.dart';
import '../models/misafirhane.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../theme/app_colors.dart';
import '../utils/stay_cost_calculator.dart';
import 'facility_price_report_sheet.dart';
import 'stay_cost_calculator_sheet.dart';
import 'facility_tariff_view.dart';

/// `fiyatlar.json` kaydını il+isim ile eşleyip gösterir.
///
/// Fiyat satırları Rotalink Pro'da veya ücretsiz tesis hakkıyla açılır.
/// Eşleşme yoksa: "Fiyat Bildir"; Pro'da açık fiyatta "Fiyatı Güncelle".
class FacilityOvernightPriceBox extends StatefulWidget {
  const FacilityOvernightPriceBox({
    super.key,
    required this.facility,
    this.topSpacing = 0,
    this.compact = false,
  });

  final Misafirhane facility;
  final double topSpacing;

  /// Kart / sohbet görünümü: yalnızca özet; detaylı tarife alt sayfada açılır.
  final bool compact;

  @override
  State<FacilityOvernightPriceBox> createState() =>
      _FacilityOvernightPriceBoxState();
}

class _FacilityOvernightPriceBoxState extends State<FacilityOvernightPriceBox> {
  bool _expanded = false;
  bool _unlocking = false;

  @override
  void initState() {
    super.initState();
    ProService.instance.isPro.addListener(_onProChanged);
    FreePriceQuota.instance.unlockedIds.addListener(_onProChanged);
  }

  @override
  void dispose() {
    ProService.instance.isPro.removeListener(_onProChanged);
    FreePriceQuota.instance.unlockedIds.removeListener(_onProChanged);
    super.dispose();
  }

  void _onProChanged() {
    if (mounted) setState(() {});
  }

  Misafirhane get _priced =>
      FacilityPriceRepository.instance.resolveFacility(widget.facility);

  bool get _unlocked =>
      PriceAccess.unlockedFor(widget.facility.stableFacilityId);

  Future<void> _unlockWithFreeQuota() async {
    final quota = FreePriceQuota.instance;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.lock_open_rounded,
          color: AppColors.primary,
          size: 32,
        ),
        title: const Text('Fiyatı ücretsiz gör'),
        content: Text(
          '${widget.facility.isim} tesisinin fiyatları kalıcı olarak açılacak.\n\n'
          'Kalan ücretsiz hakkınız: ${quota.remaining}/${FreePriceQuota.limit}. '
          'Haklar her cihaza bir kez verilir; uygulama silinip yeniden '
          'yüklense de yenilenmez. Tüm tesislerin fiyatları için Rotalink Pro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Fiyatı aç'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _unlocking = true);
    final error = await quota.unlock(widget.facility.stableFacilityId);
    if (!mounted) return;
    setState(() => _unlocking = false);
    final left = quota.remaining;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (left > 0
                  ? 'Fiyatlar açıldı. Kalan ücretsiz hak: $left.'
                  : 'Fiyatlar açıldı. Ücretsiz haklarınız bitti; '
                        'tüm tesisler için Rotalink Pro.'),
        ),
      ),
    );
  }

  Future<void> _openPro() async {
    await Navigator.of(context).pushNamed(RotalinkShellRoutes.pro);
  }

  static PriceMetaFooter _footerFor(FacilityPriceEntry? entry) =>
      PriceMetaFooter(
        gecerlilik: entry?.gecerlilik ?? entry?.tarife?.donem,
        guncelleme: entry?.tarife?.guncelleme,
        dogrulama: entry?.tarife?.dogrulama,
        kaynak: entry?.kaynak,
      );

  Future<void> _openTariffSheet(Misafirhane priced) async {
    final entry = priced.fiyatKaydi;
    final tariff = entry?.tarife;
    if (tariff == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              priced.isim,
              style: Theme.of(
                ctx,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _TariffDetails(tariff: tariff),
            const SizedBox(height: 4),
            _footerFor(entry),
          ],
        ),
      ),
    );
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
    final valueColor = isDark
        ? Colors.white.withValues(alpha: 0.95)
        : AppColors.textPrimary;
    final unavailableColor = isDark
        ? const Color(0xFFFF8A80)
        : const Color(0xFFC62828);
    final titleColor = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : AppColors.textPrimary;

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
                _ProPreview(
                  facility: priced,
                  onTap: () => unawaited(_openPro()),
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
                const SizedBox(height: 4),
                if (FreePriceQuota.instance.remaining > 0)
                  TextButton.icon(
                    onPressed: _unlocking
                        ? null
                        : () => unawaited(_unlockWithFreeQuota()),
                    icon: _unlocking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open_rounded, size: 18),
                    label: Text(
                      'Bu tesisin fiyatını ücretsiz gör '
                      '(${FreePriceQuota.instance.remaining}/${FreePriceQuota.limit} hak)',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Text(
                    'Ücretsiz ${FreePriceQuota.limit} tesis hakkınızı kullandınız.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final entry = priced.fiyatKaydi;
    final tariff = entry?.tarife;
    final hasLegacy =
        entry?.hasLegacyFiyat ??
        (priced.fiyatSivilDefined ||
            priced.fiyatKamuDefined ||
            priced.fiyatKurumDefined);
    final derived = hasLegacy
        ? const <({String label, double min, double max})>[]
        : tariff?.derivedRanges() ?? const [];
    final footer = _footerFor(entry);

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
                      FacilityPricing.currentPricesTitle,
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
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.06,
                      ),
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
              if (hasLegacy) ...[
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
              ] else
                for (final (i, r) in derived.indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _PriceRow(
                    label: r.label,
                    defined: true,
                    value: formatTlRange(r.min, r.max),
                    labelColor: labelColor,
                    valueColor: valueColor,
                    unavailableColor: unavailableColor,
                  ),
                ],
              if (StayCostCalculator.isAvailable(tariff)) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      unawaited(showStayCostCalculator(context, priced)),
                  icon: const Icon(Icons.calculate_outlined, size: 20),
                  label: const Text(FacilityPricing.calcButton),
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
              if (tariff != null) ...[
                const SizedBox(height: 10),
                _DetailToggle(
                  label: widget.compact
                      ? FacilityPricing.showDetailedPrices
                      : _expanded
                      ? FacilityPricing.hideDetailedTariff
                      : FacilityPricing.showDetailedTariff,
                  expanded: !widget.compact && _expanded,
                  onTap: widget.compact
                      ? () => unawaited(_openTariffSheet(priced))
                      : () => setState(() => _expanded = !_expanded),
                ),
                if (!widget.compact)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _expanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _TariffDetails(tariff: tariff),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
              ],
              if (!footer.isEmpty) ...[const SizedBox(height: 10), footer],
            ],
          ),
        ),
      ),
    );
  }
}

/// Kilitli durumda: tesisin gerçek tarife yapısı + maskeli tutarlar
/// ve Pro ile açılacak içeriğin veriden türetilmiş özeti.
class _ProPreview extends StatelessWidget {
  const _ProPreview({required this.facility, required this.onTap});

  final Misafirhane facility;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : AppColors.textPrimary.withValues(alpha: 0.58);
    final titleColor = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : AppColors.textPrimary;
    final entry = facility.fiyatKaydi;
    final tariff = entry?.tarife;
    final firstTable = tariff?.hasTables == true
        ? tariff!.tablolar.first
        : null;

    final Widget sample;
    if (firstTable != null) {
      sample = FacilityTariffView.preview(tariff: tariff!);
    } else {
      final labels = [
        if (facility.fiyatSivilDefined) FacilityPricing.sivilLabel,
        if (facility.fiyatKamuDefined) FacilityPricing.kamuLabel,
        if (facility.fiyatKurumDefined) FacilityPricing.kurumLabel,
      ];
      sample = Column(
        children: [
          for (final label in labels)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const MaskedPrice(),
                ],
              ),
            ),
        ],
      );
    }

    final hiddenRows = tariff == null
        ? 0
        : tariff.tablolar.fold<int>(0, (n, t) => n + t.satirlar.length) -
              (firstTable?.satirlar
                      .take(FacilityTariffView.previewRows)
                      .length ??
                  0);

    final perks = <String>[
      if (tariff != null && tariff.hasTables) ...[
        '${tariff.tablolar.fold<int>(0, (n, t) => n + t.satirlar.length)} '
            'konaklama tipi için ayrı fiyat',
        if (firstTable!.kategoriler.length > 1)
          '${firstTable.kategoriler.map((c) => c.ad).join(' / ')} fiyatları',
      ] else if (entry?.hasLegacyFiyat ?? false)
        'Personel türüne göre gecelik fiyatlar',
      if (StayCostCalculator.isAvailable(tariff)) FacilityPricing.calcPerk,
      if (tariff != null) ..._tariffPerks(tariff),
      if (entry?.kaynak != null || entry?.gecerlilik != null)
        'Fiyat kaynağı ve geçerlilik bilgisi',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tariff?.baslik ?? FacilityPricing.currentPricesTitle,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                FacilityPricing.previewBadge,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: IgnorePointer(child: sample),
        ),
        if (hiddenRows > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+ $hiddenRows konaklama tipi daha',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: labelColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (perks.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            FacilityPricing.proIncludesTitle,
            style: TextStyle(
              color: titleColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          for (final perk in perks)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      perk,
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  static List<String> _tariffPerks(FacilityTariff t) {
    final parts = [
      if (t.kurallar.isNotEmpty) 'tarife kuralları',
      if (t.dahil.isNotEmpty) 'fiyata dahil hizmetler',
      if (t.indirimler.isNotEmpty) 'indirimler',
      if (t.ekUcretler.isNotEmpty) 'ek ücretler',
      if (t.girisSaati != null || t.cikisSaati != null) 'giriş/çıkış saatleri',
    ];
    if (parts.isEmpty) return const [];
    final text = parts.length == 1
        ? parts.single
        : '${parts.sublist(0, parts.length - 1).join(', ')} ve ${parts.last}';
    final first = text[0] == 'i' ? 'İ' : text[0].toUpperCase();
    return ['$first${text.substring(1)}'];
  }
}

class _DetailToggle extends StatelessWidget {
  const _DetailToggle({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.table_rows_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                  Icons.expand_more_rounded,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarife başlığı + dönem ve [FacilityTariffView].
class _TariffDetails extends StatelessWidget {
  const _TariffDetails({required this.tariff});

  final FacilityTariff tariff;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baslik = tariff.baslik ?? FacilityPricing.detailedTariffTitle;
    final sub = [
      if (tariff.donem != null) tariff.donem!,
      if (tariff.birim != null) 'Fiyatlar ${tariff.birim}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          baslik,
          style: TextStyle(
            color: isDark
                ? Colors.white.withValues(alpha: 0.92)
                : AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              sub,
              style: TextStyle(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.62)
                    : AppColors.textPrimary.withValues(alpha: 0.58),
                fontSize: 11.5,
              ),
            ),
          ),
        const SizedBox(height: 10),
        FacilityTariffView(tariff: tariff),
      ],
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
