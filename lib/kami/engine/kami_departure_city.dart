import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import '../recommendation/distance_service.dart';
import 'kami_models.dart';
import 'kami_system_instruction.dart';

/// Çıkış ili çözümü — sistem yönergesi kural 1.
abstract final class KamiDepartureCityResolver {
  static const String askMessage = KamiSystemInstruction.askDepartureCity;

  static String? resolve({
    String? cityFromIntent,
    String? cityFromGps,
  }) {
    final fromIntent = cityFromIntent?.trim();
    if (fromIntent != null && fromIntent.isNotEmpty) return fromIntent;
    final fromGps = cityFromGps?.trim();
    if (fromGps != null && fromGps.isNotEmpty) return fromGps;
    return null;
  }

  static String? fromLocation(LatLng? user, RotaDataState data) {
    if (user == null) return null;
    return KamiDistanceService.resolveHomeCity(user, data);
  }

  static KamiPayload clarificationPayload(KamiIntentType intent) {
    return KamiPayload(
      intent: intent,
      needsClarification: true,
      clarificationHint: askMessage,
    );
  }
}
