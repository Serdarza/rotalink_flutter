import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

/// Material 3 alt sayfa — il listesi + arama; seçili il üstte chip ile gösterilir (çakışma yok).
Future<String?> showIlSearchSheet(
  BuildContext context, {
  required List<String> cities,
  String? title,
  String? currentSelection,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (outerCtx) {
      return _IlSearchSheetBody(
        cities: cities,
        title: title ?? AppStrings.routePlanSelectIl,
        currentSelection: currentSelection,
      );
    },
  );
}

class _IlSearchSheetBody extends StatefulWidget {
  const _IlSearchSheetBody({
    required this.cities,
    required this.title,
    this.currentSelection,
  });

  final List<String> cities;
  final String title;
  final String? currentSelection;

  @override
  State<_IlSearchSheetBody> createState() => _IlSearchSheetBodyState();
}

class _IlSearchSheetBodyState extends State<_IlSearchSheetBody> {
  late final TextEditingController _q;
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _q = TextEditingController();
    _filtered = List<String>.from(widget.cities);
    _q.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _q.removeListener(_applyFilter);
    _q.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final n = _q.text.trim().toLowerCase();
    setState(() {
      if (n.isEmpty) {
        _filtered = List<String>.from(widget.cities);
      } else {
        _filtered = widget.cities.where((c) => c.toLowerCase().contains(n)).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomSafe = mq.padding.bottom;
    final keyboard = mq.viewInsets.bottom;
    final sheetHeight = mq.size.height * 0.88;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: sheetHeight,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.58,
          minChildSize: 0.38,
          maxChildSize: 0.92,
          builder: (ctx, scrollController) {
            final surface = scheme.surface;
            final surfaceHigh = scheme.surfaceContainerHighest;

            return Material(
              color: surface,
              elevation: 8,
              shadowColor: Colors.black38,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
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
                  if (widget.currentSelection != null &&
                      widget.currentSelection!.trim().isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          avatar: Icon(
                            Icons.place_outlined,
                            size: 18,
                            color: scheme.primary,
                          ),
                          label: Text(
                            '${AppStrings.routePlanSelectedIlChip}: ${widget.currentSelection!.trim()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          backgroundColor: AppColors.selectedBackground.withValues(alpha: 0.4),
                          side: BorderSide(
                            color: scheme.primary.withValues(alpha: 0.35),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: Text(
                      AppStrings.routePlanSearchIlLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary.withValues(alpha: 0.85),
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _q,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: AppStrings.routePlanSearchIlHint,
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                        suffixIcon: _q.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Temizle',
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _q.clear();
                                  FocusManager.instance.primaryFocus?.unfocus();
                                },
                              ),
                        filled: true,
                        fillColor: surfaceHigh.withValues(alpha: 0.45),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: scrollController,
                      thumbVisibility: _filtered.length > 8,
                      child: ListView.builder(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 20 + bottomSafe),
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final il = _filtered[i];
                          final sel = widget.currentSelection != null &&
                              il.toLowerCase() == widget.currentSelection!.toLowerCase();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Material(
                              color: sel
                                  ? AppColors.selectedBackground.withValues(alpha: 0.4)
                                  : surfaceHigh.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                title: Text(
                                  il,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                trailing: sel
                                    ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                                    : null,
                                onTap: () => Navigator.pop(context, il),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

