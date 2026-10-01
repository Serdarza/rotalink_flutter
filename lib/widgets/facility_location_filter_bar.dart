import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/misafirhane.dart';
import '../providers/facility_filter_provider.dart';
import '../theme/app_colors.dart';
import '../utils/il_ilce.dart';

/// Konaklama sonuçlarının üstündeki il → ilçe filtresi ve sonuç sayısı.
///
/// İl seçilmeden ilçe seçimi kapalıdır; ilçe listesi yalnız seçili ilin resmi
/// ilçelerini gösterir.
class FacilityLocationFilterBar extends ConsumerWidget {
  const FacilityLocationFilterBar({
    super.key,
    required this.allFacilities,
    this.onSelectIl,
  });

  /// İl seçici sayıları için tüm tesisler.
  final List<Misafirhane> allFacilities;

  /// İl seçilince yeni arama başlatır; null ise il düğmesi gizlenir.
  final ValueChanged<String>? onSelectIl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(searchPanelLocationSummaryProvider);
    final selection = ref.watch(facilityIlceFilterProvider);
    final count = ref.watch(filteredTesisListProvider).length;
    final il = summary.il;
    final ilce = il != null && selection != null && IlIlce.sameIl(selection.il, il)
        ? selection.ilce
        : null;

    final title = il == null ? 'Birden çok il' : IlIlce.label(il, ilce ?? '');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8EEF0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.place_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  '$count tesis',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (onSelectIl != null) ...[
                Expanded(
                  child: _FilterPill(
                    label: 'İl',
                    value: il ?? 'İl seç',
                    onTap: () => _pickIl(context, il),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _FilterPill(
                  label: 'İlçe',
                  value: il == null ? 'Önce il seçin' : (ilce ?? 'Tüm ilçeler'),
                  active: ilce != null,
                  onTap: il == null ? null : () => _pickIlce(context, ref, il, summary, ilce),
                  onClear: ilce == null
                      ? null
                      : () => ref.read(facilityIlceFilterProvider.notifier).state = null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickIl(BuildContext context, String? current) async {
    final counts = <String, int>{};
    for (final m in allFacilities) {
      final il = IlIlce.canonicalIl(m.il) ?? m.il.trim();
      if (il.isEmpty) continue;
      counts[il] = (counts[il] ?? 0) + 1;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _LocationPickerSheet(
        title: 'İl seç',
        searchHint: 'İl ara',
        allLabel: null,
        allCount: 0,
        counts: counts,
        selected: current,
      ),
    );
    if (picked != null && picked.isNotEmpty && picked != current) {
      onSelectIl?.call(picked);
    }
  }

  Future<void> _pickIlce(
    BuildContext context,
    WidgetRef ref,
    String il,
    FacilityLocationSummary summary,
    String? current,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _LocationPickerSheet(
        title: '$il ilçeleri',
        searchHint: 'İlçe ara',
        allLabel: 'Tüm ilçeler',
        allCount: summary.total,
        counts: summary.ilceCounts,
        selected: current ?? '',
      ),
    );
    if (picked == null) return;
    ref.read(facilityIlceFilterProvider.notifier).state =
        picked.isEmpty ? null : IlceSelection(il: il, ilce: picked);
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.value,
    this.onTap,
    this.onClear,
    this.active = false,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = !enabled
        ? const Color(0xFF9AABB0)
        : (active ? AppColors.primary : AppColors.textPrimary);
    return Material(
      color: active ? AppColors.primary.withValues(alpha: 0.08) : const Color(0xFFF4F7F8),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? AppColors.primary.withValues(alpha: 0.5) : const Color(0xFFE1E8EA),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.campaignSummaryMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: 'İlçe filtresini kaldır',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.primary,
                  onPressed: onClear,
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.expand_more_rounded, size: 20, color: fg),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aramalı il / ilçe seçim listesi. Boş string → "Tüm …" seçeneği.
class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({
    required this.title,
    required this.searchHint,
    required this.allLabel,
    required this.allCount,
    required this.counts,
    required this.selected,
  });

  final String title;
  final String searchHint;
  final String? allLabel;
  final int allCount;
  final Map<String, int> counts;
  final String? selected;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final _query = TextEditingController();
  late final List<String> _names = widget.counts.keys.toList()
    ..sort((a, b) => IlIlce.key(a).compareTo(IlIlce.key(b)));

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = IlIlce.key(_query.text);
    final names = q.isEmpty
        ? _names
        : _names.where((n) => IlIlce.key(n).contains(q)).toList();
    final showAll = widget.allLabel != null && q.isEmpty;
    final height = MediaQuery.sizeOf(context).height * 0.75;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              widget.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF4F7F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: names.isEmpty && !showAll
                ? const Center(
                    child: Text(
                      'Eşleşen sonuç yok',
                      style: TextStyle(color: AppColors.campaignSummaryMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: names.length + (showAll ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (showAll && i == 0) {
                        return _row(
                          context,
                          name: widget.allLabel!,
                          value: '',
                          count: widget.allCount,
                          emphasized: true,
                        );
                      }
                      final n = names[i - (showAll ? 1 : 0)];
                      return _row(
                        context,
                        name: n,
                        value: n,
                        count: widget.counts[n] ?? 0,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String name,
    required String value,
    required int count,
    bool emphasized = false,
  }) {
    final selected = widget.selected == value;
    final empty = count == 0 && !emphasized;
    return ListTile(
      selected: selected,
      selectedColor: AppColors.primary,
      title: Text(
        name,
        style: TextStyle(
          fontWeight: emphasized || selected ? FontWeight.w700 : FontWeight.w500,
          color: empty && !selected ? const Color(0xFF8A9A9F) : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            empty ? 'Tesis yok' : '$count tesis',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: empty ? const Color(0xFFA5B3B7) : AppColors.campaignSummaryMuted,
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_rounded, color: AppColors.primary, size: 20),
          ],
        ],
      ),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}
