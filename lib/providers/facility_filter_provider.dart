import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/facility_address_repository.dart';
import '../models/misafirhane.dart';
import '../utils/il_ilce.dart';
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

/// Seçili ilçe; hangi ile ait olduğu da tutulur.
@immutable
class IlceSelection {
  const IlceSelection({required this.il, required this.ilce});

  final String il;
  final String ilce;

  @override
  bool operator ==(Object other) =>
      other is IlceSelection && other.il == il && other.ilce == ilce;

  @override
  int get hashCode => Object.hash(il, ilce);
}

/// Aktif ilçe filtresi; null → tüm ilçeler. Arama paneli kapanınca sıfırlanır.
final facilityIlceFilterProvider = StateProvider<IlceSelection?>((ref) => null);

String _ilceOf(Misafirhane m) => FacilityAddressRepository.instance.ilceOf(m);

/// [selection] listedeki ile aitse o ilçeye süzer. Liste başka bir ile aitse
/// (il değişti) seçim yok sayılır; eski ilçe yeni sonuçları süzemez.
List<Misafirhane> filterFacilitiesByIlce(
  List<Misafirhane> facilities,
  IlceSelection? selection, {
  String Function(Misafirhane m) ilceOf = _ilceOf,
}) {
  if (selection == null) return facilities;
  if (!facilities.any((m) => IlIlce.sameIl(m.il, selection.il))) {
    return facilities;
  }
  return facilities
      .where((m) =>
          IlIlce.sameIl(m.il, selection.il) && ilceOf(m) == selection.ilce)
      .toList(growable: false);
}

/// Harita ve liste için ortak süzgeç: tesis türü + ilçe.
List<Misafirhane> filterFacilities(
  List<Misafirhane> facilities,
  String typeFilter,
  IlceSelection? selection,
) =>
    filterFacilitiesByIlce(
      filterFacilitiesByType(facilities, typeFilter),
      selection,
    );

/// Kaynak listeyi tür + ilçe filtresiyle süzen Riverpod provider'ı.
final filteredFacilitiesProvider =
    Provider.family<List<Misafirhane>, List<Misafirhane>>((ref, source) {
  return filterFacilities(
    source,
    ref.watch(facilityTypeFilterProvider),
    ref.watch(facilityIlceFilterProvider),
  );
});

/// Arama panelinde gösterilecek ham (filtrelenmemiş) tesis listesi.
final searchPanelFacilitiesSourceProvider = StateProvider<List<Misafirhane>>(
  (ref) => const [],
);

/// Arama paneli tesis sekmesinin dinlediği filtrelenmiş liste.
final filteredTesisListProvider = Provider<List<Misafirhane>>((ref) {
  return filterFacilities(
    ref.watch(searchPanelFacilitiesSourceProvider),
    ref.watch(facilityTypeFilterProvider),
    ref.watch(facilityIlceFilterProvider),
  );
});

/// Sonuç panelindeki il / ilçe çubuğunun özeti (tür filtresi uygulanmış).
@immutable
class FacilityLocationSummary {
  const FacilityLocationSummary({
    required this.il,
    required this.ilceCounts,
    required this.total,
  });

  /// Sonuçların tamamı tek ildeyse o il; aksi halde null (ilçe seçimi kapalı).
  final String? il;

  /// İlin bütün resmi ilçeleri → tesis sayısı (0 olanlar dahil).
  final Map<String, int> ilceCounts;

  /// Tür filtresi sonrası ildeki tesis sayısı.
  final int total;
}

FacilityLocationSummary summarizeFacilityLocations(
  List<Misafirhane> typeFiltered,
  List<Misafirhane> source, {
  String Function(Misafirhane m) ilceOf = _ilceOf,
}) {
  String? il;
  for (final m in source) {
    final c = IlIlce.canonicalIl(m.il) ?? m.il.trim();
    if (il == null) {
      il = c;
    } else if (il != c) {
      il = null;
      break;
    }
  }
  if (il == null) {
    return FacilityLocationSummary(
      il: null,
      ilceCounts: const {},
      total: typeFiltered.length,
    );
  }
  final counts = <String, int>{for (final d in IlIlce.ilceleri(il)) d: 0};
  for (final m in typeFiltered) {
    final d = ilceOf(m);
    if (d.isNotEmpty) counts[d] = (counts[d] ?? 0) + 1;
  }
  return FacilityLocationSummary(
    il: il,
    ilceCounts: counts,
    total: typeFiltered.length,
  );
}

final searchPanelLocationSummaryProvider =
    Provider<FacilityLocationSummary>((ref) {
  final source = ref.watch(searchPanelFacilitiesSourceProvider);
  final typed = filterFacilitiesByType(
    source,
    ref.watch(facilityTypeFilterProvider),
  );
  return summarizeFacilityLocations(typed, source);
});
