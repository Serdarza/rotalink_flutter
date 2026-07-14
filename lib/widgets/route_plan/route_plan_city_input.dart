import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../il_search_sheet.dart';

/// Yazılabilir il alanı — yazarken öneri listesi + tam liste butonu.
class IlAutocompleteField extends StatefulWidget {
  const IlAutocompleteField({
    super.key,
    required this.controller,
    required this.cities,
    required this.label,
    required this.hint,
    required this.icon,
    required this.iconColor,
    this.onCommitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final List<String> cities;
  final String label;
  final String hint;
  final IconData icon;
  final Color iconColor;
  final ValueChanged<String>? onCommitted;
  final ValueChanged<String>? onChanged;

  @override
  State<IlAutocompleteField> createState() => _IlAutocompleteFieldState();
}

class _IlAutocompleteFieldState extends State<IlAutocompleteField> {
  final FocusNode _focus = FocusNode();
  bool _showSuggestions = false;
  List<String> _filtered = const [];

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _showSuggestions = false);
      });
    } else {
      _refreshFiltered();
      setState(() => _showSuggestions = true);
    }
  }

  void _onTextChanged() {
    _refreshFiltered();
    widget.onChanged?.call(widget.controller.text);
    if (_focus.hasFocus) {
      setState(() => _showSuggestions = true);
    }
  }

  void _refreshFiltered() {
    final q = widget.controller.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = widget.cities.take(8).toList();
      return;
    }
    _filtered = widget.cities
        .where((c) => c.toLowerCase().contains(q))
        .take(8)
        .toList();
  }

  void _commit(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    final prev = widget.controller.text.trim();
    widget.controller.text = v;
    _focus.unfocus();
    setState(() => _showSuggestions = false);
    if (v != prev) {
      widget.onCommitted?.call(v);
    }
  }

  Future<void> _openFullList() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final v = await showIlSearchSheet(
      context,
      cities: widget.cities,
      title: widget.label,
      currentSelection: widget.controller.text.trim().isEmpty
          ? null
          : widget.controller.text.trim(),
    );
    if (v != null && mounted) {
      _commit(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label.trim().isNotEmpty) ...[
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: widget.iconColor.withValues(alpha: 0.95),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: Icon(widget.icon, color: widget.iconColor, size: 22),
            suffixIcon: IconButton(
              tooltip: AppStrings.routePlanSelectIl,
              onPressed: _openFullList,
              icon: const Icon(Icons.list_alt_rounded, color: AppColors.primary),
            ),
            filled: true,
            fillColor: AppColors.suggestionFieldBg.withValues(alpha: 0.65),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          ),
          onTap: () {
            _refreshFiltered();
            setState(() => _showSuggestions = true);
          },
          onSubmitted: (raw) {
            final q = raw.trim().toLowerCase();
            if (q.isEmpty) return;
            final exact = widget.cities.where((c) => c.toLowerCase() == q);
            if (exact.isNotEmpty) {
              _commit(exact.first);
              return;
            }
            if (_filtered.isNotEmpty) {
              _commit(_filtered.first);
            }
          },
        ),
        if (_showSuggestions && _focus.hasFocus && _filtered.isNotEmpty)
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _filtered.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
                itemBuilder: (_, i) {
                  final city = _filtered[i];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(Icons.location_city_rounded, size: 20, color: widget.iconColor),
                    title: Text(city, style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () => _commit(city),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
