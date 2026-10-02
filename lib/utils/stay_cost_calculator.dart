import '../models/facility_tariff.dart';

/// Tarifedeki fiyatın neye göre alındığı.
enum StayPriceBasis { perPerson, perRoom }

/// Hesaplayıcıda seçilebilen bir konaklama tipi (tarife satırı).
class StayRoomOption {
  const StayRoomOption({
    required this.table,
    required this.row,
    required this.amount,
  });

  final TariffTable table;
  final TariffRow row;

  /// Seçili fiyat grubunda bir gecelik tutar (TL).
  final double amount;

  String get label {
    final t = table.baslik;
    return t == null ? row.ad : '${row.ad} · $t';
  }
}

/// Toplam konaklama ücreti için kullanıcı seçimleri.
class StayCostInput {
  const StayCostInput({
    required this.nightlyAmount,
    required this.basis,
    required this.nights,
    required this.adults,
    this.children = 0,
    this.childFactor = 1,
    this.rooms = 1,
    this.extraBeds = 0,
    this.extraBedAmount,
    this.breakfastPerPerson,
    this.taxRate = 0,
  });

  final double nightlyAmount;
  final StayPriceBasis basis;
  final int nights;
  final int adults;
  final int children;

  /// Çocuk başına konaklama ücreti oranı: 0 ücretsiz, 0.5 yarım, 1 tam.
  final double childFactor;
  final int rooms;
  final int extraBeds;
  final double? extraBedAmount;

  /// Kişi başı günlük kahvaltı; null → eklenmez.
  final double? breakfastPerPerson;

  /// Konaklama vergisi oranı (ör. 0.02); 0 → eklenmez.
  final double taxRate;
}

class StayCostBreakdown {
  const StayCostBreakdown({
    required this.lodging,
    required this.extraBeds,
    required this.breakfast,
    required this.tax,
  });

  final double lodging;
  final double extraBeds;
  final double breakfast;
  final double tax;

  double get total => lodging + extraBeds + breakfast + tax;
}

/// Tarife verisinden (uydurmadan) toplam konaklama ücreti hesaplar.
abstract final class StayCostCalculator {
  static final _extraBed = RegExp(r'ek\s*yatak', caseSensitive: false);
  static final _breakfast = RegExp(r'kahvalt', caseSensitive: false);
  static final _monthly = RegExp(r'ayl[ıi]k', caseSensitive: false);
  static final _child = RegExp(r'çocuk|cocuk|yaş|yas\b', caseSensitive: false);
  static final _perPerson = RegExp(
    r'kişi\s*ba|kisi\s*ba|kişi$|kisi$|tl/kişi|yatak',
    caseSensitive: false,
  );
  static final _perRoom = RegExp(r'\boda\b', caseSensitive: false);
  static final _roomName = RegExp(
    r'(iki|üç|dört|beş|\d)\s*kişilik|aile|suit|süit|double|duble|oda fiyat',
    caseSensitive: false,
  );
  static final _lodgingTax = RegExp(r'konaklama\s*vergisi', caseSensitive: false);
  static final _percent = RegExp(r'%\s*(\d+(?:[.,]\d+)?)');

  static bool _isExtraBed(TariffRow r) =>
      _extraBed.hasMatch(r.ad) && !_roomName.hasMatch(r.ad);

  static bool _isBreakfastRow(TariffRow r) =>
      _breakfast.hasMatch(r.ad) && !r.ad.toLowerCase().contains('dahil');

  static bool _isMonthly(TariffRow r, TariffTable t) =>
      _monthly.hasMatch('${r.birim ?? ''} ${t.birim ?? ''} ${r.ad}');

  static bool _isRoomRow(TariffRow r, TariffTable t) =>
      !_isExtraBed(r) && !_isBreakfastRow(r) && !_isMonthly(r, t);

  /// Konaklama satırlarında sayısal fiyatı olan fiyat grupları.
  static List<TariffCategory> categories(FacilityTariff tariff) {
    final out = <TariffCategory>[];
    for (final t in tariff.tablolar) {
      for (final c in t.kategoriler) {
        if (out.any((e) => e.id == c.id)) continue;
        final priced = t.satirlar.any(
          (r) => _isRoomRow(r, t) && r.fiyatlar[c.id]?.amount != null,
        );
        if (priced) out.add(c);
      }
    }
    return out;
  }

  static bool isAvailable(FacilityTariff? tariff) =>
      tariff != null && categories(tariff).isNotEmpty;

  static List<StayRoomOption> roomOptions(FacilityTariff tariff, String catId) => [
        for (final t in tariff.tablolar)
          for (final r in t.satirlar)
            if (_isRoomRow(r, t) && r.fiyatlar[catId]?.amount != null)
              StayRoomOption(table: t, row: r, amount: r.fiyatlar[catId]!.amount!),
      ];

  static double? _firstAmount(
    FacilityTariff tariff,
    String catId,
    bool Function(TariffRow) test,
  ) {
    for (final t in tariff.tablolar) {
      for (final r in t.satirlar) {
        final v = r.fiyatlar[catId]?.amount;
        if (test(r) && v != null) return v;
      }
    }
    return null;
  }

  static double? extraBedAmount(FacilityTariff tariff, String catId) =>
      _firstAmount(tariff, catId, _isExtraBed);

  static double? breakfastAmount(FacilityTariff tariff, String catId) =>
      _firstAmount(tariff, catId, _isBreakfastRow);

  /// Fiyat birimi ve tarifede açıkça yazıp yazmadığı.
  static ({StayPriceBasis basis, bool explicit}) inferBasis(
    FacilityTariff tariff,
    StayRoomOption option,
  ) {
    for (final unit in [option.row.birim, option.table.birim, tariff.birim]) {
      if (unit == null) continue;
      if (_perPerson.hasMatch(unit)) {
        return (basis: StayPriceBasis.perPerson, explicit: true);
      }
      if (_perRoom.hasMatch(unit)) {
        return (basis: StayPriceBasis.perRoom, explicit: true);
      }
    }
    if (tariff.kurallar.any((k) => RegExp(r'kişi başı ücret', caseSensitive: false).hasMatch(k))) {
      return (basis: StayPriceBasis.perPerson, explicit: true);
    }
    final ad = option.row.ad;
    if (RegExp(r'kişi\s*başı', caseSensitive: false).hasMatch(ad)) {
      return (basis: StayPriceBasis.perPerson, explicit: true);
    }
    if (_roomName.hasMatch(ad) || (option.row.kisi ?? 1) > 1) {
      return (basis: StayPriceBasis.perRoom, explicit: false);
    }
    return (basis: StayPriceBasis.perPerson, explicit: false);
  }

  /// Tarifede kahvaltının fiyata dahil olduğu açıkça yazıyorsa true, dahil değilse false.
  static bool? breakfastIncluded(FacilityTariff tariff, StayRoomOption? option) {
    final ad = option?.row.ad.toLowerCase() ?? '';
    if (ad.contains('kahvaltı dahil') || ad.contains('kahvaltılı')) return true;
    if (tariff.dahil.any(_breakfast.hasMatch)) return true;
    for (final s in [...tariff.notlar, ...tariff.ekUcretler, ...tariff.kurallar]) {
      final l = s.toLowerCase();
      if (!_breakfast.hasMatch(l)) continue;
      if (l.contains('dahil değil') || l.contains('dâhil değil')) return false;
      if (l.contains('dahil')) return true;
    }
    return null;
  }

  /// Kahvaltı ücretine dair tarifedeki metinler (dahil listesi hariç).
  static List<String> breakfastNotes(FacilityTariff tariff) => [
        for (final s in [...tariff.ekUcretler, ...tariff.notlar, ...tariff.kurallar])
          if (_breakfast.hasMatch(s)) s,
      ];

  /// Çocuk indirimine dair tarifedeki metinler.
  static List<String> childNotes(FacilityTariff tariff) => [
        for (final s in [...tariff.indirimler, ...tariff.kurallar, ...tariff.notlar])
          if (_child.hasMatch(s)) s,
      ];

  /// Ek ücret olarak yazılmış konaklama vergisi oranı; dahilse veya yoksa null.
  static double? lodgingTaxRate(FacilityTariff tariff) {
    if (tariff.dahil.any(_lodgingTax.hasMatch)) return null;
    for (final s in [...tariff.ekUcretler, ...tariff.kurallar, ...tariff.notlar]) {
      if (!_lodgingTax.hasMatch(s)) continue;
      final m = _percent.firstMatch(s);
      if (m == null) continue;
      final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
      if (v != null && v > 0 && v < 20) return v / 100;
    }
    return null;
  }

  /// Oda başı fiyatta kişi sayısına göre gereken oda sayısı (kapasite biliniyorsa).
  static int suggestedRooms(StayRoomOption option, int people) {
    final cap = option.row.kisi;
    if (cap == null || cap <= 0) return 1;
    return ((people + cap - 1) ~/ cap).clamp(1, 20);
  }

  static StayCostBreakdown compute(StayCostInput i) {
    final nights = i.nights.clamp(1, 365);
    final payingGuests = i.adults + i.children * i.childFactor;
    final lodging = switch (i.basis) {
      StayPriceBasis.perPerson => i.nightlyAmount * nights * payingGuests,
      StayPriceBasis.perRoom => i.nightlyAmount * nights * i.rooms,
    };
    final extraBeds = (i.extraBedAmount ?? 0) * i.extraBeds * nights;
    final breakfast =
        (i.breakfastPerPerson ?? 0) * nights * (i.adults + i.children);
    final tax = (lodging + extraBeds) * i.taxRate;
    return StayCostBreakdown(
      lodging: lodging,
      extraBeds: extraBeds,
      breakfast: breakfast,
      tax: tax,
    );
  }
}
