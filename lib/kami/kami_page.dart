import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/firebase_rota_repository.dart';
import '../models/route_plan_outcome.dart';
import '../theme/app_colors.dart';
import '../utils/maps_launch.dart';
import 'engine/kami_models.dart';
import 'engine/kami_service.dart';
import 'engine/location_service.dart';
import 'engine/response_builder.dart';
import 'kami_assistant.dart';
import 'kami_messages.dart';
import 'recommendation/distance_service.dart';
import 'recommendation/kami_recommendation_service.dart';
import 'recommendation/route_optimizer.dart';
import 'recommendation/trip_score_service.dart';

/// KAMİ sohbet — kullanıcı / asistan için iki yumuşak yüzey rengi.
abstract final class _KamiChatPalette {
  static const userSurface = Color(0xFFD9EDF2);
  static const assistantSurface = Color(0xFFF0F4F6);
  static const userBorder = Color(0xFFB5D5DE);
  static const assistantBorder = Color(0xFFD5DEE4);
  static const innerCardSurface = Color(0xFFFFFFFF);
}

/// Sohbet balonu / sonuç bloğu kabı.
class _KamiMessageBlock extends StatelessWidget {
  const _KamiMessageBlock({
    required this.isUser,
    required this.child,
    this.fullWidth = false,
  });

  final bool isUser;
  final Widget child;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final surface =
        isUser ? _KamiChatPalette.userSurface : _KamiChatPalette.assistantSurface;
    final border =
        isUser ? _KamiChatPalette.userBorder : _KamiChatPalette.assistantBorder;

    final block = Container(
      margin: const EdgeInsets.only(bottom: 14),
      width: fullWidth ? double.infinity : null,
      constraints: fullWidth
          ? null
          : BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
      padding: EdgeInsets.fromLTRB(
        fullWidth ? 16 : 14,
        fullWidth ? 16 : 12,
        fullWidth ? 16 : 14,
        fullWidth ? 14 : 12,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 6),
          bottomRight: Radius.circular(isUser ? 6 : 18),
        ),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );

    if (fullWidth) return block;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: block,
    );
  }
}

/// Harita / görsel inceleme — ikon + "İncele" etiketi (arama listesi ile uyumlu).
class _KamiInspectButton extends StatelessWidget {
  const _KamiInspectButton({
    required this.tapAction,
    required this.onTap,
  });

  final KamiResultCardTap tapAction;
  final VoidCallback onTap;

  static (IconData icon, Color color) _style(KamiResultCardTap action) {
    switch (action) {
      case KamiResultCardTap.maps:
        return (Icons.explore_rounded, AppColors.primary);
      case KamiResultCardTap.images:
        return (Icons.image_search_rounded, const Color(0xFF00796B));
      case KamiResultCardTap.none:
        return (Icons.open_in_new_rounded, AppColors.textPrimary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style(tapAction);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: SizedBox(
            width: 50,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: color.withValues(alpha: 0.18)),
                  ),
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(height: 5),
                Text(
                  'İncele',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _kamiHandleInspectTap(
  BuildContext context, {
  required KamiResultCardTap tapAction,
  required String city,
  required String title,
}) {
  final placeCity = city.trim();
  final placeTitle = title.trim();
  switch (tapAction) {
    case KamiResultCardTap.maps:
      unawaited(openMapSearch(context, placeCity, placeTitle));
    case KamiResultCardTap.images:
      final q =
          placeCity.isEmpty ? placeTitle : '$placeCity $placeTitle'.trim();
      unawaited(_kamiOpenGoogleImages(q));
    case KamiResultCardTap.none:
      break;
  }
}

Future<void> _kamiOpenGoogleImages(String query) async {
  final q = query.trim();
  if (q.isEmpty) return;
  final uri = Uri.parse(
    'https://www.google.com/search?tbm=isch&q=${Uri.encodeComponent(q)}',
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<void> _kamiDialPhone(BuildContext context, String raw) async {
  final p = raw.trim().replaceAll(RegExp(r'[^\d+]'), '');
  if (p.isEmpty || p == '0') {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Telefon numarası yok')),
    );
    return;
  }
  final uri = Uri(scheme: 'tel', path: p);
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Arama başlatılamadı')),
    );
  }
}

/// KAMİ asistan sayfası — Intent/Rule Engine sonucu gösterir (LLM yok).
class KamiPage extends StatefulWidget {
  const KamiPage({
    super.key,
    required this.repository,
    this.initialData,
    this.userLocationHint,
    this.service,
  });

  final FirebaseRotaRepository repository;
  final RotaDataState? initialData;
  final LatLng? userLocationHint;

  /// Test / ileride Gemini için override. Null ise yerel [KamiService].
  final KamiAssistantService? service;

  @override
  State<KamiPage> createState() => _KamiPageState();
}

class _KamiPageState extends State<KamiPage> {
  late final KamiChatController _controller;
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<RotaDataState>? _dataSub;
  RotaDataState? _latestData;
  List<String> _suggestionChips = KamiMessages.suggestionChips;

  @override
  void initState() {
    super.initState();
    _latestData = widget.initialData ?? widget.repository.currentState;
    final rotaStream = widget.repository.watchRoot();
    _dataSub = rotaStream.listen((data) {
      _latestData = data;
      unawaited(_refreshLocationChips());
    });

    final service = widget.service ??
        KamiService(
          contextProvider: () async {
            var data = _latestData ?? widget.repository.currentState;
            if (data == null) {
              data = await widget.repository.watchRoot().first;
            }
            final loc = await const KamiLocationService().resolveUserLocation(
              hint: widget.userLocationHint,
            );
            return KamiQueryContext(
              data: data,
              userLocation: loc ?? widget.userLocationHint,
              locationGranted: loc != null || widget.userLocationHint != null,
            );
          },
        );

    _controller = KamiChatController(service: service);
    _controller.addListener(_onControllerChanged);
    unawaited(_refreshLocationChips());
  }

  Future<void> _refreshLocationChips() async {
    final data = _latestData;
    final loc = await const KamiLocationService().resolveUserLocation(
      hint: widget.userLocationHint,
    );
    if (!mounted) return;
    if (data == null || loc == null) return;
    final city = KamiDistanceService.resolveHomeCity(
      loc,
      data,
    );
    if (city == null || city.trim().isEmpty) return;
    final next = KamiMessages.suggestionChipsForCity(city);
    if (listEquals(_suggestionChips, next)) return;
    setState(() => _suggestionChips = next);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _openWeekendRoute(KamiCityScore summary) async {
    final data = _latestData;
    if (data == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veriler henüz yüklenmedi.')),
      );
      return;
    }

    final user = await const KamiLocationService().resolveUserLocation(
      hint: widget.userLocationHint,
    );
    final loc = user ?? widget.userLocationHint;
    if (loc == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rota için konum gerekir.')),
      );
      return;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    try {
      final full = KamiTripScoreService.scoreCity(
        data: data,
        city: summary.city,
        distanceKm: summary.distanceKm,
      );
      final trip = await KamiRouteOptimizer.buildTrip(
        data: data,
        user: loc,
        destination: full,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // dialog
      Navigator.of(context).pop(
        RoutePlanOutcome(stops: trip.stops, segments: trip.segments),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rota oluşturulamadı: $e')),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_dataSub?.cancel() ?? Future<void>.value());
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (_controller.hasConversation) {
      _controller.clearConversation();
      return;
    }
    Navigator.of(context).maybePop();
  }

  static String _stripChipDecoration(String label) {
    return label.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final showWelcome = !_controller.hasConversation;

    return PopScope(
      canPop: showWelcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !showWelcome) {
          _controller.clearConversation();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF3F7F9),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: _handleBack,
          tooltip: showWelcome ? 'Kapat' : 'Yeni soru',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              KamiMessages.appBarTitle,
              style: TextStyle(
                color: AppColors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            Text(
              KamiMessages.appBarSubtitle,
              style: TextStyle(
                color: AppColors.white.withValues(alpha: 0.88),
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: showWelcome
                ? const _WelcomePanel()
                : _ResultTranscript(
                    messages: _controller.messages,
                    scrollController: _scrollController,
                    data: _latestData,
                    userLocationHint: widget.userLocationHint,
                    onOpenWeekendRoute: _openWeekendRoute,
                  ),
          ),
          if (showWelcome)
            _SuggestionChipRow(
              chips: _suggestionChips,
              onChipTap: (label) {
                final query = _stripChipDecoration(label);
                if (query.isEmpty) return;
                _controller.setInputText(query);
                unawaited(_controller.submitCurrentInput());
              },
            ),
          _KamiComposer(
            controller: _controller.inputController,
            focusNode: _inputFocus,
            sending: _controller.isSending,
            onSend: _controller.submitCurrentInput,
            bottomPad: bottomInset + (keyboard > 0 ? 8 : 10),
          ),
        ],
      ),
    ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 16),
      child: Column(
        children: [
          ClipOval(
            child: Image.asset(
              'assets/images/kami_logo.png',
              width: 88,
              height: 88,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            KamiMessages.welcomeHeadline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
              color: AppColors.textPrimary.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            KamiMessages.welcomeName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            KamiMessages.welcomeBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.55,
              fontWeight: FontWeight.w400,
              color: AppColors.textPrimary.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 28),
          const _CapabilityGrid(),
          const SizedBox(height: 24),
          Text(
            KamiMessages.welcomeTagline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: AppColors.primary.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityGrid extends StatelessWidget {
  const _CapabilityGrid();

  static const _items = <(IconData, String)>[
    (Icons.hotel_outlined, 'Kamu misafirhaneleri'),
    (Icons.apartment_outlined, 'Belediye tesisleri'),
    (Icons.museum_outlined, 'Gezilecek yerler'),
    (Icons.restaurant_outlined, 'Yöresel yemekler'),
    (Icons.weekend_outlined, 'Hafta sonu önerileri'),
    (Icons.alt_route_outlined, 'Akıllı rota'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in _items) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F8F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(item.$1, size: 20, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(
                  item.$2,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SuggestionChipRow extends StatelessWidget {
  const _SuggestionChipRow({
    required this.chips,
    required this.onChipTap,
  });

  final List<String> chips;
  final ValueChanged<String> onChipTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final chip in chips) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    onPressed: () => onChipTap(chip),
                    backgroundColor: AppColors.campaignBtnSecondary,
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.18),
                    ),
                    label: Text(
                      chip,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultTranscript extends StatelessWidget {
  const _ResultTranscript({
    required this.messages,
    required this.scrollController,
    required this.data,
    required this.userLocationHint,
    required this.onOpenWeekendRoute,
  });

  final List<KamiChatMessage> messages;
  final ScrollController scrollController;
  final RotaDataState? data;
  final LatLng? userLocationHint;
  final Future<void> Function(KamiCityScore summary) onOpenWeekendRoute;

  @override
  Widget build(BuildContext context) {
    final visible = messages.where((m) {
      if (m.role == KamiMessageRole.user) return m.text.trim().isNotEmpty;
      final ui = m.metadata?['ui'];
      if (ui == 'facility_cards' || ui == 'weekend_recs' || ui == 'route_recs') {
        return true;
      }
      return m.text.trim().isNotEmpty;
    }).toList();

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final msg = visible[index];
        final isUser = msg.role == KamiMessageRole.user;

        if (!isUser &&
            (msg.metadata?['ui'] == 'weekend_recs' ||
                msg.metadata?['ui'] == 'route_recs')) {
          return _WeekendRecsResult(
            message: msg,
            data: data,
            userLocationHint: userLocationHint,
            onOpenRoute: onOpenWeekendRoute,
            mapButtonLabel: msg.metadata?['ui'] == 'route_recs'
                ? 'Rotayı haritada göster'
                : 'Haritada göster',
          );
        }

        if (!isUser && msg.metadata?['ui'] == 'facility_cards') {
          return _FacilityCardsResult(message: msg);
        }

        return isUser
            ? _UserBubble(text: msg.text)
            : _AssistantTextResult(text: msg.text);
      },
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _KamiMessageBlock(
      isUser: true,
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14.5,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Düz metin cevaplar: ilk satır kalın başlık, gövde ferah satır aralığı.
class _AssistantTextResult extends StatelessWidget {
  const _AssistantTextResult({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text
        .split('\n')
        .map((e) => e.trimRight())
        .where((e) => e.trim().isNotEmpty || e.isEmpty)
        .toList();
    final title = lines.isNotEmpty ? lines.first.trim() : '';
    final bodyLines = lines.length > 1 ? lines.sublist(1) : const <String>[];
    final body = bodyLines.join('\n').trim();

    return _KamiMessageBlock(
      isUser: false,
      fullWidth: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              body,
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.84),
                fontSize: 14.5,
                height: 1.55,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          const SizedBox(height: 14),
          const _RotalinkSourceChip(),
        ],
      ),
    );
  }
}

class _RotalinkSourceChip extends StatelessWidget {
  const _RotalinkSourceChip();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _KamiChatPalette.innerCardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _KamiChatPalette.assistantBorder),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_outlined, size: 14, color: AppColors.primary),
              SizedBox(width: 5),
              Text(
                KamiMessages.sourceLabel,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Akıllı hafta sonu önerileri — filtre + kart + haritada göster.
class _WeekendRecsResult extends StatefulWidget {
  const _WeekendRecsResult({
    required this.message,
    required this.data,
    required this.userLocationHint,
    required this.onOpenRoute,
    this.mapButtonLabel = 'Haritada göster',
  });

  final KamiChatMessage message;
  final RotaDataState? data;
  final LatLng? userLocationHint;
  final Future<void> Function(KamiCityScore summary) onOpenRoute;
  final String mapButtonLabel;

  @override
  State<_WeekendRecsResult> createState() => _WeekendRecsResultState();
}

class _WeekendRecsResultState extends State<_WeekendRecsResult> {
  static const _recService = KamiRecommendationService();

  late List<KamiCityScore> _scores;
  final Set<KamiTripFilter> _filters = {};
  bool _filtering = false;

  @override
  void initState() {
    super.initState();
    _scores = _parseScores(widget.message);
  }

  List<KamiCityScore> _parseScores(KamiChatMessage message) {
    final raw = message.metadata?['recommendations'];
    final out = <KamiCityScore>[];
    if (raw is List) {
      for (final item in raw) {
        final s = KamiCityScore.fromMap(item);
        if (s != null) out.add(s);
      }
    }
    return out;
  }

  Future<void> _toggleFilter(KamiTripFilter f) async {
    setState(() {
      if (_filters.contains(f)) {
        _filters.remove(f);
      } else {
        _filters.add(f);
      }
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final data = widget.data;
    if (data == null) return;

    LatLng? user = widget.userLocationHint;
    final meta = widget.message.metadata;
    if (user == null && meta != null) {
      final lat = meta['userLat'];
      final lon = meta['userLon'];
      if (lat is num && lon is num) {
        user = LatLng(lat.toDouble(), lon.toDouble());
      }
    }
    if (user == null) return;

    setState(() => _filtering = true);
    final isRoute = widget.message.metadata?['ui'] == 'route_recs';
    final List<KamiCityScore> next;
    if (isRoute) {
      var homeCity = widget.message.metadata?['homeCity'] as String?;
      homeCity ??= KamiDistanceService.resolveHomeCity(user, data);
      if (homeCity == null || homeCity.trim().isEmpty) {
        if (mounted) setState(() => _filtering = false);
        return;
      }
      next = _recService.nearbyRouteSuggestions(
        data: data,
        user: user,
        homeCity: homeCity,
      );
    } else {
      next = _recService.weekendSuggestions(
        data: data,
        user: user,
        filters: Set<KamiTripFilter>.from(_filters),
      );
    }
    if (!mounted) return;
    setState(() {
      _scores = next;
      _filtering = false;
    });
  }

  Future<void> _showDetail(KamiCityScore summary) async {
    final data = widget.data;
    KamiCityScore detail = summary;
    if (data != null) {
      detail = KamiTripScoreService.scoreCity(
        data: data,
        city: summary.city,
        distanceKm: summary.distanceKm,
      );
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return _WeekendCityContentSheet(
          detail: detail,
          mapButtonLabel: widget.mapButtonLabel,
          onShowMap: () {
            Navigator.of(ctx).pop();
            unawaited(widget.onOpenRoute(detail));
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.message.metadata ?? const {};
    final title = (meta['title'] ?? widget.message.text).toString();
    final subtitle = (meta['subtitle'] ?? '').toString();

    return _KamiMessageBlock(
      isUser: false,
      fullWidth: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.58),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (widget.message.metadata?['ui'] != 'route_recs')
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final f in KamiTripFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: _filters.contains(f),
                        label: Text(
                          f.label,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        onSelected: (_) => unawaited(_toggleFilter(f)),
                        selectedColor: AppColors.primary.withValues(alpha: 0.18),
                        checkmarkColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (widget.message.metadata?['ui'] != 'route_recs')
            const SizedBox(height: 12),
          if (_filtering)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_scores.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Bu filtrelere uyan destinasyon yok. Filtreleri gevşetin.',
                style: TextStyle(
                  color: AppColors.textPrimary.withValues(alpha: 0.65),
                ),
              ),
            )
          else
            for (var i = 0; i < _scores.length; i++) ...[
              _WeekendCityCard(
                index: i + 1,
                score: _scores[i],
                mapButtonLabel: widget.mapButtonLabel,
                onTap: () => unawaited(_showDetail(_scores[i])),
                onShowMap: () => unawaited(widget.onOpenRoute(_scores[i])),
              ),
              const SizedBox(height: 12),
            ],
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 2),
            child: _RotalinkSourceChip(),
          ),
        ],
      ),
    );
  }
}

/// İl önerisine tıklanınca Rotalink içeriği: gezi / yemek / sosyal / tesis.
class _WeekendCityContentSheet extends StatelessWidget {
  const _WeekendCityContentSheet({
    required this.detail,
    required this.onShowMap,
    this.mapButtonLabel = 'Haritada göster',
  });

  final KamiCityScore detail;
  final VoidCallback onShowMap;
  final String mapButtonLabel;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.88;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  detail.city,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Puan ${detail.score} · '
                  '${KamiDistanceService.formatKm(detail.distanceKm)} · '
                  '${detail.driveLabel}',
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.58),
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatChip(label: 'Gezi ${detail.geziCount}'),
                    _StatChip(label: 'Yemek ${detail.yemekCount}'),
                    _StatChip(label: 'Sosyal ${detail.sosyalCount}'),
                    _StatChip(label: 'Tesis ${detail.facilityCount}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  TabBar(
                    isScrollable: true,
                    labelColor: AppColors.primary,
                    unselectedLabelColor:
                        AppColors.textPrimary.withValues(alpha: 0.45),
                    indicatorColor: AppColors.primary,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                    tabs: [
                      Tab(text: 'Gezi (${detail.gezi.length})'),
                      Tab(text: 'Yemek (${detail.yemek.length})'),
                      Tab(text: 'Sosyal (${detail.sosyal.length})'),
                      Tab(text: 'Tesis (${detail.facilities.length})'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _CityPlaceList(
                          emptyLabel: 'Bu ilde gezilecek yer kaydı yok.',
                          children: [
                            for (final g in detail.gezi)
                              _CityPlaceTile(
                                title: g.isim.trim().isEmpty
                                    ? 'İsimsiz yer'
                                    : g.isim.trim(),
                                city: g.il.trim(),
                                description: g.aciklama.trim(),
                                address: g.adres.trim(),
                                badge: (g.tur ?? '').trim(),
                                tapAction: KamiResultCardTap.maps,
                              ),
                          ],
                        ),
                        _CityPlaceList(
                          emptyLabel: 'Bu ilde yöresel yemek kaydı yok.',
                          children: [
                            for (final y in detail.yemek)
                              _CityPlaceTile(
                                title: y.isim.trim().isEmpty
                                    ? 'İsimsiz yemek'
                                    : y.isim.trim(),
                                city: y.il.trim(),
                                description: y.aciklama.trim(),
                                address: y.adres.trim(),
                                badge: 'Yemek',
                                tapAction: KamiResultCardTap.images,
                              ),
                          ],
                        ),
                        _CityPlaceList(
                          emptyLabel: 'Bu ilde belediye sosyal tesis kaydı yok.',
                          children: [
                            for (final s in detail.sosyal)
                              _CityPlaceTile(
                                title: s.isim.trim().isEmpty
                                    ? 'İsimsiz tesis'
                                    : s.isim.trim(),
                                city: s.il.trim(),
                                description: s.aciklama.trim(),
                                address: s.adres.trim(),
                                badge: 'Sosyal',
                                tapAction: KamiResultCardTap.maps,
                              ),
                          ],
                        ),
                        _CityPlaceList(
                          emptyLabel: 'Bu ilde kamu misafirhanesi kaydı yok.',
                          children: [
                            for (final m in detail.facilities)
                              _CityPlaceTile(
                                title: m.isim.trim().isEmpty
                                    ? 'İsimsiz tesis'
                                    : m.isim.trim(),
                                city: detail.city,
                                description: m.tip.trim(),
                                address: m.adres.trim(),
                                phone: m.telefon.trim(),
                                badge: m.tip.trim().isEmpty
                                    ? 'Tesis'
                                    : m.tip.trim(),
                                tapAction: KamiResultCardTap.maps,
                                dialPhoneOnTap: true,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 10 + bottom),
            child: FilledButton.icon(
              onPressed: onShowMap,
              icon: const Icon(Icons.map_outlined),
              label: Text(mapButtonLabel),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CityPlaceList extends StatelessWidget {
  const _CityPlaceList({
    required this.children,
    required this.emptyLabel,
  });

  final List<Widget> children;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.55),
              fontSize: 14.5,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: children.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) => children[i],
    );
  }
}

class _CityPlaceTile extends StatelessWidget {
  const _CityPlaceTile({
    required this.title,
    this.city = '',
    this.description = '',
    this.address = '',
    this.phone = '',
    this.badge = '',
    this.tapAction = KamiResultCardTap.none,
    this.dialPhoneOnTap = false,
  });

  final String title;
  final String city;
  final String description;
  final String address;
  final String phone;
  final String badge;
  final KamiResultCardTap tapAction;
  final bool dialPhoneOnTap;

  @override
  Widget build(BuildContext context) {
    final desc = description.trim();
    final addr = address.trim();
    final tel = phone.trim();
    final showTel = tel.isNotEmpty &&
        tel != '0' &&
        tel.toLowerCase() != 'null';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _KamiChatPalette.innerCardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _KamiChatPalette.assistantBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
              if (badge.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
              if (tapAction != KamiResultCardTap.none) ...[
                const SizedBox(width: 4),
                _KamiInspectButton(
                  tapAction: tapAction,
                  onTap: () => _kamiHandleInspectTap(
                    context,
                    tapAction: tapAction,
                    city: city,
                    title: title,
                  ),
                ),
              ],
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              desc,
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.78),
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ],
          if (addr.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 16,
                  color: AppColors.primary.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    addr,
                    style: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: 0.62),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (showTel) ...[
            const SizedBox(height: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dialPhoneOnTap
                  ? () => unawaited(_kamiDialPhone(context, tel))
                  : null,
              child: Row(
                children: [
                  Icon(
                    Icons.phone_outlined,
                    size: 16,
                    color: AppColors.primary.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tel,
                    style: TextStyle(
                      color: dialPhoneOnTap
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: dialPhoneOnTap
                          ? TextDecoration.underline
                          : TextDecoration.none,
                      decorationColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F8F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _WeekendCityCard extends StatelessWidget {
  const _WeekendCityCard({
    required this.index,
    required this.score,
    required this.onTap,
    required this.onShowMap,
    this.mapButtonLabel = 'Haritada',
  });

  final int index;
  final KamiCityScore score;
  final VoidCallback onTap;
  final VoidCallback onShowMap;
  final String mapButtonLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _KamiChatPalette.innerCardSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _KamiChatPalette.assistantBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5F7),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '$index',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            score.city,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Puan ${score.score}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: onShowMap,
                      child: Text(
                        mapButtonLabel.contains('Rotayı')
                            ? 'Rotayı göster'
                            : mapButtonLabel,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${KamiDistanceService.formatKm(score.distanceKm)} · '
                  'Yaklaşık ${score.driveLabel}',
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Gezi ${score.geziCount} · Yemek ${score.yemekCount} · '
                  'Sosyal ${score.sosyalCount} · Tesis ${score.facilityCount}',
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.55),
                    fontSize: 12.5,
                  ),
                ),
                if (score.highlights.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    score.highlights.take(3).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary.withValues(alpha: 0.72),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'İçeriği görmek için dokunun',
                  style: TextStyle(
                    color: AppColors.primary.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Profesyonel sonuç listesi — tesis / gezi / yemek / sosyal (DB açıklamaları dahil).
class _FacilityCardsResult extends StatelessWidget {
  const _FacilityCardsResult({required this.message});

  final KamiChatMessage message;

  @override
  Widget build(BuildContext context) {
    final meta = message.metadata ?? const {};
    final title = (meta['title'] ?? message.text).toString();
    final subtitle = (meta['subtitle'] ?? '').toString();
    final rawCards = meta['cards'];
    final cards = <KamiResultCard>[];
    if (rawCards is List) {
      for (final item in rawCards) {
        final c = KamiResultCard.fromMap(item);
        if (c != null) cards.add(c);
      }
    }

    final sections = <String, List<KamiResultCard>>{};
    for (final card in cards) {
      final key = card.section.trim().isEmpty ? 'Öneriler' : card.section.trim();
      sections.putIfAbsent(key, () => <KamiResultCard>[]).add(card);
    }

    return _KamiMessageBlock(
      isUser: false,
      fullWidth: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.58),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          for (final entry in sections.entries) ...[
            if (sections.length > 1 || entry.key != 'Öneriler') ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 4),
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
            for (var i = 0; i < entry.value.length; i++) ...[
              _FacilityInfoCard(
                card: entry.value[i],
                displayIndex: i + 1,
              ),
              const SizedBox(height: 14),
            ],
          ],
          const Padding(
            padding: EdgeInsets.only(top: 2, bottom: 2),
            child: _RotalinkSourceChip(),
          ),
        ],
      ),
    );
  }
}

class _FacilityInfoCard extends StatelessWidget {
  const _FacilityInfoCard({
    required this.card,
    required this.displayIndex,
  });

  final KamiResultCard card;
  final int displayIndex;

  @override
  Widget build(BuildContext context) {
    final phone = card.phone.trim();
    final dist = card.distanceLabel.trim();
    final address = card.address.trim();
    final description = card.description.trim();
    final city = card.city.trim();
    final tapAction = card.tapAction;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5F7),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '$displayIndex',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                  if (city.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      city,
                      style: TextStyle(
                        color: AppColors.textPrimary.withValues(alpha: 0.55),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (tapAction != KamiResultCardTap.none)
              _KamiInspectButton(
                tapAction: tapAction,
                onTap: () => _kamiHandleInspectTap(
                  context,
                  tapAction: tapAction,
                  city: city,
                  title: card.title,
                ),
              ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.82),
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Divider(
          height: 1,
          color: AppColors.primary.withValues(alpha: 0.08),
        ),
        const SizedBox(height: 12),
        if (phone.isNotEmpty) ...[
          _InfoRow(
            icon: Icons.phone_outlined,
            label: 'İletişim',
            value: phone,
            linkStyle: true,
            onTap: () => unawaited(_kamiDialPhone(context, phone)),
          ),
          const SizedBox(height: 10),
        ],
        if (address.isNotEmpty) ...[
          _InfoRow(
            icon: Icons.place_outlined,
            label: 'Adres',
            value: address,
          ),
          const SizedBox(height: 10),
        ],
        if (dist.isNotEmpty)
          _InfoRow(
            icon: Icons.near_me_outlined,
            label: 'Mesafe',
            value: dist,
            emphasize: true,
          )
        else if (phone.isEmpty && address.isEmpty && description.isEmpty)
          const _InfoRow(
            icon: Icons.info_outline,
            label: 'Not',
            value: 'Ek bilgi yok',
            muted: true,
          ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: _KamiChatPalette.innerCardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _KamiChatPalette.assistantBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: content,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
    this.emphasize = false,
    this.linkStyle = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool muted;
  final bool emphasize;
  final bool linkStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary.withValues(alpha: 0.85)),
        const SizedBox(width: 8),
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.55),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: muted
                  ? AppColors.textPrimary.withValues(alpha: 0.45)
                  : linkStyle
                      ? AppColors.primary
                      : AppColors.textPrimary,
              fontSize: emphasize ? 14.5 : 14,
              fontWeight: emphasize || linkStyle
                  ? FontWeight.w700
                  : FontWeight.w500,
              height: 1.35,
              decoration:
                  linkStyle ? TextDecoration.underline : TextDecoration.none,
              decorationColor: AppColors.primary,
            ),
          ),
        ),
      ],
    );

    if (onTap == null) return row;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }
}

class _KamiComposer extends StatelessWidget {
  const _KamiComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.bottomPad,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      color: AppColors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPad),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F7F8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.12),
                  ),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                  decoration: const InputDecoration(
                    hintText: KamiMessages.inputHint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, color: AppColors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
