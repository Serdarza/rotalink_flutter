import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import '../../models/gezi_yemek_item.dart';
import '../../models/misafirhane.dart';
import '../../models/sosyal_item.dart';
import '../recommendation/trip_score_service.dart';
import 'kami_entities.dart';

/// KAMİ niyet türleri — yerel motor + ileride Gemini mapping için ortak.
enum KamiIntentType {
  weekendTrip,
  food,
  route,
  accommodation,
  cityOverview,
  nearbyMunicipal,
  nearbyFacilities,
  nearbyExplore,
  sightseeing,
  facilitySearch,
  databaseSearch,
  help,
  unknown,
}

/// Algılanmış niyet + çıkarılmış slotlar / varlıklar.
class DetectedIntent {
  const DetectedIntent({
    required this.type,
    this.city,
    this.fromCity,
    this.toCity,
    this.confidence = 0,
    this.rawText = '',
    this.entities,
  });

  final KamiIntentType type;
  final String? city;
  final String? fromCity;
  final String? toCity;
  final double confidence;
  final String rawText;
  final KamiEntities? entities;

  bool get hasCity => city != null && city!.trim().isNotEmpty;
  bool get hasRouteCities =>
      fromCity != null &&
      fromCity!.trim().isNotEmpty &&
      toCity != null &&
      toCity!.trim().isNotEmpty;
}

/// Motor çalışma bağlamı — yalnızca uygulama verisi + konum.
class KamiQueryContext {
  const KamiQueryContext({
    required this.data,
    this.userLocation,
    this.locationGranted = false,
  });

  final RotaDataState data;
  final LatLng? userLocation;
  final bool locationGranted;
}

/// Servislerin ortak çıktı birimi — uydurma yok, yalnız DB kayıtları.
class KamiPayload {
  const KamiPayload({
    required this.intent,
    this.title = '',
    this.subtitle = '',
    this.cities = const [],
    this.facilities = const [],
    this.gezi = const [],
    this.yemek = const [],
    this.sosyal = const [],
    this.routeSections = const [],
    this.cityScores = const [],
    this.userLocation,
    this.needsLocation = false,
    this.needsClarification = false,
    this.clarificationHint = '',
    this.emptyReason = '',
  });

  final KamiIntentType intent;
  final String title;
  final String subtitle;
  final List<String> cities;
  final List<Misafirhane> facilities;
  final List<GeziYemekItem> gezi;
  final List<GeziYemekItem> yemek;
  final List<SosyalItem> sosyal;
  final List<KamiRouteSection> routeSections;

  /// Akıllı hafta sonu önerileri (puanlı iller).
  final List<KamiCityScore> cityScores;

  /// Mesafe hesabı için (yakındaki tesisler vb.).
  final LatLng? userLocation;
  final bool needsLocation;
  final bool needsClarification;
  final String clarificationHint;
  final String emptyReason;

  bool get isEmpty =>
      facilities.isEmpty &&
      gezi.isEmpty &&
      yemek.isEmpty &&
      sosyal.isEmpty &&
      routeSections.isEmpty &&
      cityScores.isEmpty &&
      !needsLocation &&
      !needsClarification;
}

/// Rota cevabında bir il bloğu.
class KamiRouteSection {
  const KamiRouteSection({
    required this.city,
    required this.roleLabel,
    this.facilities = const [],
    this.gezi = const [],
    this.yemek = const [],
    this.sosyal = const [],
  });

  final String city;
  final String roleLabel;
  final List<Misafirhane> facilities;
  final List<GeziYemekItem> gezi;
  final List<GeziYemekItem> yemek;
  final List<SosyalItem> sosyal;
}
