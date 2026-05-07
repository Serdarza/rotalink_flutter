import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Arama çubuğunda boşken gösterilen "Örnek: …" daktilo animasyonu.
class SearchTypewriterExamples extends StatefulWidget {
  const SearchTypewriterExamples({super.key});

  static const samples = ['Düzce', 'Düzce Orduevi'];

  @override
  State<SearchTypewriterExamples> createState() => _SearchTypewriterExamplesState();
}

class _SearchTypewriterExamplesState extends State<SearchTypewriterExamples> {
  static const _prefix = 'Örnek: ';
  static const _typeMs = 55;
  static const _deleteMs = 38;
  static const _holdMs = 2000;

  var _sampleIndex = 0;
  var _visibleLen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    while (mounted) {
      final full =
          SearchTypewriterExamples.samples[_sampleIndex % SearchTypewriterExamples.samples.length];
      for (var i = 0; i <= full.length; i++) {
        if (!mounted) return;
        setState(() => _visibleLen = i);
        await Future<void>.delayed(const Duration(milliseconds: _typeMs));
      }
      await Future<void>.delayed(const Duration(milliseconds: _holdMs));
      if (!mounted) return;
      for (var i = full.length; i >= 0; i--) {
        if (!mounted) return;
        setState(() => _visibleLen = i);
        await Future<void>.delayed(const Duration(milliseconds: _deleteMs));
      }
      if (!mounted) return;
      setState(() => _sampleIndex++);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final full =
        SearchTypewriterExamples.samples[_sampleIndex % SearchTypewriterExamples.samples.length];
    final n = _visibleLen.clamp(0, full.length);
    final shown = full.substring(0, n);
    return Text(
      '$_prefix$shown',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.searchBarHint,
        fontSize: 13,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
