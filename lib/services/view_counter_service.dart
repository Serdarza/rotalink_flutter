import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'review_repository.dart';

/// Görüntülenme sayacı kategorileri (Firestore belge kimliğinin ön eki).
enum ViewCategory { konaklama, kamp, gezi, yemek, hediyelik, sosyal }

/// Tüm kategoriler için ortak görüntülenme sayacı.
///
/// Firestore: `facilityViews/{kategori_il_ad}` → `count` (int).
/// Yeni paket / tablo yok; yorum sistemiyle aynı Firestore örneği kullanılır.
///
/// Aynı oturumda (uygulama açık kaldığı sürece) aynı kayıt yalnız bir kez
/// sayılır; detay sayfasını tekrar açmak veya yenilemek sayıyı artırmaz.
class ViewCounterService {
  ViewCounterService._();
  static final ViewCounterService instance = ViewCounterService._();

  static const String collection = 'facilityViews';

  final Set<String> _recordedThisSession = <String>{};
  final Map<String, int> _cache = <String, int>{};
  final Map<String, Future<int>> _inFlight = <String, Future<int>>{};

  /// Sayı değiştiğinde (bu oturumdaki yeni görüntülenme) artar; etiketler dinler.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(collection);

  /// Kategori + il + ad → kararlı belge kimliği. Boşsa boş döner.
  static String keyFor(ViewCategory category, String il, String name) {
    final n = name.trim();
    if (n.isEmpty) return '';
    final raw = '${il.trim()}\u0001$n';
    var id = ReviewRepository.sanitizeFacilityId(raw);
    if (id.length > 200) id = id.substring(0, 200);
    return '${category.name}_$id';
  }

  /// Önbellekteki sayı (yoksa null).
  int? cached(String id) => _cache[id];

  /// Gerçek bir detay ziyaretini kaydeder (oturum başına bir kez).
  Future<void> recordView(String id) async {
    if (id.isEmpty || !_recordedThisSession.add(id)) return;
    try {
      await _col.doc(id).set(<String, dynamic>{
        'count': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final known = _cache[id];
      if (known != null) {
        _cache[id] = known + 1;
      } else {
        _cache.remove(id);
        _inFlight.remove(id);
      }
      changes.value++;
    } catch (e) {
      // Yazılamadı (çevrimdışı / kural): sonraki ziyarette yeniden denensin.
      _recordedThisSession.remove(id);
      debugPrint('ViewCounter record: $e');
    }
  }

  /// Kaydın toplam görüntülenme sayısı (hata / kayıt yoksa 0).
  Future<int> countFor(String id) {
    if (id.isEmpty) return Future<int>.value(0);
    final hit = _cache[id];
    if (hit != null) return Future<int>.value(hit);
    return _inFlight[id] ??= _fetch(id);
  }

  Future<int> _fetch(String id) async {
    try {
      final snap = await _col.doc(id).get();
      final value = (snap.data()?['count'] as num?)?.toInt() ?? 0;
      final count = value < 0 ? 0 : value;
      _cache[id] = count;
      return count;
    } catch (e) {
      debugPrint('ViewCounter read: $e');
      return 0;
    } finally {
      _inFlight.remove(id);
    }
  }

  /// 1248 → "1.248" (Türkçe binlik ayracı).
  static String formatTr(int value) {
    final s = value.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return value < 0 ? '-$buf' : buf.toString();
  }
}
