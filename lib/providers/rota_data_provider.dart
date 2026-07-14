import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firebase_rota_repository.dart';

/// GitHub / yerel önbellekten gelen güncel rota verisi (tesisler, gezi, yemek, sosyal).
///
/// [MainMapScreen] StreamBuilder veriyi aldığında bu provider güncellenir;
/// filtreleme provider'ları ([filteredFacilitiesProvider] vb.) aynı kalır.
final rotaDataStateProvider = StateProvider<RotaDataState?>(
  (ref) => null,
);
