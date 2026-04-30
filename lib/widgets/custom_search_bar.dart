import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';
import '../utils/main_map_search.dart';

// ── Tasarım sabitleri ─────────────────────────────────────────────────────────

const _kRadius = 24.0;
const _kHeight = 56.0;
const _kMaxWidth = 600.0;
const _kBg = Color(0xFFF8F9FE); // Çok hafif soğuk beyaz
const _kHintColor = Color(0xFF9E9E9E);
const _kDividerColor = Color(0x1F000000);

// ── Widget ────────────────────────────────────────────────────────────────────

/// Premium ana harita arama çubuğu.
///
/// Özellikler:
/// - Squircle form + Soft Shadow + Glow (odakta)
/// - `AnimatedScale` ile hafif büyüme animasyonu
/// - `RawAutocomplete` — il önerileri
/// - Sesli arama (`speech_to_text`)
/// - Filtre ikonu + dikey ayraç
/// - Tablet uyumlu (`maxWidth: $_kMaxWidth`, ortalı)
class CustomSearchBar extends StatefulWidget {
  const CustomSearchBar({
    super.key,
    required this.controller,
    this.ilOptionsSorted,
    this.onSubmitted,
    this.onSearchCleared,
    this.onFilterPressed,
  });

  final TextEditingController controller;

  /// Sıralı il listesi — `MainMapSearch.distinctSortedIller` çıktısı.
  final List<String>? ilOptionsSorted;

  final VoidCallback? onSubmitted;

  /// Metin tamamen boşaldığında harita durumunu sıfırlamak için.
  final VoidCallback? onSearchCleared;

  /// Filtre ikonu tıklandığında (geçilmezse ikon soluk gösterilir).
  final VoidCallback? onFilterPressed;

  @override
  State<CustomSearchBar> createState() => _CustomSearchBarState();
}

class _CustomSearchBarState extends State<CustomSearchBar> {
  late final FocusNode _focusNode;
  bool _hadMeaningfulText = false;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechUsable = false;
  bool _listening = false;

  // ── Listeners ──────────────────────────────────────────────────────────────

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onControllerChanged() {
    final empty = widget.controller.text.trim().isEmpty;
    if (_hadMeaningfulText && empty) widget.onSearchCleared?.call();
    _hadMeaningfulText = !empty;
    _rebuild();
  }

  // ── Sesli Arama ────────────────────────────────────────────────────────────

  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (mounted) setState(() => _speechUsable = ok);
      if (!ok && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Sesli arama kullanılamıyor.')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _speechUsable = false);
    }
  }

  Future<void> _onMicPressed() async {
    if (!_speechUsable) {
      await _initSpeech();
      if (!mounted || !_speechUsable) return;
    }
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        widget.controller.text = r.recognizedWords;
        if (r.finalResult) {
          FocusManager.instance.primaryFocus?.unfocus();
          SchedulerBinding.instance.addPostFrameCallback((_) {
            widget.onSubmitted?.call();
          });
          unawaited(_speech.stop());
          if (mounted) setState(() => _listening = false);
        }
      },
      localeId: 'tr_TR',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.search,
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  void _submit() => widget.onSubmitted?.call();

  // ── TextField ──────────────────────────────────────────────────────────────

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required VoidCallback onSubmit,
  }) {
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) {
            FocusManager.instance.primaryFocus?.unfocus();
            SchedulerBinding.instance.addPostFrameCallback((_) => onSubmit());
          },
          style: const TextStyle(
            color: AppColors.searchBarText,
            fontSize: 15.5,
            fontWeight: FontWeight.w500,
          ),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          ),
        ),
        // ── Daktilo hint overlay ────────────────────────────────────────────
        ListenableBuilder(
          listenable: Listenable.merge([controller, focusNode]),
          builder: (_, _) {
            if (controller.text.isNotEmpty || focusNode.hasFocus) {
              return const SizedBox.shrink();
            }
            return const IgnorePointer(
              child: Padding(
                padding: EdgeInsets.only(left: 4),
                child: _TypewriterHint(),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _hadMeaningfulText = widget.controller.text.trim().isNotEmpty;
    _focusNode = FocusNode()..addListener(_rebuild);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focusNode
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    final showClear = widget.controller.text.isNotEmpty;
    final imeBottom = MediaQuery.viewInsetsOf(context).bottom;
    final iller = widget.ilOptionsSorted;
    final useAuto = iller != null && iller.isNotEmpty;

    // ── Metin alanı (autocomplete veya düz) ───────────────────────────────
    final Widget field = useAuto
        ? RawAutocomplete<String>(
            textEditingController: widget.controller,
            focusNode: _focusNode,
            displayStringForOption: (s) => s,
            optionsBuilder: (tv) =>
                MainMapSearch.filterIlAutocomplete(iller, tv.text),
            onSelected: (il) {
              widget.controller.text = il;
              FocusManager.instance.primaryFocus?.unfocus();
              SchedulerBinding.instance
                  .addPostFrameCallback((_) => _submit());
            },
            fieldViewBuilder: (_, ctrl, fn, onFsub) => _buildField(
              controller: ctrl,
              focusNode: fn,
              onSubmit: () {
                onFsub();
                _submit();
              },
            ),
            optionsViewBuilder: (_, onSel, options) {
              if (options.isEmpty) return const SizedBox.shrink();
              final maxW =
                  (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 568.0);
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 12,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  color: AppColors.white,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxHeight: 320, maxWidth: maxW),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (_, i) {
                        final opt = options.elementAt(i);
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.map_outlined,
                              color: AppColors.primary, size: 22),
                          title: Text(
                            opt,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () => onSel(opt),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          )
        : _buildField(
            controller: widget.controller,
            focusNode: _focusNode,
            onSubmit: _submit,
          );

    // ── Gölge: dingin vs. odaklı ─────────────────────────────────────────
    final List<BoxShadow> shadow = focused
        ? [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.14),
              blurRadius: 22,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ];

    return Padding(
      padding: EdgeInsets.only(bottom: imeBottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxWidth),
          child: AnimatedScale(
            scale: focused ? 1.015 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              height: _kHeight,
              decoration: BoxDecoration(
                color: _kBg,
                borderRadius: BorderRadius.circular(_kRadius),
                boxShadow: shadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_kRadius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      // ── Arama ikonu ───────────────────────────────────
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.search,
                          key: ValueKey<bool>(focused),
                          color: focused
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.65),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 6),

                      // ── Metin alanı ───────────────────────────────────
                      Expanded(child: field),

                      // ── Temizle ───────────────────────────────────────
                      if (showClear)
                        _BarBtn(
                          icon: Icons.close,
                          tooltip: AppStrings.clearSearch,
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            widget.controller.clear();
                          },
                        ),

                      // ── Mikrofon ──────────────────────────────────────
                      _BarBtn(
                        icon: _listening ? Icons.mic : Icons.mic_none,
                        color: _listening
                            ? Colors.redAccent
                            : AppColors.primary,
                        tooltip: 'Sesli ara',
                        onPressed: _onMicPressed,
                      ),

                      // ── Dikey ayraç ───────────────────────────────────
                      Container(
                        height: 22,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        color: _kDividerColor,
                      ),

                      // ── Filtre ────────────────────────────────────────
                      _BarBtn(
                        icon: Icons.tune,
                        tooltip: 'Filtrele',
                        color: widget.onFilterPressed != null
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.38),
                        onPressed: widget.onFilterPressed,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Yardımcı — küçük ikon butonu ─────────────────────────────────────────────

class _BarBtn extends StatelessWidget {
  const _BarBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = AppColors.primary,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: color, size: 20),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

// ── Daktilo Hint ──────────────────────────────────────────────────────────────

/// "İl veya misafirhane ara  ·  [daktilo]" — arama boşken gösterilir.
class _TypewriterHint extends StatefulWidget {
  const _TypewriterHint();

  @override
  State<_TypewriterHint> createState() => _TypewriterHintState();
}

class _TypewriterHintState extends State<_TypewriterHint> {
  static const _prefix = 'İl veya misafirhane ara  ·  ';

  static const _samples = [
    'Düzce',
    'Düzce Orduevi',
    'Ankara',
    'Ankara Kara Kuvvetleri',
    'İstanbul',
    'Trabzon',
    'Karşıyaka Deniz Lojmanı',
    'Antalya Hava',
  ];

  // Hız (ms)
  static const _typeMs = 36;
  static const _deleteMs = 20;
  static const _holdMs = 1800;

  int _idx = 0;
  int _len = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    while (mounted) {
      final full = _samples[_idx % _samples.length];
      for (var i = 0; i <= full.length; i++) {
        if (!mounted) return;
        setState(() => _len = i);
        await Future<void>.delayed(const Duration(milliseconds: _typeMs));
      }
      await Future<void>.delayed(const Duration(milliseconds: _holdMs));
      if (!mounted) return;
      for (var i = full.length; i >= 0; i--) {
        if (!mounted) return;
        setState(() => _len = i);
        await Future<void>.delayed(const Duration(milliseconds: _deleteMs));
      }
      if (!mounted) return;
      setState(() => _idx++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = _samples[_idx % _samples.length];
    final shown = full.substring(0, _len.clamp(0, full.length));
    return Text(
      '$_prefix$shown',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _kHintColor,
        fontSize: 13.0,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
      ),
    );
  }
}
