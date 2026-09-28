import 'package:flutter/foundation.dart';

import '../models/misafirhane.dart';

/// Pro: karşılaştırma için seçilen tesisler (uygulama oturumu boyunca).
class FacilityCompareSelection extends ValueNotifier<List<Misafirhane>> {
  FacilityCompareSelection._() : super(const []);

  static final instance = FacilityCompareSelection._();

  static const maxItems = 3;

  bool contains(Misafirhane m) => value.any((x) => x.sameFavoriteIdentity(m));

  bool get isFull => value.length >= maxItems;

  /// Ekler veya çıkarır; liste doluysa ekleme yapılmaz ve false döner.
  bool toggle(Misafirhane m) {
    if (contains(m)) {
      remove(m);
      return true;
    }
    if (isFull) return false;
    value = [...value, m];
    return true;
  }

  void remove(Misafirhane m) {
    value = value.where((x) => !x.sameFavoriteIdentity(m)).toList();
  }

  void clear() => value = const [];
}
