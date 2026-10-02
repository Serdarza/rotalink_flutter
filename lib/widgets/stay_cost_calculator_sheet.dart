import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/facility_pricing.dart';
import '../constants/store_links.dart';
import '../models/facility_tariff.dart';
import '../models/misafirhane.dart';
import '../theme/app_colors.dart';
import '../utils/stay_cost_calculator.dart';
import 'facility_tariff_view.dart' show formatTl;

/// Fiyatı açık (Pro) tesiste toplam konaklama ücreti hesaplayıcı.
Future<void> showStayCostCalculator(BuildContext context, Misafirhane priced) {
  final tariff = priced.fiyatKaydi?.tarife;
  if (!StayCostCalculator.isAvailable(tariff)) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, controller) => _StayCostCalculatorBody(
        facility: priced,
        tariff: tariff!,
        controller: controller,
      ),
    ),
  );
}

class _StayCostCalculatorBody extends StatefulWidget {
  const _StayCostCalculatorBody({
    required this.facility,
    required this.tariff,
    required this.controller,
  });

  final Misafirhane facility;
  final FacilityTariff tariff;
  final ScrollController controller;

  @override
  State<_StayCostCalculatorBody> createState() => _StayCostCalculatorBodyState();
}

class _StayCostCalculatorBodyState extends State<_StayCostCalculatorBody> {
  late final List<TariffCategory> _categories;
  late String _catId;
  List<StayRoomOption> _options = const [];
  int _optionIndex = 0;
  StayPriceBasis _basis = StayPriceBasis.perPerson;
  bool _basisExplicit = false;
  int _nights = 1;
  int _adults = 2;
  int _children = 0;
  double _childFactor = 1;
  int _rooms = 1;
  bool _roomsTouched = false;
  int _extraBeds = 0;
  bool _breakfastOn = false;
  final _breakfastCtrl = TextEditingController();
  bool _taxOn = true;

  FacilityTariff get _t => widget.tariff;

  @override
  void initState() {
    super.initState();
    _categories = StayCostCalculator.categories(_t);
    _catId = _defaultCategory().id;
    _loadOptions();
  }

  @override
  void dispose() {
    _breakfastCtrl.dispose();
    super.dispose();
  }

  TariffCategory _defaultCategory() {
    for (final c in _categories) {
      final s = '${c.id} ${c.ad}'.toLowerCase();
      if (s.contains('sivil') || s.contains('misafir') || s.contains('genel')) {
        return c;
      }
    }
    return _categories.first;
  }

  void _loadOptions() {
    final prevRow = _options.isEmpty ? null : _options[_optionIndex].row;
    _options = StayCostCalculator.roomOptions(_t, _catId);
    final keep = prevRow == null ? -1 : _options.indexWhere((o) => o.row == prevRow);
    _optionIndex = keep >= 0 ? keep : 0;
    _applyOption();
  }

  void _applyOption() {
    final o = _option;
    if (o == null) return;
    final b = StayCostCalculator.inferBasis(_t, o);
    _basis = b.basis;
    _basisExplicit = b.explicit;
    if (!_roomsTouched) {
      _rooms = StayCostCalculator.suggestedRooms(o, _adults + _children);
    }
  }

  StayRoomOption? get _option =>
      _options.isEmpty ? null : _options[_optionIndex];

  double? get _extraBedAmount => StayCostCalculator.extraBedAmount(_t, _catId);
  double? get _breakfastRowAmount =>
      StayCostCalculator.breakfastAmount(_t, _catId);
  bool? get _breakfastIncluded =>
      StayCostCalculator.breakfastIncluded(_t, _option);
  double? get _taxRate => StayCostCalculator.lodgingTaxRate(_t);

  double? get _breakfastPrice {
    if (!_breakfastOn || _breakfastIncluded == true) return null;
    final fromRow = _breakfastRowAmount;
    if (fromRow != null) return fromRow;
    return double.tryParse(_breakfastCtrl.text.replaceAll('.', '').replaceAll(',', '.'));
  }

  StayCostBreakdown? get _result {
    final o = _option;
    if (o == null) return null;
    return StayCostCalculator.compute(
      StayCostInput(
        nightlyAmount: o.amount,
        basis: _basis,
        nights: _nights,
        adults: _adults,
        children: _children,
        childFactor: _childFactor,
        rooms: _rooms,
        extraBeds: _extraBeds,
        extraBedAmount: _extraBedAmount,
        breakfastPerPerson: _breakfastPrice,
        taxRate: _taxOn ? (_taxRate ?? 0) : 0,
      ),
    );
  }

  String get _catName =>
      _categories.firstWhere((c) => c.id == _catId).ad;

  void _setPeople({int? adults, int? children}) {
    setState(() {
      _adults = adults ?? _adults;
      _children = children ?? _children;
      if (!_roomsTouched && _option != null) {
        _rooms = StayCostCalculator.suggestedRooms(_option!, _adults + _children);
      }
    });
  }

  Future<void> _share(StayCostBreakdown r) async {
    final o = _option!;
    final people = [
      '$_adults yetişkin',
      if (_children > 0) '$_children çocuk',
    ].join(', ');
    final b = StringBuffer()
      ..writeln(widget.facility.isim)
      ..writeln('${o.row.ad} · $_catName')
      ..writeln('$_nights gece · $people')
      ..writeln()
      ..writeln('Tahmini toplam: ${formatTl(r.total)}')
      ..writeln('(Tarifeye göre hesaplandı; kesin tutar için tesisle görüşün.)')
      ..writeln()
      ..write(StoreLinks.shareDownloadFooter());
    await Share.share(b.toString());
  }

  @override
  Widget build(BuildContext context) {
    final o = _option;
    final r = _result;
    final childNotes = StayCostCalculator.childNotes(_t);
    final breakfastNotes = StayCostCalculator.breakfastNotes(_t);
    final unconfirmed = _t.dogrulama == TariffVerification.teyitGerekli;

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.calculate_outlined, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    FacilityPricing.calcTitle,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    widget.facility.isim,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7C82)),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_categories.length > 1) ...[
          const _SectionTitle('Fiyat grubu'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _categories)
                ChoiceChip(
                  label: Text(c.ad),
                  selected: c.id == _catId,
                  onSelected: (_) => setState(() {
                    _catId = c.id;
                    _loadOptions();
                  }),
                ),
            ],
          ),
        ],
        const _SectionTitle('Konaklama tipi'),
        DropdownButtonFormField<int>(
          initialValue: _optionIndex,
          key: ValueKey(_catId),
          isExpanded: true,
          decoration: _fieldDecoration(),
          items: [
            for (final (i, opt) in _options.indexed)
              DropdownMenuItem(
                value: i,
                child: Text(
                  '${opt.label} — ${formatTl(opt.amount)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (i) => setState(() {
            _optionIndex = i ?? 0;
            _roomsTouched = false;
            _applyOption();
          }),
        ),
        const _SectionTitle('Fiyat birimi'),
        SegmentedButton<StayPriceBasis>(
          segments: const [
            ButtonSegment(
              value: StayPriceBasis.perPerson,
              label: Text('Kişi başı'),
              icon: Icon(Icons.person_outline, size: 18),
            ),
            ButtonSegment(
              value: StayPriceBasis.perRoom,
              label: Text('Oda başı'),
              icon: Icon(Icons.bed_outlined, size: 18),
            ),
          ],
          selected: {_basis},
          onSelectionChanged: (s) => setState(() {
            _basis = s.first;
            _basisExplicit = false;
          }),
        ),
        _Hint(
          _basisExplicit
              ? 'Tarifede belirtilen birim.'
              : 'Tarifede birim açık yazmıyor; tesisle teyit edin, gerekirse değiştirin.',
          warn: !_basisExplicit,
        ),
        const _SectionTitle('Konaklama'),
        _StepperRow(
          icon: Icons.nights_stay_outlined,
          label: 'Gece',
          value: _nights,
          min: 1,
          max: 60,
          onChanged: (v) => setState(() => _nights = v),
        ),
        _StepperRow(
          icon: Icons.person_outline,
          label: 'Yetişkin',
          value: _adults,
          min: 1,
          max: 12,
          onChanged: (v) => _setPeople(adults: v),
        ),
        _StepperRow(
          icon: Icons.child_care_outlined,
          label: 'Çocuk',
          value: _children,
          min: 0,
          max: 10,
          onChanged: (v) => _setPeople(children: v),
        ),
        if (_basis == StayPriceBasis.perRoom)
          _StepperRow(
            icon: Icons.meeting_room_outlined,
            label: 'Oda',
            value: _rooms,
            min: 1,
            max: 20,
            onChanged: (v) => setState(() {
              _rooms = v;
              _roomsTouched = true;
            }),
          ),
        if (_extraBedAmount != null)
          _StepperRow(
            icon: Icons.single_bed_outlined,
            label: 'Ek yatak (${formatTl(_extraBedAmount!)} / gece)',
            value: _extraBeds,
            min: 0,
            max: 6,
            onChanged: (v) => setState(() => _extraBeds = v),
          ),
        if (_children > 0 && _basis == StayPriceBasis.perPerson) ...[
          const _SectionTitle('Çocuk konaklama ücreti'),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Ücretsiz')),
              ButtonSegment(value: 0.5, label: Text('Yarım')),
              ButtonSegment(value: 1, label: Text('Tam')),
            ],
            selected: {_childFactor},
            onSelectionChanged: (s) => setState(() => _childFactor = s.first),
          ),
          if (childNotes.isNotEmpty)
            _NotesBox(title: 'Tesisin çocuk kuralı', notes: childNotes)
          else
            const _Hint('Tarifede çocuk indirimi belirtilmemiş; tesise sorun.', warn: true),
        ],
        const _SectionTitle('Kahvaltı'),
        if (_breakfastIncluded == true)
          const _Hint('Tarifeye göre kahvaltı fiyata dahil.')
        else ...[
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _breakfastOn,
            onChanged: (v) => setState(() => _breakfastOn = v),
            title: Text(
              _breakfastRowAmount != null
                  ? 'Kahvaltı ekle (${formatTl(_breakfastRowAmount!)} / kişi / gün)'
                  : 'Kahvaltı ekle',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          if (_breakfastOn && _breakfastRowAmount == null)
            TextField(
              controller: _breakfastCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _fieldDecoration(
                hint: 'Kişi başı günlük kahvaltı ücreti (TL)',
              ),
              onChanged: (_) => setState(() {}),
            ),
          if (breakfastNotes.isNotEmpty)
            _NotesBox(title: 'Tesisin kahvaltı bilgisi', notes: breakfastNotes)
          else if (_breakfastIncluded == null)
            const _Hint('Tarifede kahvaltı bilgisi yok.'),
        ],
        if (_taxRate != null)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _taxOn,
            onChanged: (v) => setState(() => _taxOn = v),
            title: Text(
              'Konaklama vergisi (%${(_taxRate! * 100).toStringAsFixed(0)})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Tarifede ek ücret olarak belirtilmiş.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),
        if (o != null && r != null)
          _ResultCard(
            result: r,
            nights: _nights,
            unconfirmed: unconfirmed,
            onShare: () => _share(r),
          ),
      ],
    );
  }

  static InputDecoration _fieldDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF3F7F8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.warn = false});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              warn ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded,
              size: 15,
              color: warn ? const Color(0xFFE08600) : const Color(0xFF2E7D32),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 12, color: Color(0xFF5A6B70), height: 1.35),
              ),
            ),
          ],
        ),
      );
}

class _NotesBox extends StatelessWidget {
  const _NotesBox({required this.title, required this.notes});

  final String title;
  final List<String> notes;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• $n',
                  style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF5A4A00)),
                ),
              ),
          ],
        ),
      );
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_rounded, size: 18),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_rounded, size: 18),
            ),
          ],
        ),
      );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.nights,
    required this.unconfirmed,
    required this.onShare,
  });

  final StayCostBreakdown result;
  final int nights;
  final bool unconfirmed;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final r = result;
    Widget line(String label, double v) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                ),
              ),
              Text(
                formatTl(v),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.82)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tahmini toplam',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
          ),
          Text(
            formatTl(r.total),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (nights > 1)
            Text(
              'Gecelik ortalama ${formatTl(r.total / nights)}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
            ),
          const SizedBox(height: 6),
          line('Konaklama', r.lodging),
          if (r.extraBeds > 0) line('Ek yatak', r.extraBeds),
          if (r.breakfast > 0) line('Kahvaltı', r.breakfast),
          if (r.tax > 0) line('Konaklama vergisi', r.tax),
          const SizedBox(height: 12),
          Text(
            unconfirmed
                ? 'Bu tesisin fiyatı teyit gerektiriyor. Hesap tarifeye göredir; kesin tutar için tesisle görüşün.'
                : 'Hesap tarifeye göredir; dönem, kampanya ve tesis kuralları tutarı değiştirebilir.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('Hesabı paylaş'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
