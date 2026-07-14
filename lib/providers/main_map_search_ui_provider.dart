import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Arama çubuğu odakta mı (kullanıcı tıkladı / yazıyor).
final searchBarFocusedProvider = StateProvider<bool>((ref) => false);

/// Alt sekmeli arama paneli açık mı ([isPanelUp]).
final searchPanelOpenProvider = StateProvider<bool>((ref) => false);

/// Arama çubuğu + filtre chip bloğu toolbar altında sabit kalır (konum değişmez).
final isMapSearchChromeActiveProvider = Provider<bool>((ref) {
  return ref.watch(searchBarFocusedProvider) || ref.watch(searchPanelOpenProvider);
});

/// Harita üzerindeki yuvarlak butonlar (FAB, KAMİ, ACİL vb.) gizlensin mi.
final shouldHideMapOverlayButtonsProvider = Provider<bool>((ref) {
  return ref.watch(isMapSearchChromeActiveProvider);
});
