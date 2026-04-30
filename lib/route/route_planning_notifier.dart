import 'package:flutter/material.dart';

import '../data/firebase_rota_repository.dart';
import '../data/saved_routes_repository.dart';
import '../l10n/app_strings.dart';
import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
import '../models/route_stop.dart';
import '../utils/main_map_search.dart';

/// Kotlin [MainActivity.showRoutePlanningFlow] + [getRouteStops] ile aynı iş kuralları;
/// UI katmanından ayrılmış rota planı taslağı.
class RoutePlanningNotifier extends ChangeNotifier {
  RoutePlanningNotifier({required SavedRoutesRepository savedRoutesRepository})
      : _savedRoutesRepository = savedRoutesRepository {
    _startCity = TextEditingController();
    _intermediate.add(RouteStopDraft());
    _reloadSavedFuture();
  }

  final SavedRoutesRepository _savedRoutesRepository;
  bool _disposed = false;

  late final TextEditingController _startCity;
  final List<RouteStopDraft> _intermediate = [];

  Future<List<SavedRouteRecord>> _savedFuture = Future.value(const []);
  bool _calculating = false;
  String? _justAddedStopId;

  TextEditingController get startCity => _startCity;
  List<RouteStopDraft> get intermediate => List.unmodifiable(_intermediate);
  bool get calculating => _calculating;
  String? get justAddedStopId => _justAddedStopId;
  Future<List<SavedRouteRecord>> get savedFuture => _savedFuture;

  void _reloadSavedFuture() {
    _savedFuture = _savedRoutesRepository.loadAll();
    notifyListeners();
  }

  List<String> citySuggestions(RotaDataState data) {
    final kaynak = MainMapSearch.tesisKaynagiArama(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    return kaynak.map((e) => e.il).where((s) => s.trim().isNotEmpty).toSet().toList()..sort();
  }

  void addStop() {
    final row = RouteStopDraft();
    _intermediate.add(row);
    _justAddedStopId = row.id;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      _justAddedStopId = null;
      notifyListeners();
    });
  }

  void removeStop(int i) {
    if (_intermediate.length <= 1) return;
    _intermediate[i].dispose();
    _intermediate.removeAt(i);
    notifyListeners();
  }

  void reorderStops(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _intermediate.removeAt(oldIndex);
    _intermediate.insert(newIndex, item);
    notifyListeners();
  }

  /// Akıllı kürasyon: 1 konak, 2 yemek, 3 gezi.
  static const int _seedKonakCap = 1;
  static const int _seedYemekCap = 2;
  static const int _seedGeziCap = 3;

  void trimStopSelectionsForCity(int stopIndex, String il, RotaDataState data) {
    if (stopIndex < 0 || stopIndex >= _intermediate.length) return;
    final row = _intermediate[stopIndex];
    final n = il.trim().toLowerCase();
    if (n.isEmpty) return;
    row.konakSecimler.removeWhere((m) => m.il.trim().toLowerCase() != n);
    row.geziSecimler.removeWhere((g) => g.il.trim().toLowerCase() != n);
    row.yemekSecimler.removeWhere((y) => y.il.trim().toLowerCase() != n);
    row.suggestionsTabIndex = 0;
    seedSuggestionsForStop(stopIndex, data);
    notifyListeners();
  }

  /// Konak (0) / Gezi (1) / Yemek (2) sekmesi — geri tuşu ile bir önceki sekmeye dönüş için.
  void setStopSuggestionsTab(int stopIndex, int tab) {
    if (stopIndex < 0 || stopIndex >= _intermediate.length) return;
    final t = tab.clamp(0, 2);
    final row = _intermediate[stopIndex];
    if (row.suggestionsTabIndex == t) return;
    row.suggestionsTabIndex = t;
    notifyListeners();
  }

  /// İl seçildikten sonra sabit sıralı öneriler (ekle/kaldır ile düzenlenir).
  void seedSuggestionsForStop(int stopIndex, RotaDataState data) {
    if (stopIndex < 0 || stopIndex >= _intermediate.length) return;
    final row = _intermediate[stopIndex];
    final il = row.city.text.trim();
    if (il.isEmpty) return;
    final ilKey = il.toLowerCase();

    final kaynak = MainMapSearch.tesisKaynagiArama(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    final konaklar = kaynak.where((m) => m.il.trim().toLowerCase() == ilKey).toList()
      ..sort((a, b) => a.isim.compareTo(b.isim));

    final geziRaw = data.gezi
        .where((g) => g.il.trim().toLowerCase() == ilKey && g.isim.trim().isNotEmpty)
        .toList();
    final geziUnique = _uniqueGeziByName(geziRaw)..sort((a, b) => a.isim.compareTo(b.isim));

    final yemekRaw = data.yemek
        .where((y) => y.il.trim().toLowerCase() == ilKey && y.isim.trim().isNotEmpty)
        .toList();
    final yemekUnique = _uniqueGeziByName(yemekRaw)..sort((a, b) => a.isim.compareTo(b.isim));

    row.konakSecimler
      ..clear()
      ..addAll(konaklar.take(_seedKonakCap));
    row.geziSecimler
      ..clear()
      ..addAll(geziUnique.take(_seedGeziCap));
    row.yemekSecimler
      ..clear()
      ..addAll(yemekUnique.take(_seedYemekCap));
  }

  /// Taslak değişti (ör. başlangıç ili); harita önizlemesi dinleyicileri için.
  void touchDraft() {
    notifyListeners();
  }

  /// OSRM / harita önizlemesi: geçerli şehir zinciri (ara duraklarda hatalı il satırı atlanır).
  List<RouteStop>? previewStopsForMap(RotaDataState data) {
    final kaynak = MainMapSearch.tesisKaynagiArama(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    final allCities = kaynak.map((e) => e.il.toLowerCase()).toSet();
    final start = _startCity.text.trim();
    if (start.isEmpty || !allCities.contains(start.toLowerCase())) return null;
    final stops = <RouteStop>[RouteStop(city: start, days: 0)];
    for (final row in _intermediate) {
      final city = row.city.text.trim();
      if (city.isEmpty) continue;
      if (!allCities.contains(city.toLowerCase())) continue;
      stops.add(RouteStop(city: city, days: 1));
    }
    final distinct = _distinctByCity(stops);
    if (distinct.length < 2) return null;
    return distinct;
  }

  static List<GeziYemekItem> _uniqueGeziByName(List<GeziYemekItem> items) {
    final seen = <String>{};
    final out = <GeziYemekItem>[];
    for (final g in items) {
      final k = g.isim.trim().toLowerCase();
      if (k.isEmpty || seen.contains(k)) continue;
      seen.add(k);
      out.add(g);
    }
    return out;
  }

  void addStopKonak(int stopIndex, Misafirhane m) {
    if (stopIndex < 0 || stopIndex >= _intermediate.length) return;
    final row = _intermediate[stopIndex];
    if (row.konakSecimler.any((x) => x.sameFavoriteIdentity(m))) return;
    row.konakSecimler.add(m);
    notifyListeners();
  }

  void removeStopKonak(int stopIndex, Misafirhane m) {
    if (stopIndex < 0 || stopIndex >= _intermediate.length) return;
    _intermediate[stopIndex].konakSecimler.removeWhere((x) => x.sameFavoriteIdentity(m));
    notifyListeners();
  }

  void addStopGezi(int stopIndex, GeziYemekItem g) {
    if (stopIndex < 0 || stopIndex >= _intermediate.length) return;
    final row = _intermediate[stopIndex];
    if (row.geziSecimler.any((x) => _sameGeziKey(x, g))) return;
    row.geziSecimler.add(g);
    notifyListeners();
  }

  void removeStopGezi(int stopIndex, GeziYemekItem g) {
    if (stopIndex < 0 || stopIndex >= _intermediate.length) return;
    _intermediate[stopIndex].geziSecimler.removeWhere((x) => _sameGeziKey(x, g));
    notifyListeners();
  }

  void addStopYemek(int stopIndex, GeziYemekItem y) {
    if (stopIndex < 0 || stopIndex >= _intermediate.length) return;
    final row = _intermediate[stopIndex];
    if (row.yemekSecimler.any((x) => _sameGeziKey(x, y))) return;
    row.yemekSecimler.add(y);
    notifyListeners();
  }

  void removeStopYemek(int stopIndex, GeziYemekItem y) {
    if (stopIndex < 0 || stopIndex >= _intermediate.length) return;
    _intermediate[stopIndex].yemekSecimler.removeWhere((x) => _sameGeziKey(x, y));
    notifyListeners();
  }

  static bool _sameGeziKey(GeziYemekItem a, GeziYemekItem b) =>
      a.isim.trim() == b.isim.trim() && a.il.trim().toLowerCase() == b.il.trim().toLowerCase();

  void resetNewRouteForm() {
    _startCity.clear();
    for (final r in _intermediate) {
      r.dispose();
    }
    _intermediate
      ..clear()
      ..add(RouteStopDraft());
    notifyListeners();
  }

  void setCalculating(bool v) {
    if (_calculating == v) return;
    _calculating = v;
    notifyListeners();
  }

  List<RouteStop>? collectStops(RotaDataState data, void Function(String) snack) {
    final kaynak = MainMapSearch.tesisKaynagiArama(
      aramaIcinTumTesisler: data.aramaIcinTumTesisler,
      misafirhaneler: data.misafirhaneler,
    );
    final allCities = kaynak.map((e) => e.il.toLowerCase()).toSet();

    final start = _startCity.text.trim();
    if (start.isEmpty || !allCities.contains(start.toLowerCase())) {
      snack(AppStrings.routePlanInvalidStart);
      return null;
    }

    final stops = <RouteStop>[RouteStop(city: start, days: 0)];
    for (final row in _intermediate) {
      final city = row.city.text.trim();
      final daysRaw = int.tryParse(row.days.text.trim()) ?? 1;
      final days = daysRaw < 1 ? 1 : daysRaw;
      if (city.isEmpty) continue;
      if (!allCities.contains(city.toLowerCase())) {
        snack('${AppStrings.routePlanInvalidStop} ($city)');
        return null;
      }
      final cityKey = city.toLowerCase();
      final konak = row.konakSecimler
          .where((m) => m.il.trim().toLowerCase() == cityKey)
          .toList();
      final gezi = row.geziSecimler
          .where((g) => g.il.trim().toLowerCase() == cityKey)
          .toList();
      final yemek = row.yemekSecimler
          .where((y) => y.il.trim().toLowerCase() == cityKey)
          .toList();
      final nights = days < 1 ? 1 : days;
      final items = <Object>[...konak];
      for (var idx = 0; idx < gezi.length; idx++) {
        final dayNum = nights > 0 ? (idx % nights) + 1 : 1;
        items.add(gezi[idx].forRouteSuggestion(turLabel: 'Gezi', day: dayNum));
      }
      for (var idx = 0; idx < yemek.length; idx++) {
        final dayNum = nights > 0 ? (idx % nights) + 1 : 1;
        items.add(yemek[idx].forRouteSuggestion(turLabel: 'Yemek', day: dayNum));
      }
      stops.add(RouteStop(city: city, days: days, items: items));
    }

    final distinct = _distinctByCity(stops);
    if (distinct.length < 2) {
      snack(AppStrings.routePlanNeedTarget);
      return null;
    }
    return distinct;
  }

  List<RouteStop> _distinctByCity(List<RouteStop> stops) {
    final seen = <String>{};
    final out = <RouteStop>[];
    for (final s in stops) {
      final k = s.city.trim().toLowerCase();
      if (seen.contains(k)) continue;
      seen.add(k);
      out.add(s);
    }
    return out;
  }

  Future<void> deleteSaved(String name) async {
    await _savedRoutesRepository.deleteByName(name);
    _reloadSavedFuture();
  }

  Future<void> promptSaveRoute(
    BuildContext context,
    List<RouteStop> stops,
    void Function(String) snack,
  ) async {
    final nameCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(AppStrings.routePlanSaveTitle),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(hintText: AppStrings.routePlanSaveNameHint),
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        snack(AppStrings.routePlanSaveEmptyName);
        return;
      }
      final lites = stops.map((s) => RouteStopLite(city: s.city, days: s.days)).toList();
      await _savedRoutesRepository.upsert(
        SavedRouteRecord(
          name: name,
          savedDateMillis: DateTime.now().millisecondsSinceEpoch,
          stops: lites,
        ),
      );
      if (context.mounted) {
        snack(AppStrings.routePlanSaveSuccess);
      }
      // Diyalog alt ağacı tam kalktıktan sonra dinleyicileri güncelle (çerçeve iddiası önlenir).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        _reloadSavedFuture();
      });
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _startCity.dispose();
    for (final r in _intermediate) {
      r.dispose();
    }
    super.dispose();
  }
}

class RouteStopDraft {
  RouteStopDraft()
      : id = 's${_gen++}',
        city = TextEditingController(),
        days = TextEditingController(text: '1'),
        konakSecimler = [],
        geziSecimler = [],
        yemekSecimler = [],
        suggestionsTabIndex = 0;

  static var _gen = 0;
  final String id;
  final TextEditingController city;
  final TextEditingController days;

  /// 0 = Konak, 1 = Gezi, 2 = Yemek öneri sekmesi.
  int suggestionsTabIndex;

  /// Bu durak için seçilen misafirhaneler (il ile [city] uyumlu olmalı).
  final List<Misafirhane> konakSecimler;

  /// Gezi / yemek RTDB kayıtları (il eşleşmesi).
  final List<GeziYemekItem> geziSecimler;
  final List<GeziYemekItem> yemekSecimler;

  void dispose() {
    city.dispose();
    days.dispose();
  }
}
