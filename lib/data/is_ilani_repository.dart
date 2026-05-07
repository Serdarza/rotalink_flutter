import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../constants/firebase_config.dart';
import '../models/is_ilani.dart';

/// Firebase Realtime Database `is_ilanlari` düğümünden iş ilanlarını dinler.
class IsIlaniRepository {
  IsIlaniRepository({FirebaseDatabase? database})
      : _db = database ??
            FirebaseDatabase.instanceFor(
              app: Firebase.app(),
              databaseURL: kFirebaseRtdbUrl,
            );

  final FirebaseDatabase _db;

  static const String _pathIsIlanlari = 'is_ilanlari';

  // -------------------------------------------------------------------------
  // Tarih parse — "20 Nisan - 4 Mayıs" gibi Türkçe aralık formatı
  // -------------------------------------------------------------------------

  static const Map<String, int> _aylar = {
    'ocak': 1,
    'şubat': 2,
    'mart': 3,
    'nisan': 4,
    'mayıs': 5,
    'haziran': 6,
    'temmuz': 7,
    'ağustos': 8,
    'eylül': 9,
    'ekim': 10,
    'kasım': 11,
    'aralık': 12,
  };

  /// "20 Nisan - 4 Mayıs" → bitiş tarihi olan `DateTime(yıl, 5, 4)`.
  ///
  /// Aralık varsa ( " - " veya " – " ) sağ taraf; tek tarihse tek parça kullanılır.
  /// Yıl varsa ("4 Mayıs 2026") o yıl, yoksa mevcut yıl alınır.
  /// Parse başarısız olursa `null` döner — ilan listeye dahil edilir (güvenli hata payı).
  static DateTime? _parseBitisTarihi(String tarih) {
    try {
      final bolunmus = tarih.split(RegExp(r'\s*[–-]\s*'));
      final sonParca = bolunmus.last.trim();

      final tokenler = sonParca.split(RegExp(r'\s+'));
      if (tokenler.length < 2) return null;

      final gun = int.tryParse(tokenler[0]);
      final ay = _aylar[tokenler[1].toLowerCase()];
      if (gun == null || ay == null) return null;

      final yil = tokenler.length >= 3
          ? (int.tryParse(tokenler[2]) ?? DateTime.now().year)
          : DateTime.now().year;

      return DateTime(yil, ay, gun);
    } catch (_) {
      return null;
    }
  }

  /// "20 Nisan - 4 Mayıs" → başlangıç tarihi olan `DateTime(yıl, 4, 20)`.
  ///
  /// Aralık varsa sol taraf; tek tarihse tek parça kullanılır.
  /// Sıralama için kullanılır — parse başarısız olursa `null` döner.
  static DateTime? _parseBaslangicTarihi(String tarih) {
    try {
      final bolunmus = tarih.split(RegExp(r'\s*[–-]\s*'));
      final ilkParca = bolunmus.first.trim();

      final tokenler = ilkParca.split(RegExp(r'\s+'));
      if (tokenler.length < 2) return null;

      final gun = int.tryParse(tokenler[0]);
      final ay = _aylar[tokenler[1].toLowerCase()];
      if (gun == null || ay == null) return null;

      final yil = tokenler.length >= 3
          ? (int.tryParse(tokenler[2]) ?? DateTime.now().year)
          : DateTime.now().year;

      return DateTime(yil, ay, gun);
    } catch (_) {
      return null;
    }
  }

  /// İlan bugün veya gelecekte bitiyor mu?
  /// Bitiş tarihi parse edilemezse `true` döner (ilanı listede tut).
  static bool _aktifMi(IsIlani ilan) {
    if (ilan.tarih.isEmpty) return true;
    final bitis = _parseBitisTarihi(ilan.tarih);
    if (bitis == null) return true;
    final bugun = DateTime.now();
    final bugunSadece = DateTime(bugun.year, bugun.month, bugun.day);
    return !bugunSadece.isAfter(bitis);
  }

  /// Listeyi başlangıç tarihine göre yeniden eskiye sıralar.
  ///
  /// - Tarihi parse edilebilen ilanlar başa gelir (yeniden eskiye).
  /// - Tarihi parse edilemeyen ilanlar listenin sonuna düşer;
  ///   kendi aralarındaki sıra (ters-anahtar sırası) korunur.
  static List<IsIlani> _sortNewestFirst(List<IsIlani> liste) {
    liste.sort((a, b) {
      final da = _parseBaslangicTarihi(a.tarih);
      final db = _parseBaslangicTarihi(b.tarih);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da); // azalan: yeni → eski
    });
    return liste;
  }

  // -------------------------------------------------------------------------
  // Stream
  // -------------------------------------------------------------------------

  /// `is_ilanlari` düğümünü gerçek zamanlı dinleyen stream.
  /// Veri yoksa boş liste döner; map/list formatını her ikisini de destekler.
  /// Bitiş tarihi geçmiş ilanlar filtrelenir; kalanlar yeniden eskiye sıralanır.
  Stream<List<IsIlani>> watchIlanlar() {
    return _db.ref(_pathIsIlanlari).onValue.map((DatabaseEvent event) {
      final raw = event.snapshot.value;
      if (raw == null) return const <IsIlani>[];

      List<IsIlani> filterValid(Iterable<IsIlani?> items) => items
          .whereType<IsIlani>()
          .where((i) => i.kurum.isNotEmpty || i.pozisyon.isNotEmpty)
          .where(_aktifMi)
          .toList();

      if (raw is List) {
        // Listeyi tersine çevir (ters-giriş-sırası = fallback eski→yeni→ters)
        final parsed = filterValid(raw.reversed.map(IsIlani.tryParse));
        return _sortNewestFirst(parsed);
      }

      if (raw is Map) {
        // Anahtarları büyükten küçüğe sırala → ters-anahtar = fallback sırası
        final entries = (raw as Map<Object?, Object?>).entries.toList()
          ..sort((a, b) {
            final ia = int.tryParse(a.key.toString()) ?? -1;
            final ib = int.tryParse(b.key.toString()) ?? -1;
            return ib.compareTo(ia); // azalan anahtar sırası
          });
        final parsed = filterValid(entries.map((e) => IsIlani.tryParse(e.value)));
        return _sortNewestFirst(parsed);
      }

      return const <IsIlani>[];
    });
  }
}
