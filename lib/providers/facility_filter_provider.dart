import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/misafirhane.dart';
import '../utils/search_normalize.dart';

/// Sabit tesis tipi filtre seçenekleri (JSON'dan okunmaz).
const String kFacilityFilterAll = 'Tüm Tesisler';

const List<String> kFacilityTypeFilterOptions = <String>[
  kFacilityFilterAll,
  'Orduevi',
  'Polisevi',
  'Öğretmenevi',
];

/// Aktif tesis tipi filtresi. Varsayılan: tüm tesisler.
final facilityTypeFilterProvider = StateProvider<String>(
  (ref) => kFacilityFilterAll,
);

/// [tip] alanı seçilen filtre etiketiyle eşleşiyor mu?
bool facilityMatchesTypeFilter(String tip, String filter) {
  if (filter == kFacilityFilterAll) return true;
  final trimmed = tip.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed == filter) return true;
  return normalizeForSearch(trimmed) == normalizeForSearch(filter);
}

/// Verilen listeyi aktif filtreye göre süzer.
List<Misafirhane> filterFacilitiesByType(
  List<Misafirhane> facilities,
  String activeFilter,
) {
  if (activeFilter == kFacilityFilterAll) return facilities;
  return facilities
      .where((m) => facilityMatchesTypeFilter(m.tip, activeFilter))
      .toList(growable: false);
}

/// Kaynak listeyi [facilityTypeFilterProvider] ile süzen Riverpod provider'ı.
final filteredFacilitiesProvider =
    Provider.family<List<Misafirhane>, List<Misafirhane>>((ref, source) {
  final filter = ref.watch(facilityTypeFilterProvider);
  return filterFacilitiesByType(source, filter);
});

/// Arama panelinde gösterilecek ham (filtrelenmemiş) tesis listesi.
final searchPanelFacilitiesSourceProvider = StateProvider<List<Misafirhane>>(
  (ref) => const [],
);

/// Arama paneli tesis sekmesinin dinlediği filtrelenmiş liste.
final filteredTesisListProvider = Provider<List<Misafirhane>>((ref) {
  final source = ref.watch(searchPanelFacilitiesSourceProvider);
  final filter = ref.watch(facilityTypeFilterProvider);
  return filterFacilitiesByType(source, filter);
});
