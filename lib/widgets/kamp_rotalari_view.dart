import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/kamp_repository.dart';
import '../services/view_counter_service.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';
import '../utils/maps_launch.dart';
import 'ara_action_button.dart';
import 'rotalink_tile_layer.dart';
import 'view_count_label.dart';

class KampRotalariBody extends StatefulWidget {
  const KampRotalariBody({super.key, required this.iller});

  final Set<String> iller;

  @override
  State<KampRotalariBody> createState() => _KampRotalariBodyState();
}

class _KampRotalariBodyState extends State<KampRotalariBody> {
  static const _favoritesKey = 'rotalink_camp_favorites';

  var _filtre = const KampFiltre();
  var _harita = false;
  var _favoriler = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_favorileriYukle());
  }

  Future<void> _favorileriYukle() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(
      () =>
          _favoriler = (prefs.getStringList(_favoritesKey) ?? const []).toSet(),
    );
  }

  Future<void> _favoriDegistir(KampAlani item) async {
    final next = Set<String>.from(_favoriler);
    final key = item.id.trim().isEmpty ? '${item.il}\u0001${item.ad}' : item.id;
    if (!next.add(key)) next.remove(key);
    setState(() => _favoriler = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, next.toList()..sort());
  }

  bool _favoriMi(KampAlani item) {
    final key = item.id.trim().isEmpty ? '${item.il}\u0001${item.ad}' : item.id;
    return _favoriler.contains(key);
  }

  void _chip(KampFiltre next) => setState(() => _filtre = next);

  int get _aktifFiltreSayisi => [
    _filtre.sorgu.trim().isNotEmpty,
    _filtre.cadir,
    _filtre.karavan,
    _filtre.ucretsiz,
    _filtre.ucretli,
    _filtre.elektrik,
    _filtre.dus,
    _filtre.tuvalet,
  ].where((x) => x).length;

  Future<void> _filtreleriAc() async {
    final next = await showModalBottomSheet<KampFiltre>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _KampFiltreSheet(initial: _filtre),
    );
    if (next != null && mounted) setState(() => _filtre = next);
  }

  @override
  Widget build(BuildContext context) {
    final kaynak = KampRepository.instance.forIller(widget.iller);
    final goster = kampFiltrele(kaynak, _filtre);
    final yuklendi =
        KampRepository.instance.items.value.isNotEmpty || kaynak.isNotEmpty;
    return Column(
      children: [
        _KampToolbar(
          count: goster.length,
          mapMode: _harita,
          activeFilterCount: _aktifFiltreSayisi,
          onFilter: _filtreleriAc,
          onViewChanged: goster.isEmpty
              ? null
              : () => setState(() => _harita = !_harita),
        ),
        SizedBox(
          height: 45,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 7),
            children: [
              _quickFilter(
                'Tümü',
                _aktifFiltreSayisi == 0,
                () => _chip(const KampFiltre()),
              ),
              _quickFilter(
                'Çadır',
                _filtre.cadir,
                () => _chip(_kopya(cadir: !_filtre.cadir)),
              ),
              _quickFilter(
                'Karavan',
                _filtre.karavan,
                () => _chip(_kopya(karavan: !_filtre.karavan)),
              ),
              _quickFilter(
                'Ücretsiz',
                _filtre.ucretsiz,
                () => _chip(_kopya(ucretsiz: !_filtre.ucretsiz)),
              ),
            ],
          ),
        ),
        Expanded(
          child: goster.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      yuklendi
                          ? 'Bu aramada kamp alanı yok. Bilinmeyen yer eklenmez.'
                          : 'Kamp listesi henüz inmedi. İnternet bağlantınızı kontrol edin.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6B7C82),
                        height: 1.4,
                      ),
                    ),
                  ),
                )
              : _harita
              ? _KampHarita(items: goster)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 7, 14, 24),
                  itemCount: goster.length + 1,
                  separatorBuilder: (_, i) => i == goster.length - 1
                      ? const SizedBox.shrink()
                      : const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    if (i == goster.length) return const _Atif();
                    final item = goster[i];
                    return _KampKart(
                      item: item,
                      isFavorite: _favoriMi(item),
                      onFavorite: () => unawaited(_favoriDegistir(item)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  KampFiltre _kopya({
    bool? cadir,
    bool? karavan,
    bool? ucretsiz,
    bool? ucretli,
    bool? elektrik,
    bool? dus,
    bool? tuvalet,
  }) {
    return KampFiltre(
      sorgu: _filtre.sorgu,
      cadir: cadir ?? _filtre.cadir,
      karavan: karavan ?? _filtre.karavan,
      ucretsiz: ucretsiz ?? _filtre.ucretsiz,
      ucretli: ucretli ?? _filtre.ucretli,
      elektrik: elektrik ?? _filtre.elektrik,
      dus: dus ?? _filtre.dus,
      tuvalet: tuvalet ?? _filtre.tuvalet,
    );
  }

  Widget _quickFilter(String label, bool secili, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: secili,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        selectedColor: AraUi.activeFill,
        backgroundColor: AraUi.inactiveFillOf(context),
        checkmarkColor: AraUi.activeForeground,
        labelStyle: TextStyle(
          color: secili ? AraUi.activeForeground : AraUi.inactiveForegroundOf(context),
          fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
        ),
        shape: const StadiumBorder(),
        side: BorderSide(
          color: secili ? AraUi.activeFill : AraUi.inactiveBorderOf(context),
        ),
      ),
    );
  }
}

class _KampToolbar extends StatelessWidget {
  const _KampToolbar({
    required this.count,
    required this.mapMode,
    required this.activeFilterCount,
    required this.onFilter,
    required this.onViewChanged,
  });

  final int count;
  final bool mapMode;
  final int activeFilterCount;
  final VoidCallback onFilter;
  final VoidCallback? onViewChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AraUi.kamp.bg,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.terrain_rounded, color: AraUi.kamp.fg, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kamp keşfi',
                  style: TextStyle(
                    color: AppColors.textStrongOf(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$count kamp alanı bulundu',
                  style: TextStyle(
                    color: AppColors.textMutedOf(context),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          _ToolbarButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filtrele',
            badge: activeFilterCount,
            onTap: onFilter,
          ),
          const SizedBox(width: 7),
          _ToolbarButton(
            icon: mapMode ? Icons.view_agenda_outlined : Icons.map_outlined,
            tooltip: mapMode ? 'Liste görünümü' : 'Harita görünümü',
            onTap: onViewChanged,
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: AppColors.surfaceOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AraUi.inactiveBorderOf(context)),
          ),
          child: IconButton(
            onPressed: onTap,
            tooltip: tooltip,
            icon: Icon(icon, size: 20, color: AppColors.primary),
          ),
        ),
        if (badge > 0)
          Positioned(
            right: -3,
            top: -4,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFE57D35),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _KampFiltreSheet extends StatefulWidget {
  const _KampFiltreSheet({required this.initial});

  final KampFiltre initial;

  @override
  State<_KampFiltreSheet> createState() => _KampFiltreSheetState();
}

class _KampFiltreSheetState extends State<_KampFiltreSheet> {
  late final TextEditingController _query;
  late KampFiltre _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    _query = TextEditingController(text: widget.initial.sorgu);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  KampFiltre _copy({
    String? sorgu,
    bool? cadir,
    bool? karavan,
    bool? ucretsiz,
    bool? ucretli,
    bool? elektrik,
    bool? dus,
    bool? tuvalet,
  }) {
    return KampFiltre(
      sorgu: sorgu ?? _value.sorgu,
      cadir: cadir ?? _value.cadir,
      karavan: karavan ?? _value.karavan,
      ucretsiz: ucretsiz ?? _value.ucretsiz,
      ucretli: ucretli ?? _value.ucretli,
      elektrik: elektrik ?? _value.elektrik,
      dus: dus ?? _value.dus,
      tuvalet: tuvalet ?? _value.tuvalet,
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: keyboard),
      child: Material(
        color: AppColors.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7E1DF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Kamp alanını bul',
                style: TextStyle(
                  color: AppColors.textStrongOf(context),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'İl, ilçe veya kamp adına göre arayın; ihtiyaçlarınıza uygun özellikleri seçin.',
                style: TextStyle(
                  color: AppColors.textMutedOf(context),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _query,
                autofocus: false,
                textInputAction: TextInputAction.search,
                cursorColor: AppColors.primary,
                style: TextStyle(
                  color: AppColors.searchTextOf(context),
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                ),
                onChanged: (value) =>
                    setState(() => _value = _copy(sorgu: value)),
                decoration: InputDecoration(
                  hintText: 'İl, ilçe veya kamp adı',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.primary,
                  ),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _query.clear();
                            setState(() => _value = _copy(sorgu: ''));
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: AppColors.fieldFillOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const _FilterTitle('Kamp türü'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _sheetChip(
                    'Çadır',
                    Icons.cabin_outlined,
                    _value.cadir,
                    () => _value = _copy(cadir: !_value.cadir),
                  ),
                  _sheetChip(
                    'Karavan',
                    Icons.rv_hookup_rounded,
                    _value.karavan,
                    () => _value = _copy(karavan: !_value.karavan),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _FilterTitle('Ücret'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _sheetChip(
                    'Ücretsiz',
                    Icons.money_off_csred_outlined,
                    _value.ucretsiz,
                    () => _value = _copy(ucretsiz: !_value.ucretsiz),
                  ),
                  _sheetChip(
                    'Ücretli',
                    Icons.payments_outlined,
                    _value.ucretli,
                    () => _value = _copy(ucretli: !_value.ucretli),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _FilterTitle('Olanaklar'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _sheetChip(
                    'Elektrik',
                    Icons.bolt_rounded,
                    _value.elektrik,
                    () => _value = _copy(elektrik: !_value.elektrik),
                  ),
                  _sheetChip(
                    'Duş',
                    Icons.shower_outlined,
                    _value.dus,
                    () => _value = _copy(dus: !_value.dus),
                  ),
                  _sheetChip(
                    'Tuvalet',
                    Icons.wc_rounded,
                    _value.tuvalet,
                    () => _value = _copy(tuvalet: !_value.tuvalet),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      _query.clear();
                      setState(() => _value = const KampFiltre());
                    },
                    child: const Text('Temizle'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, _value),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Filtreleri uygula'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetChip(
    String label,
    IconData icon,
    bool selected,
    VoidCallback update,
  ) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => setState(update),
      avatar: Icon(
        icon,
        size: 17,
        color: selected ? AppColors.primary : const Color(0xFF718187),
      ),
      label: Text(label),
      selectedColor: AppColors.primary.withValues(alpha: 0.14),
      checkmarkColor: AppColors.primary,
      side: BorderSide(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.32)
            : AppColors.primary.withValues(alpha: 0.08),
      ),
    );
  }
}

class _FilterTitle extends StatelessWidget {
  const _FilterTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textStrongOf(context),
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Atif extends StatelessWidget {
  const _Atif();

  @override
  Widget build(BuildContext context) {
    final metin = KampRepository.instance.atif.isEmpty
        ? 'Konum verisi © OpenStreetMap katkıları (ODbL). Resmî fiyat değildir.'
        : '${KampRepository.instance.atif}. Resmî fiyat değildir.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        metin,
        style: const TextStyle(
          color: Color(0xFF90A4AE),
          fontSize: 11.5,
          height: 1.35,
        ),
      ),
    );
  }
}

class _KampKart extends StatelessWidget {
  const _KampKart({
    required this.item,
    required this.isFavorite,
    required this.onFavorite,
  });

  final KampAlani item;
  final bool isFavorite;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final yer = [
      item.il,
      if (item.ilce?.trim().isNotEmpty ?? false) item.ilce!,
    ].join(' / ');
    final features = _oneCikanOzellikler(item);
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () => unawaited(showKampDetay(context, item)),
        child: Ink(
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.09),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              item.ad,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textStrongOf(context),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onFavorite,
                          tooltip: isFavorite
                              ? 'Favorilerden çıkar'
                              : 'Favorilere ekle',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isFavorite
                                ? AraUi.favorite
                                : AraUi.mutedTextOf(context),
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: Color(0xFF6F8186),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            yer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF6F8186),
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        if (item.dogrulama == 'resmi') ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 3),
                          const Text(
                            'Doğrulandı',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _kampIcon(item.kampTuru),
                                size: 14,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                kampTuruEtiket(item.kampTuru),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_ucret(item) case final price?)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7F4EE),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              price,
                              style: const TextStyle(
                                color: Color(0xFF176B5B),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    ViewCountLabel(
                      viewId: ViewCounterService.keyFor(
                        ViewCategory.kamp,
                        item.il,
                        item.id.isNotEmpty ? item.id : item.ad,
                      ),
                    ),
                    if (features.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final feature in features.take(4))
                            _FeaturePill(icon: feature.$1, label: feature.$2),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    AraActionRow(
                      children: [
                        AraActionButton(
                          icon: Icons.navigation_outlined,
                          label: 'Yol tarifi',
                          onTap: () => unawaited(
                            openInNativeMaps(
                              context,
                              query: '${item.ad} ${item.il}',
                              latitude: item.enlem,
                              longitude: item.boylam,
                            ),
                          ),
                        ),
                        AraActionButton(
                          icon: Icons.info_outline_rounded,
                          label: 'Detay',
                          primary: true,
                          onTap: () => unawaited(showKampDetay(context, item)),
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
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6F4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF49635D),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

List<(IconData, String)> _oneCikanOzellikler(KampAlani k) => [
  if (k.cadir == true) (Icons.cabin_outlined, 'Çadır'),
  if (k.karavan == true || k.kampTuru == 'karavan')
    (Icons.rv_hookup_rounded, 'Karavan'),
  if (k.elektrik == true) (Icons.bolt_rounded, 'Elektrik'),
  if (k.tuvalet == true) (Icons.wc_rounded, 'Tuvalet'),
  if (k.dus == true) (Icons.shower_outlined, 'Duş'),
  if (k.icmeSuyu == true) (Icons.water_drop_outlined, 'İçme suyu'),
  if (k.wifi == true) (Icons.wifi_rounded, 'Wi-Fi'),
  if (k.otopark == true) (Icons.local_parking_rounded, 'Otopark'),
  if (k.denizeYakin == true) (Icons.waves_rounded, 'Denize yakın'),
];

IconData _kampIcon(String tur) {
  switch (tur) {
    case 'karavan':
      return Icons.rv_hookup_rounded;
    case 'glamping':
      return Icons.cabin_rounded;
    case 'milli_park':
    case 'orman_parki':
      return Icons.forest_rounded;
    case 'belediye':
      return Icons.account_balance_outlined;
    default:
      return Icons.terrain_rounded;
  }
}

List<Color> _kampGradient(String tur) {
  switch (tur) {
    case 'karavan':
      return const [Color(0xFF34556D), Color(0xFF4E8192)];
    case 'glamping':
      return const [Color(0xFF7A5543), Color(0xFFB17A59)];
    case 'milli_park':
    case 'orman_parki':
      return const [Color(0xFF285B45), Color(0xFF4A8B63)];
    case 'belediye':
      return const [Color(0xFF365E69), Color(0xFF4A8990)];
    default:
      return const [Color(0xFF176B5B), Color(0xFF3C9678)];
  }
}

String? _ucret(KampAlani k) {
  if (k.resmiFiyat) {
    final birim = k.fiyatBirim == null ? '' : ' / ${k.fiyatBirim}';
    return '${k.fiyat!.toStringAsFixed(k.fiyat! == k.fiyat!.roundToDouble() ? 0 : 2)} ₺$birim';
  }
  if (k.ucret == 'ucretsiz') return 'Ücretsiz';
  if (k.ucret == 'ucretli') return 'Ücretli';
  return null;
}

class _KampHarita extends StatelessWidget {
  const _KampHarita({required this.items});

  final List<KampAlani> items;

  @override
  Widget build(BuildContext context) {
    final ilk = LatLng(items.first.enlem, items.first.boylam);
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: ilk,
              initialZoom: items.length == 1 ? 12 : 6,
            ),
            children: [
              const RotalinkTileLayer(),
              MarkerLayer(
                markers: [
                  for (final k in items)
                    Marker(
                      point: LatLng(k.enlem, k.boylam),
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => unawaited(showKampDetay(context, k)),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            _kampIcon(k.kampTuru),
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: 12,
          left: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.place_rounded,
                  size: 17,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  '${items.length} kamp alanı',
                  style: TextStyle(
                    color: AppColors.textStrongOf(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showKampDetay(BuildContext context, KampAlani k) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => ViewRecorder(
        viewId: ViewCounterService.keyFor(
          ViewCategory.kamp,
          k.il,
          k.id.isNotEmpty ? k.id : k.ad,
        ),
        child: _KampDetaySheet(item: k, controller: controller),
      ),
    ),
  );
}

class _KampDetaySheet extends StatelessWidget {
  const _KampDetaySheet({required this.item, required this.controller});

  final KampAlani item;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final features = _oneCikanOzellikler(item);
    return Material(
      color: const Color(0xFFF7FAF9),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: controller,
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _kampGradient(item.kampTuru),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        _kampIcon(item.kampTuru),
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kampTuruEtiket(item.kampTuru),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.ad,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: Colors.white,
                      size: 17,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '${item.il}${item.ilce == null ? '' : ' / ${item.ilce}'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (item.dogrulama == 'resmi')
                      const _WhiteBadge(
                        icon: Icons.verified_rounded,
                        label: 'Resmî kaynak',
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.adres != null) ...[
                  _DetailCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.pin_drop_outlined,
                          color: AppColors.primary,
                          size: 21,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.adres!,
                            style: const TextStyle(
                              color: Color(0xFF50625F),
                              height: 1.4,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (features.isNotEmpty) ...[
                  const _DetailSectionTitle('Olanaklar'),
                  _DetailCard(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final feature in features)
                          _FeaturePill(icon: feature.$1, label: feature.$2),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                ],
                const _DetailSectionTitle('Kamp bilgileri'),
                _DetailCard(
                  child: Column(
                    children: _satirlar([
                      ('Ücret', _ucret(item)),
                      ('Motokaravan', _evet(item.motokaravan)),
                      ('Atık boşaltma', _evet(item.atik)),
                      ('Telefon', item.telefon),
                      ('Rezervasyon', item.rezervasyon),
                      (
                        'Bakanlık belgesi',
                        item.bakanlikBelgeNo == null
                            ? null
                            : 'Belgeli (No ${item.bakanlikBelgeNo})',
                      ),
                      ('Son kontrol', _tarih(item.sonKontrol)),
                      (
                        'Doğrulama',
                        item.dogrulama == 'resmi'
                            ? 'Resmî kaynak'
                            : 'Açık veri',
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => unawaited(
                      openInNativeMaps(
                        context,
                        query: '${item.ad} ${item.il}',
                        latitude: item.enlem,
                        longitude: item.boylam,
                      ),
                    ),
                    icon: const Icon(Icons.navigation_rounded, size: 19),
                    label: const Text('Yol tarifi al'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
                if (item.kaynakUrl != null || item.web != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (item.kaynakUrl != null)
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () => unawaited(_ac(item.kaynakUrl!)),
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 17,
                            ),
                            label: const Text('Kaynak'),
                          ),
                        ),
                      if (item.web != null)
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              final uri = Uri.tryParse(item.web!);
                              if (uri != null) unawaited(_ac(uri));
                            },
                            icon: const Icon(Icons.language_rounded, size: 17),
                            label: const Text('Resmî site'),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  item.atif.isEmpty
                      ? '© OpenStreetMap katkıları (ODbL)'
                      : item.atif,
                  style: const TextStyle(
                    color: Color(0xFF90A4AE),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteBadge extends StatelessWidget {
  const _WhiteBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSectionTitle extends StatelessWidget {
  const _DetailSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textStrongOf(context),
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

Widget _satir(String ad, String deger) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            ad,
            style: const TextStyle(color: Color(0xFF78909C), fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            deger,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// Değeri bilinmeyen satır gösterilmez.
List<Widget> _satirlar(List<(String, String?)> rows) => [
  for (final (ad, deger) in rows)
    if (deger != null && deger.trim().isNotEmpty) _satir(ad, deger),
];

String? _evet(bool? v) {
  if (v == true) return 'Var';
  if (v == false) return 'Yok';
  return null;
}

String? _tarih(DateTime? d) {
  if (d == null) return null;
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

Future<void> _ac(Uri u) async {
  if (u.scheme != 'https' && u.scheme != 'http') return;
  try {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  } catch (_) {}
}
