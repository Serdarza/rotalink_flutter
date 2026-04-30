import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import '../constants/firebase_config.dart';
import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
import '../models/sosyal_item.dart';

/// Kotlin `FirebaseRotaRepository` ile aynı kök dinleyici ve yollar.
class RotaDataState {
  const RotaDataState({
    this.misafirhaneler = const [],
    this.aramaIcinTumTesisler = const [],
    this.gezi = const [],
    this.yemek = const [],
    this.sosyal = const [],
    this.initialLoadCompleted = false,
    this.errorMessage,
  });

  final List<Misafirhane> misafirhaneler;
  final List<Misafirhane> aramaIcinTumTesisler;
  final List<GeziYemekItem> gezi;
  final List<GeziYemekItem> yemek;
  final List<SosyalItem> sosyal;
  final bool initialLoadCompleted;
  final String? errorMessage;
}

class FirebaseRotaRepository {
  FirebaseRotaRepository({FirebaseDatabase? database})
      : _db = database ??
            FirebaseDatabase.instanceFor(
              app: Firebase.app(),
              databaseURL: kFirebaseRtdbUrl,
            );

  final FirebaseDatabase _db;

  /// [Firebase.initializeApp] sonrası, **ilk [DatabaseReference] kullanımından önce** bir kez çağrılmalı.
  /// Disk önbelleği: uygulama yeniden açıldığında harita verisi ağ gelmeden yüklenebilir.
  static void configureOfflinePersistence() {
    if (kIsWeb) return;
    try {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: kFirebaseRtdbUrl,
      );
      db.setPersistenceEnabled(true);
      db.setPersistenceCacheSizeBytes(20 * 1024 * 1024);
    } catch (_) {}
  }

  /// Splash / açılışta bir kez; izin verilen yollardan ön yükleme yapar.
  Future<void> primeRootSnapshot() async {
    try {
      await _db.ref(pathTesisler).get();
    } catch (_) {}
  }

  static const String pathTesisler = 'tesisler';
  static const String pathTesislerLegacy = 'misafirhaneler';
  static const String pathGeziler = 'geziler';
  static const String pathYemekler = 'yemekler';
  static const String pathSosyal = 'sosyal';

  /// Kök yerine izin verilen 5 yolu ayrı ayrı dinler ve birleştirir.
  /// Kural: kök ".read": false olsa bile çalışır.
  Stream<RotaDataState> watchRoot() {
    final controller = StreamController<RotaDataState>.broadcast();

    dynamic valTesisler;
    dynamic valLegacy;
    dynamic valGeziler;
    dynamic valYemekler;
    dynamic valSosyal;
    var readyCount = 0;

    void emit() {
      if (readyCount < 5) return;
      try {
        controller.add(_mapSnapshotToState({
          pathTesisler: valTesisler,
          pathTesislerLegacy: valLegacy,
          pathGeziler: valGeziler,
          pathYemekler: valYemekler,
          pathSosyal: valSosyal,
        }));
      } catch (err) {
        controller.add(RotaDataState(
          initialLoadCompleted: true,
          errorMessage: kDebugMode ? err.toString() : 'Veri okunamadı.',
        ));
      }
    }

    void onError(Object err) {
      readyCount++;
      emit();
    }

    final s1 = _db.ref(pathTesisler).onValue.listen((e) {
      valTesisler = e.snapshot.value;
      if (readyCount < 1) readyCount++;
      emit();
    }, onError: onError);
    final s2 = _db.ref(pathTesislerLegacy).onValue.listen((e) {
      valLegacy = e.snapshot.value;
      if (readyCount < 2) readyCount++;
      emit();
    }, onError: onError);
    final s3 = _db.ref(pathGeziler).onValue.listen((e) {
      valGeziler = e.snapshot.value;
      if (readyCount < 3) readyCount++;
      emit();
    }, onError: onError);
    final s4 = _db.ref(pathYemekler).onValue.listen((e) {
      valYemekler = e.snapshot.value;
      if (readyCount < 4) readyCount++;
      emit();
    }, onError: onError);
    final s5 = _db.ref(pathSosyal).onValue.listen((e) {
      valSosyal = e.snapshot.value;
      if (readyCount < 5) readyCount++;
      emit();
    }, onError: onError);

    controller.onCancel = () {
      s1.cancel();
      s2.cancel();
      s3.cancel();
      s4.cancel();
      s5.cancel();
    };

    return controller.stream;
  }

  RotaDataState _mapSnapshotToState(dynamic root) {
    if (root is! Map) {
      return const RotaDataState(initialLoadCompleted: true);
    }
    final m = root.map((k, v) => MapEntry(k.toString(), v));
    final tesisFull = _loadTesisFull(m);
    // Aynı (il+isim) kombinasyonuna sahip tekrarlı kayıtları temizle;
    // koordinatı olan kayıt tercih edilir. Bu olmadan arama sonuçlarında
    // aynı key'e sahip birden fazla marker oluşur → Flutter "Duplicate keys" hatası.
    final deduplicated = _distinctByStableFacilityIdPreferCoords(tesisFull);
    final gezi = _parseGeziYemekList(m[pathGeziler]);
    final yemek = _parseGeziYemekList(m[pathYemekler]);
    final sosyal = _parseSosyalList(m[pathSosyal]);
    return RotaDataState(
      misafirhaneler: _distinctByIlPreferCoords(deduplicated),
      aramaIcinTumTesisler: deduplicated,
      gezi: gezi,
      yemek: yemek,
      sosyal: sosyal,
      initialLoadCompleted: true,
    );
  }

  List<SosyalItem> _parseSosyalList(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v.map(SosyalItem.tryParse).whereType<SosyalItem>().toList();
    }
    if (v is Map) {
      final entries = v.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key.toString()) ?? 1 << 30;
          final ib = int.tryParse(b.key.toString()) ?? 1 << 30;
          return ia.compareTo(ib);
        });
      return entries
          .map((e) => SosyalItem.tryParse(e.value))
          .whereType<SosyalItem>()
          .toList();
    }
    return [];
  }

  List<GeziYemekItem> _parseGeziYemekList(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v.map(GeziYemekItem.tryParse).whereType<GeziYemekItem>().toList();
    }
    if (v is Map) {
      final entries = v.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key.toString()) ?? 1 << 30;
          final ib = int.tryParse(b.key.toString()) ?? 1 << 30;
          return ia.compareTo(ib);
        });
      return entries
          .map((e) => GeziYemekItem.tryParse(e.value))
          .whereType<GeziYemekItem>()
          .toList();
    }
    return [];
  }

  /// `stableFacilityId` (il + isim) bazında tekrarları kaldır; koordinatı olan kayıt tercih edilir.
  List<Misafirhane> _distinctByStableFacilityIdPreferCoords(List<Misafirhane> full) {
    final seen = <String, Misafirhane>{};
    for (final t in full) {
      final k = t.stableFacilityId;
      final ex = seen[k];
      if (ex == null) {
        seen[k] = t;
        continue;
      }
      final exBad = ex.latitude == 0 || ex.longitude == 0;
      final tGood = t.latitude != 0 && t.longitude != 0;
      if (exBad && tGood) seen[k] = t;
    }
    return seen.values.toList();
  }

  /// Her il için tek temsilci; mümkünse koordinatı olan kayıt seçilir.
  List<Misafirhane> _distinctByIlPreferCoords(List<Misafirhane> full) {
    final byIl = <String, Misafirhane>{};
    for (final t in full) {
      final k = t.il.trim();
      if (k.isEmpty) continue;
      final ex = byIl[k];
      if (ex == null) {
        byIl[k] = t;
        continue;
      }
      final exBad = ex.latitude == 0 || ex.longitude == 0;
      final tGood = t.latitude != 0 && t.longitude != 0;
      if (exBad && tGood) {
        byIl[k] = t;
      }
    }
    return byIl.values.toList();
  }

  List<Misafirhane> _loadTesisFull(Map<String, dynamic> m) {
    final primary = _parseMisafirhaneList(m[pathTesisler]);
    if (primary.isNotEmpty) return primary;
    return _parseMisafirhaneList(m[pathTesislerLegacy]);
  }

  List<Misafirhane> _parseMisafirhaneList(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v.map(Misafirhane.tryParse).whereType<Misafirhane>().toList();
    }
    if (v is Map) {
      final entries = v.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key.toString()) ?? 1 << 30;
          final ib = int.tryParse(b.key.toString()) ?? 1 << 30;
          return ia.compareTo(ib);
        });
      return entries
          .map((e) => Misafirhane.tryParse(e.value))
          .whereType<Misafirhane>()
          .toList();
    }
    return [];
  }
}
