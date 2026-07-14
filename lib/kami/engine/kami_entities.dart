/// Tesis türü (kamu konaklama alt kategorileri).
enum KamiFacilityKind {
  orduevi,
  ogretmenevi,
  polisevi,
  misafirhane,
}

extension KamiFacilityKindX on KamiFacilityKind {
  String get key {
    switch (this) {
      case KamiFacilityKind.orduevi:
        return 'orduevi';
      case KamiFacilityKind.ogretmenevi:
        return 'ogretmenevi';
      case KamiFacilityKind.polisevi:
        return 'polisevi';
      case KamiFacilityKind.misafirhane:
        return 'misafirhane';
    }
  }

  String get label {
    switch (this) {
      case KamiFacilityKind.orduevi:
        return 'Orduevi';
      case KamiFacilityKind.ogretmenevi:
        return 'Öğretmenevi';
      case KamiFacilityKind.polisevi:
        return 'Polisevi';
      case KamiFacilityKind.misafirhane:
        return 'Misafirhane';
    }
  }

  /// Tip + isim alanında aranacak anahtarlar.
  List<String> get matchKeys {
    switch (this) {
      case KamiFacilityKind.orduevi:
        return const ['orduevi'];
      case KamiFacilityKind.ogretmenevi:
        return const ['ogretmenevi', 'ogretmen'];
      case KamiFacilityKind.polisevi:
        return const ['polisevi'];
      case KamiFacilityKind.misafirhane:
        return const ['misafirhane', 'misafir'];
    }
  }
}

/// Metinden çıkarılan varlıklar.
class KamiEntities {
  const KamiEntities({
    this.cities = const [],
    this.fromCity,
    this.toCity,
    this.district,
    this.facilityKind,
    this.nameQuery = '',
    this.nearby = false,
    this.nearestOnly = false,
    this.wantsFood = false,
    this.wantsTourism = false,
    this.wantsMunicipal = false,
    this.wantsAccommodation = false,
    this.wantsRoute = false,
    this.wantsBreakfast = false,
    this.wantsScenic = false,
    this.wantsFavorites = false,
    this.wantsHistory = false,
    this.rawText = '',
  });

  final List<String> cities;
  final String? fromCity;
  final String? toCity;
  final String? district;
  final KamiFacilityKind? facilityKind;

  /// Tür/il çıkarıldıktan sonra kalan isim sorgusu (ör. "Kalender").
  final String nameQuery;
  final bool nearby;
  final bool nearestOnly;
  final bool wantsFood;
  final bool wantsTourism;
  final bool wantsMunicipal;
  final bool wantsAccommodation;
  final bool wantsRoute;
  final bool wantsBreakfast;
  final bool wantsScenic;
  final bool wantsFavorites;
  final bool wantsHistory;
  final String rawText;

  String? get primaryCity => cities.isNotEmpty ? cities.first : null;

  bool get hasNameQuery => nameQuery.trim().isNotEmpty;
  bool get hasRouteCities =>
      fromCity != null &&
      fromCity!.trim().isNotEmpty &&
      toCity != null &&
      toCity!.trim().isNotEmpty;
}
