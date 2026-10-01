import 'package:flutter/foundation.dart';

import '../constants/tr_il_ilce.dart';

/// Arama sorgusunun çözüldüğü konum: yalnız il veya il + ilçe.
@immutable
class IlIlceMatch {
  const IlIlceMatch(this.il, [this.ilce]);

  final String il;
  final String? ilce;

  @override
  bool operator ==(Object other) =>
      other is IlIlceMatch && other.il == il && other.ilce == ilce;

  @override
  int get hashCode => Object.hash(il, ilce);

  @override
  String toString() => IlIlce.label(il, ilce ?? '');
}

/// İl / ilçe adlarını [kTrIlIlceleri] referansına göre standartlaştırır ve
/// Türkçe karakter / büyük-küçük harf duyarsız eşleştirir.
abstract final class IlIlce {
  static const merkez = 'Merkez';

  /// "İSTANBUL", "istanbul", "İstanbul" → "istanbul"; boşluk ve noktalama atılır.
  static String key(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      final m = _fold[c];
      if (m != null) {
        b.write(m);
        continue;
      }
      final low = c.toLowerCase();
      final u = low.codeUnitAt(0);
      if ((u >= 0x61 && u <= 0x7a) || (u >= 0x30 && u <= 0x39)) b.write(low);
    }
    return b.toString();
  }

  static const _fold = <String, String>{
    'ç': 'c', 'Ç': 'c', 'ğ': 'g', 'Ğ': 'g', 'ı': 'i', 'I': 'i', 'İ': 'i',
    'ö': 'o', 'Ö': 'o', 'ş': 's', 'Ş': 's', 'ü': 'u', 'Ü': 'u',
    'â': 'a', 'Â': 'a', 'î': 'i', 'Î': 'i', 'û': 'u', 'Û': 'u',
  };

  static final Map<String, String> _ilByKey = {
    for (final il in kTrIlIlceleri.keys) key(il): il,
  };

  static final Map<String, Map<String, String>> _ilceByKey = {
    for (final e in kTrIlIlceleri.entries)
      e.key: {for (final d in e.value) key(d): d},
  };

  /// Referanstaki il adı; bulunamazsa null.
  static String? canonicalIl(String raw) => _ilByKey[key(raw)];

  /// İlin resmi ilçeleri (alfabetik); il bilinmiyorsa boş.
  static List<String> ilceleri(String il) {
    final c = canonicalIl(il);
    return c == null ? const [] : kTrIlIlceleri[c]!;
  }

  static bool sameIl(String a, String b) => key(a) == key(b);

  /// Ham ilçe değerini standart ada çevirir; referansta yoksa boş döner.
  /// "Çanakkale Merkez", "Çanakkale" ve "merkez" → "Merkez" (yalnız merkez
  /// ilçesi olan illerde).
  static String canonicalIlce(String il, String raw) {
    final cIl = canonicalIl(il);
    if (cIl == null) return '';
    final k = key(raw);
    if (k.isEmpty) return '';
    final byKey = _ilceByKey[cIl]!;
    final hit = byKey[k];
    if (hit != null) return hit;
    final ilK = key(cIl);
    if (byKey.containsKey(key(merkez)) &&
        (k == ilK || k == '${ilK}merkez' || k == 'merkez')) {
      return merkez;
    }
    return '';
  }

  /// Kart ve sonuç başlığı: "İstanbul / Sarıyer"; ilçe yoksa yalnız il.
  static String label(String il, String ilce) {
    final i = il.trim();
    final d = ilce.trim();
    if (d.isEmpty) return i;
    if (i.isEmpty) return d;
    return '$i / $d';
  }

  /// Sorgu bir il, "il ilçe" / "ilçe il" ya da yalnız ilçe adıysa eşleşmeleri
  /// döner. Yalnız ilçe adı birden çok ilde varsa hepsi döner; "Merkez" tek
  /// başına ilçe sayılmaz. [iller] verideki iller (yalnız bunlar aranır).
  static List<IlIlceMatch> matchQuery(String query, Iterable<String> iller) {
    final q = key(query);
    if (q.isEmpty) return const [];
    final ilsInData = <String>[
      for (final il in iller)
        if (canonicalIl(il) != null) canonicalIl(il)!,
    ];
    for (final il in ilsInData) {
      if (key(il) == q) return [IlIlceMatch(il)];
    }
    final out = <IlIlceMatch>[];
    for (final il in ilsInData.toSet()) {
      final ilK = key(il);
      for (final e in _ilceByKey[il]!.entries) {
        if (q == '$ilK${e.key}' || q == '${e.key}$ilK') {
          return [IlIlceMatch(il, e.value)];
        }
        if (q == e.key && e.value != merkez) out.add(IlIlceMatch(il, e.value));
      }
    }
    return out;
  }

  /// Arama çubuğu önerileri: önce iller, sonra "İl / İlçe" seçenekleri.
  static List<String> autocomplete(
    List<String> sortedIller,
    String rawQuery, {
    int limit = 8,
  }) {
    final q = key(rawQuery);
    if (q.isEmpty) return const [];
    final out = <String>[];
    for (final il in sortedIller) {
      if (key(il).startsWith(q)) out.add(il);
    }
    if (out.isEmpty && q.length >= 2) {
      for (final il in sortedIller) {
        if (key(il).contains(q)) out.add(il);
      }
    }
    final districts = <String>[];
    for (final il in sortedIller) {
      final cIl = canonicalIl(il);
      if (cIl == null) continue;
      final ilK = key(cIl);
      for (final e in _ilceByKey[cIl]!.entries) {
        final byName = q.length >= 3 && e.value != merkez && e.key.startsWith(q);
        final byIl = q.length > ilK.length && '$ilK${e.key}'.startsWith(q);
        if (byName || byIl) districts.add(label(il, e.value));
      }
    }
    districts.sort((a, b) => key(a).compareTo(key(b)));
    out.addAll(districts);
    return out.length > limit ? out.sublist(0, limit) : out;
  }
}
