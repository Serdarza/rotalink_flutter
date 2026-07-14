import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ads/ad_service.dart';
import '../data/firebase_rota_repository.dart';
import '../data/saved_routes_repository.dart';
import '../l10n/app_strings.dart';
import '../models/route_plan_outcome.dart';
import '../route/route_planning_notifier.dart';
import '../screens/route_plan_advice_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/route_plan/route_plan_city_input.dart';
import '../widgets/rotalink_banner_ad.dart';

/// 1. adım: iller + günler. 2. adım tavsiye ekranına gider.
class RoutePlanScreen extends StatelessWidget {
  RoutePlanScreen({
    super.key,
    required this.repository,
    SavedRoutesRepository? savedRoutesRepository,
    this.embeddedInShell = false,
  }) : savedRoutesRepository = savedRoutesRepository ?? SavedRoutesRepository();

  final FirebaseRotaRepository repository;
  final SavedRoutesRepository savedRoutesRepository;

  /// [RotalinkMainShell] alt menüsü görünürken açıldıysa true.
  final bool embeddedInShell;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          RoutePlanningNotifier(savedRoutesRepository: savedRoutesRepository),
      child: _RoutePlanCitiesPage(
        repository: repository,
        embeddedInShell: embeddedInShell,
      ),
    );
  }
}

class _RoutePlanCitiesPage extends StatefulWidget {
  const _RoutePlanCitiesPage({
    required this.repository,
    required this.embeddedInShell,
  });

  final FirebaseRotaRepository repository;
  final bool embeddedInShell;

  @override
  State<_RoutePlanCitiesPage> createState() => _RoutePlanCitiesPageState();
}

class _RoutePlanCitiesPageState extends State<_RoutePlanCitiesPage> {
  static const _cardRadius = 16.0;
  late final Stream<RotaDataState> _rotaStream;
  RotaDataState? _initialRota;

  @override
  void initState() {
    super.initState();
    _initialRota = widget.repository.currentState;
    _rotaStream = widget.repository.watchRoot();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openAdvice(RotaDataState data) async {
    final n = context.read<RoutePlanningNotifier>();
    final raw = n.collectStops(data, _snack);
    if (raw == null) return;

    for (var i = 0; i < n.intermediate.length; i++) {
      final city = n.intermediate[i].city.text.trim();
      if (city.isNotEmpty) {
        n.trimStopSelectionsForCity(i, city, data);
      }
    }

    final outcome = await Navigator.of(context).push<RoutePlanOutcome>(
      MaterialPageRoute(
        builder: (_) => RoutePlanAdviceScreen(
          data: data,
          stops: raw,
        ),
      ),
    );
    if (!mounted || outcome == null) return;
    Navigator.of(context).pop<RoutePlanOutcome>(outcome);
  }

  Future<void> _loadSaved(SavedRouteRecord record, RotaDataState data) async {
    final raw = record.stops.map((e) => e.toRouteStop()).toList();
    if (raw.length < 2) {
      _snack(AppStrings.routePlanNeedTarget);
      return;
    }

    final outcome = await Navigator.of(context).push<RoutePlanOutcome>(
      MaterialPageRoute(
        builder: (_) => RoutePlanAdviceScreen(
          data: data,
          stops: raw,
          restoreSaved: true,
        ),
      ),
    );
    if (!mounted || outcome == null) return;
    Navigator.of(context).pop<RoutePlanOutcome>(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final listBottomPad = widget.embeddedInShell
        ? 16.0
        : 24.0 + MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF4F7F8),
      appBar: AppBar(
        leading: widget.embeddedInShell
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
        automaticallyImplyLeading: !widget.embeddedInShell,
        title: const Text(AppStrings.routePlanTitle),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          StreamBuilder<RotaDataState>(
            stream: _rotaStream,
            initialData: _initialRota,
            builder: (context, snap) {
              final data = snap.data;
              return Consumer<RoutePlanningNotifier>(
                builder: (context, n, _) {
                  return IconButton(
                    icon: const Icon(Icons.bookmark_add_outlined),
                    tooltip: AppStrings.routePlanSaveTitle,
                    onPressed: data == null || n.calculating
                        ? null
                        : () async {
                            final raw = n.collectStops(data, _snack);
                            if (raw == null) return;
                            await n.promptSaveRoute(context, raw, _snack);
                          },
                  );
                },
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<RotaDataState>(
          stream: _rotaStream,
          initialData: _initialRota,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            final data = snapshot.data;
            if (data == null) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            if (data.errorMessage != null) {
              return Center(child: Text(data.errorMessage!));
            }

            return Consumer<RoutePlanningNotifier>(
              builder: (context, n, _) {
                return FutureBuilder<List<SavedRouteRecord>>(
                  future: n.savedFuture,
                  builder: (context, savedSnap) {
                    final saved = savedSnap.data ?? const [];
                    final cities = n.citySuggestions(data);
                    return Column(
                      children: [
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(16, 16, 16, listBottomPad),
                            children: [
                              const Text(
                                'Nereden nereye?',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Başlangıçta kalmazsınız. Yol üzerinde mola; varışta konaklama önerilir.',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: AppColors.campaignSummaryMuted
                                      .withValues(alpha: 0.95),
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (saved.isNotEmpty) ...[
                                Text(
                                  AppStrings.routePlanSavedTitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                ...saved.map((r) => _SavedCard(
                                      record: r,
                                      onTap: () => _loadSaved(r, data),
                                      onDelete: () => n.deleteSaved(r.name),
                                    )),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: n.resetNewRouteForm,
                                    child: const Text(AppStrings.routePlanNew),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              _WhiteCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    IlAutocompleteField(
                                      controller: n.startCity,
                                      cities: cities,
                                      label: 'Başlangıç (hareket)',
                                      hint: AppStrings.routePlanStartHint,
                                      icon: Icons.trip_origin_rounded,
                                      iconColor: const Color(0xFF2E7D32),
                                      onCommitted: (_) => n.touchDraft(),
                                    ),
                                    for (var i = 0; i < n.intermediate.length; i++) ...[
                                      const SizedBox(height: 14),
                                      Builder(
                                        builder: (_) {
                                          final isArrival =
                                              i == n.intermediate.length - 1;
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      isArrival
                                                          ? 'Varış'
                                                          : 'Yolda mola ili (opsiyonel)',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: (isArrival
                                                                ? const Color(0xFFC62828)
                                                                : AppColors.primary)
                                                            .withValues(alpha: 0.95),
                                                      ),
                                                    ),
                                                  ),
                                                  if (n.intermediate.length > 1)
                                                    IconButton(
                                                      onPressed: () =>
                                                          n.removeStop(i),
                                                      icon: const Icon(
                                                        Icons
                                                            .remove_circle_outline_rounded,
                                                        size: 20,
                                                      ),
                                                      color: AppColors
                                                          .campaignSummaryMuted,
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              IlAutocompleteField(
                                                controller:
                                                    n.intermediate[i].city,
                                                cities: cities,
                                                label: '',
                                                hint: isArrival
                                                    ? 'Örn: Antalya'
                                                    : 'Örn: Bolu',
                                                icon: isArrival
                                                    ? Icons.flag_rounded
                                                    : Icons.local_cafe_rounded,
                                                iconColor: isArrival
                                                    ? const Color(0xFFC62828)
                                                    : const Color(0xFFEF6C00),
                                                onCommitted: (v) => n
                                                    .trimStopSelectionsForCity(
                                                  i,
                                                  v,
                                                  data,
                                                ),
                                              ),
                                              if (isArrival) ...[
                                                const SizedBox(height: 10),
                                                TextField(
                                                  controller:
                                                      n.intermediate[i].days,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  decoration: InputDecoration(
                                                    labelText:
                                                        'Varışta kaç gün kalacaksınız?',
                                                    filled: true,
                                                    fillColor: AppColors
                                                        .suggestionFieldBg
                                                        .withValues(alpha: 0.65),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                      borderSide:
                                                          BorderSide.none,
                                                    ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                      borderSide: BorderSide(
                                                        color: AppColors.primary
                                                            .withValues(
                                                                alpha: 0.12),
                                                      ),
                                                    ),
                                                    isDense: true,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: n.addStop,
                                        icon: const Icon(
                                          Icons.add_circle_outline_rounded,
                                        ),
                                        label: const Text('Yolda mola ili ekle'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () => unawaited(_openAdvice(data)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Rota oluştur',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        RotalinkBannerAd(adsEnabled: AdService.adsEnabled),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_RoutePlanCitiesPageState._cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
        child: child,
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  const _SavedCard({
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  final SavedRouteRecord record;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          title: Text(record.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            record.stops.map((s) => s.city).join(' → '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: onDelete,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
