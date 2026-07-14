import 'package:flutter/material.dart';

import 'custom_search_bar.dart';
import 'facility_type_filter_chips.dart';

/// Arama çubuğu + tip filtre chip satırı — toolbar altında sabit konumda kalır.
class MainMapSearchChrome extends StatelessWidget {
  const MainMapSearchChrome({
    super.key,
    this.anchorKey,
    required this.top,
    required this.searchBarSession,
    required this.controller,
    this.focusNode,
    required this.ilOptionsSorted,
    this.onSubmitted,
    this.onSearchCleared,
    this.onFocusChanged,
  });

  static const double searchBarHeight = 56;
  static const double filterChipsHeight = 40;
  static const double gap = 4;
  /// Toolbar altı boşluk — arama çubuğu konumu.
  static const double topGapBelowToolbar = 28;
  static const double blockHeight =
      searchBarHeight + gap + filterChipsHeight;

  final Key? anchorKey;
  final double top;
  final int searchBarSession;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final List<String>? ilOptionsSorted;
  final VoidCallback? onSubmitted;
  final VoidCallback? onSearchCleared;
  final ValueChanged<bool>? onFocusChanged;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      key: anchorKey,
      left: 0,
      right: 0,
      top: top,
      height: blockHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CustomSearchBar(
              key: ValueKey<int>(searchBarSession),
              controller: controller,
              focusNode: focusNode,
              ilOptionsSorted: ilOptionsSorted,
              onSubmitted: onSubmitted,
              onSearchCleared: onSearchCleared,
              onFocusChanged: onFocusChanged,
              ignoreKeyboardInset: true,
            ),
          ),
          const SizedBox(height: gap),
          const SizedBox(
            height: filterChipsHeight,
            child: FacilityTypeFilterChips(),
          ),
        ],
      ),
    );
  }
}
