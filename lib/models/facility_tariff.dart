/// `fiyatlar.json` kaydındaki isteğe bağlı `tarife` nesnesi.
///
/// Kurumdan kuruma değişen tarifeleri tek bir sabit tabloya zorlamadan taşır:
/// fiyat kategorileri (kolonlar) ve konaklama tipleri (satırlar) veriden gelir.
/// Hiçbir alan zorunlu değildir; eksik alanlar arayüzde gösterilmez.
class FacilityTariff {
  const FacilityTariff({
    this.baslik,
    this.birim,
    this.donem,
    this.guncelleme,
    this.dogrulama,
    this.tablolar = const [],
    this.kurallar = const [],
    this.dahil = const [],
    this.indirimler = const [],
    this.ekUcretler = const [],
    this.notlar = const [],
    this.girisSaati,
    this.cikisSaati,
  });

  final String? baslik;

  /// Varsayılan fiyat birimi (ör. "gecelik", "kişi başı / gece").
  final String? birim;

  /// Geçerlilik dönemi (ör. "2026", "01.06.2026 – 15.09.2026").
  final String? donem;

  /// Son güncelleme tarihi — `YYYY-MM-DD` veya serbest metin.
  final String? guncelleme;

  final TariffVerification? dogrulama;

  final List<TariffTable> tablolar;
  final List<String> kurallar;
  final List<String> dahil;
  final List<String> indirimler;
  final List<String> ekUcretler;
  final List<String> notlar;
  final String? girisSaati;
  final String? cikisSaati;

  bool get hasTables => tablolar.any((t) => t.satirlar.isNotEmpty);

  bool get hasContent =>
      hasTables ||
      kurallar.isNotEmpty ||
      dahil.isNotEmpty ||
      indirimler.isNotEmpty ||
      ekUcretler.isNotEmpty ||
      notlar.isNotEmpty;

  /// Eski `fiyat_*` alanları olmayan kayıtlar için kategori bazlı min–max özeti.
  List<({String label, double min, double max})> derivedRanges() {
    final order = <String>[];
    final labels = <String, String>{};
    final mins = <String, double>{};
    final maxs = <String, double>{};
    for (final table in tablolar) {
      for (final cat in table.kategoriler) {
        labels.putIfAbsent(cat.id, () => cat.ad);
        if (!order.contains(cat.id)) order.add(cat.id);
      }
      for (final row in table.satirlar) {
        row.fiyatlar.forEach((id, price) {
          final v = price.amount;
          if (v == null) return;
          mins[id] = mins[id] == null || v < mins[id]! ? v : mins[id]!;
          maxs[id] = maxs[id] == null || v > maxs[id]! ? v : maxs[id]!;
        });
      }
    }
    return [
      for (final id in order)
        if (mins[id] != null)
          (label: labels[id] ?? id, min: mins[id]!, max: maxs[id]!),
    ];
  }

  static FacilityTariff? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = _map(raw);
    final sharedCategories = TariffCategory.parseList(m['kategoriler']);
    final sharedUnit = _text(m['birim']);

    final tables = <TariffTable>[];
    final rawTables = m['tablolar'];
    if (rawTables is List) {
      for (final t in rawTables) {
        final table = TariffTable.tryParse(t, sharedCategories, sharedUnit);
        if (table != null) tables.add(table);
      }
    } else if (m['satirlar'] is List) {
      final table = TariffTable.tryParse(m, sharedCategories, sharedUnit);
      if (table != null) tables.add(table);
    }

    final tariff = FacilityTariff(
      baslik: _text(m['baslik']),
      birim: sharedUnit,
      donem: _text(m['donem']),
      guncelleme: _text(m['guncelleme']),
      dogrulama: TariffVerification.tryParse(m['dogrulama']),
      tablolar: List.unmodifiable(tables),
      kurallar: _texts(m['kurallar']),
      dahil: _texts(m['dahil']),
      indirimler: _texts(m['indirimler']),
      ekUcretler: _texts(m['ek_ucretler']),
      notlar: _texts(m['notlar']),
      girisSaati: _text(m['giris_saati']),
      cikisSaati: _text(m['cikis_saati']),
    );
    return tariff.hasContent ? tariff : null;
  }
}

/// Bir fiyat tablosu (ör. sezon, bina veya hafta içi/sonu bazında ayrı tablolar).
class TariffTable {
  const TariffTable({
    required this.kategoriler,
    required this.satirlar,
    this.baslik,
    this.donem,
    this.aciklama,
    this.birim,
  });

  final String? baslik;
  final String? donem;
  final String? aciklama;
  final String? birim;
  final List<TariffCategory> kategoriler;
  final List<TariffRow> satirlar;

  static TariffTable? tryParse(
    dynamic raw,
    List<TariffCategory> sharedCategories,
    String? sharedUnit,
  ) {
    if (raw is! Map) return null;
    final m = _map(raw);
    final own = TariffCategory.parseList(m['kategoriler']);
    final rows = <TariffRow>[];
    final rawRows = m['satirlar'];
    if (rawRows is List) {
      for (final r in rawRows) {
        final row = TariffRow.tryParse(r);
        if (row != null) rows.add(row);
      }
    }
    if (rows.isEmpty) return null;

    final categories = [...(own.isNotEmpty ? own : sharedCategories)];
    // Kategori listesinde tanımlanmamış ama satırda fiyatı olan anahtarlar da gösterilsin.
    for (final row in rows) {
      for (final id in row.fiyatlar.keys) {
        if (!categories.any((c) => c.id == id)) {
          categories.add(TariffCategory(id: id, ad: id));
        }
      }
    }
    return TariffTable(
      baslik: _text(m['baslik']),
      donem: _text(m['donem']),
      aciklama: _text(m['aciklama']),
      birim: _text(m['birim']) ?? sharedUnit,
      kategoriler: List.unmodifiable(categories),
      satirlar: List.unmodifiable(rows),
    );
  }
}

/// Fiyat kolonu: "Kamu", "Sivil", "Öğrenci", "Kişi başı" vb.
class TariffCategory {
  const TariffCategory({required this.id, required this.ad, this.aciklama});

  final String id;
  final String ad;
  final String? aciklama;

  static List<TariffCategory> parseList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <TariffCategory>[];
    for (final c in raw) {
      if (c is String && c.trim().isNotEmpty) {
        out.add(TariffCategory(id: c.trim(), ad: c.trim()));
      } else if (c is Map) {
        final m = _map(c);
        final ad = _text(m['ad']);
        final id = _text(m['id']) ?? ad;
        if (id != null) {
          out.add(TariffCategory(
            id: id,
            ad: ad ?? id,
            aciklama: _text(m['aciklama']),
          ));
        }
      }
    }
    return out;
  }
}

/// Konaklama tipi satırı: oda tipi, kişi sayısı ve kategori → fiyat eşlemesi.
class TariffRow {
  const TariffRow({
    required this.ad,
    required this.fiyatlar,
    this.kisi,
    this.birim,
    this.aciklama,
  });

  final String ad;
  final int? kisi;
  final String? birim;
  final String? aciklama;

  /// Kategori id → fiyat. Anahtar yoksa o kategori için fiyat belirtilmemiştir.
  final Map<String, TariffPrice> fiyatlar;

  static TariffRow? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = _map(raw);
    final ad = _text(m['ad']);
    if (ad == null) return null;
    final prices = <String, TariffPrice>{};
    final rawPrices = m['fiyatlar'];
    if (rawPrices is Map) {
      rawPrices.forEach((k, v) {
        final p = TariffPrice.tryParse(v);
        if (p != null) prices[k.toString()] = p;
      });
    }
    final kisi = m['kisi'];
    return TariffRow(
      ad: ad,
      kisi: kisi is num ? kisi.toInt() : int.tryParse('${kisi ?? ''}'),
      birim: _text(m['birim']),
      aciklama: _text(m['aciklama']),
      fiyatlar: Map.unmodifiable(prices),
    );
  }
}

/// Sayı → kesin tutar (TL); metin → olduğu gibi gösterilir ("Bilgi için arayınız").
class TariffPrice {
  const TariffPrice._({this.amount, this.text});

  final double? amount;
  final String? text;

  static TariffPrice? tryParse(dynamic raw) {
    if (raw is num) return TariffPrice._(amount: raw.toDouble());
    if (raw is Map) {
      final m = _map(raw);
      return tryParse(m['tutar'] ?? m['fiyat'] ?? m['metin']);
    }
    final s = _text(raw);
    if (s == null) return null;
    return TariffPrice._(text: s);
  }
}

enum TariffVerification {
  resmiKaynak('Resmî kaynaktan alındı'),
  tesisDogruladi('Tesis tarafından doğrulandı'),
  kullaniciBildirimi('Kullanıcı bildirimi'),
  teyitGerekli('Teyit gerekli');

  const TariffVerification(this.label);

  final String label;

  bool get isConfirmed =>
      this == TariffVerification.resmiKaynak ||
      this == TariffVerification.tesisDogruladi;

  static TariffVerification? tryParse(dynamic raw) => switch (_text(raw)) {
        'resmi_kaynak' => TariffVerification.resmiKaynak,
        'tesis_dogruladi' => TariffVerification.tesisDogruladi,
        'kullanici_bildirimi' => TariffVerification.kullaniciBildirimi,
        'teyit_gerekli' => TariffVerification.teyitGerekli,
        _ => null,
      };
}

Map<String, dynamic> _map(Map raw) =>
    raw.map((k, v) => MapEntry(k.toString(), v));

String? _text(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty || s.toLowerCase() == 'null') return null;
  return s;
}

List<String> _texts(dynamic v) {
  if (v is String) {
    final s = _text(v);
    return s == null ? const [] : [s];
  }
  if (v is! List) return const [];
  return List.unmodifiable(v.map(_text).whereType<String>());
}
