import 'dart:async';
import 'package:flutter/material.dart';
import '../data/kis_kesfet_osm_piste_repository.dart';
import '../data/kis_kesfet_repository.dart';
import '../models/kis_kesfet_place.dart';
import '../navigation/rotalink_shell_scope.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';
import '../utils/search_normalize.dart';
import '../widgets/kis_kesfet_ui.dart';
import 'kis_kesfet_il_screen.dart';

class KisKesfetScreen extends StatefulWidget {
  const KisKesfetScreen({super.key, this.places});
  final List<KisKesfetPlace>? places;
  @override
  State<KisKesfetScreen> createState() => _KisKesfetScreenState();
}

class _KisKesfetScreenState extends State<KisKesfetScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  List<KisKesfetPlace>? _places;
  Object? _error;
  static const _kategoriler = [
    KisKesfetKategori.kayak,
    KisKesfetKategori.termal,
  ];
  KisKesfetKategori get _aktif => _kategoriler[_tabs.index];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _kategoriler.length, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.places != null) {
      _places = widget.places;
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final places = await KisKesfetRepository.load();
      await KisKesfetOsmPisteRepository.ensureLoaded();
      if (!mounted) return;
      setState(() {
        _places = places;
        _error = null;
      });
      unawaited(_refreshRemote());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _refreshRemote() async {
    final remote = await KisKesfetRepository.fetchRemote();
    if (!mounted || remote == null || remote.isEmpty) return;
    setState(() {
      _places = KisKesfetRepository.mergeById(_places ?? const [], remote);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = KisKesfetUi.accentOf(context, _aktif);
    return Scaffold(
      backgroundColor: AraUi.pageOf(context),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Geri',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surfaceOf(context),
                            foregroundColor: AppColors.textStrongOf(context),
                            side: BorderSide(
                              color: AppColors.borderOf(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Kış Keşfet',
                            style: TextStyle(
                              color: AppColors.textStrongOf(context),
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                        ),
                        Icon(Icons.ac_unit_rounded, color: accent, size: 22),
                      ],
                    ),
                    const SizedBox(height: 18),
                    KisKesfetHero(
                      kategori: _aktif,
                      eyebrow: 'KIŞA BİR ROTA ÇİZ',
                      title: KisKesfetUi.titleFor(_aktif),
                      subtitle: KisKesfetUi.subtitleFor(_aktif),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      textInputAction: TextInputAction.search,
                      style: TextStyle(color: AppColors.textStrongOf(context)),
                      decoration: InputDecoration(
                        hintText: 'Gitmek istediğin ili ara',
                        hintStyle: TextStyle(
                          color: AppColors.textMutedOf(context),
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(Icons.search_rounded, color: accent),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Aramayı temizle',
                                onPressed: () => setState(_search.clear),
                                icon: const Icon(Icons.close_rounded, size: 20),
                              ),
                        filled: true,
                        fillColor: AppColors.surfaceOf(context),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: AppColors.borderOf(context),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: AppColors.borderOf(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: accent, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (var i = 0; i < _kategoriler.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _KategoriChip(
                              kategori: _kategoriler[i],
                              selected: _tabs.index == i,
                              onTap: () {
                                FocusScope.of(context).unfocus();
                                _tabs.animateTo(i);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return _EmptyMessage(
        text: 'Kış Keşfet listesi açılamadı.',
        onRetry: () {
          setState(() => _error = null);
          unawaited(_load());
        },
      );
    }
    final places = _places;
    if (places == null) return const Center(child: CircularProgressIndicator());
    return TabBarView(
      controller: _tabs,
      children: [
        for (final kategori in _kategoriler)
          _IlList(kategori: kategori, places: places, query: _search.text),
      ],
    );
  }
}

class _KategoriChip extends StatelessWidget {
  const _KategoriChip({
    required this.kategori,
    required this.selected,
    required this.onTap,
  });
  final KisKesfetKategori kategori;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final ink = KisKesfetUi.accentOf(context, kategori);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? KisKesfetUi.tintOf(context, kategori)
            : AppColors.surfaceOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected
                ? ink.withValues(alpha: 0.5)
                : AppColors.borderOf(context),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
            child: Column(
              children: [
                Icon(
                  KisKesfetUi.iconFor(kategori),
                  size: 23,
                  color: selected ? ink : AppColors.textMutedOf(context),
                ),
                const SizedBox(height: 7),
                Text(
                  kategori.etiket,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? ink : AppColors.textStrongOf(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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

class _IlList extends StatelessWidget {
  const _IlList({
    required this.kategori,
    required this.places,
    required this.query,
  });
  final KisKesfetKategori kategori;
  final List<KisKesfetPlace> places;
  final String query;

  @override
  Widget build(BuildContext context) {
    final grouped = KisKesfetRepository.groupByIl(
      KisKesfetRepository.forCategory(places, kategori),
    );
    final needle = normalizeForSearch(query);
    final iller = KisKesfetRepository.sortedIller(grouped)
        .where(
          (il) => needle.isEmpty || normalizeForSearch(il).contains(needle),
        )
        .toList();
    if (grouped.isEmpty) {
      return const _EmptyMessage(
        text: 'Bu kategoride henüz doğrulanmış kayıt yok.',
      );
    }
    if (iller.isEmpty) {
      return const _EmptyMessage(text: 'Aradığınız il bu kategoride yok.');
    }
    final accent = KisKesfetUi.accentOf(context, kategori);
    return ListView.separated(
      key: PageStorageKey(kategori),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + RotalinkShellScope.scrollBottomPadding(context),
      ),
      itemCount: iller.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  'Rotanı seç',
                  style: TextStyle(
                    color: AppColors.textStrongOf(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Text(
                '${iller.length} il',
                style: TextStyle(
                  color: AppColors.textMutedOf(context),
                  fontSize: 12,
                ),
              ),
            ],
          );
        }
        final il = iller[index - 1];
        final rows = grouped[il] ?? const <KisKesfetPlace>[];
        return Material(
          color: AppColors.surfaceOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: AppColors.borderOf(context)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => KisKesfetIlScreen(
                    il: il,
                    kategori: kategori,
                    places: rows,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 60,
                    decoration: BoxDecoration(
                      color: KisKesfetUi.tintOf(context, kategori),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      KisKesfetUi.iconFor(kategori),
                      color: accent,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          il,
                          style: TextStyle(
                            color: AppColors.textStrongOf(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          KisKesfetUi.ilOzeti(kategori, rows),
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          rows.take(2).map((p) => p.isim).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMutedOf(context),
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: accent, size: 19),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          children: [
            Icon(
              Icons.travel_explore_rounded,
              size: 40,
              color: AppColors.textMutedOf(context),
            ),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMutedOf(context),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar dene'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
