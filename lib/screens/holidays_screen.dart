import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/public_holidays_2026.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

/// 2026 resmi tatiller — liste, kart tasarımı ve geri sayım.
class HolidaysScreen extends StatefulWidget {
  const HolidaysScreen({super.key});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

enum _HolidayTiming {
  /// Tatil bitti.
  past,

  /// Devam ediyor veya başlangıca 30 günden az kaldı.
  withinOneMonth,

  /// Başlangıca 30 gün veya daha fazla.
  futureBeyond,
}

class _HolidayCardStyle {
  const _HolidayCardStyle({
    required this.strip,
    required this.iconBg,
    required this.iconFg,
    required this.dateFg,
    required this.dateChipBg,
    required this.dateChipBorder,
    required this.countdownBg,
    required this.countdownFg,
    required this.countdownIcon,
    required this.durationChipBg,
    required this.durationChipFg,
    required this.cardBorder,
    required this.titleMuted,
  });

  final Color strip;
  final Color iconBg;
  final Color iconFg;
  final Color dateFg;
  final Color dateChipBg;
  final Color dateChipBorder;
  final Color countdownBg;
  final Color countdownFg;
  final Color countdownIcon;
  final Color durationChipBg;
  final Color durationChipFg;
  final Color cardBorder;
  final bool titleMuted;
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static _HolidayTiming _holidayTiming(PublicHoliday2026 h, DateTime now) {
    final t = _dateOnly(now);
    final d0 = _dateOnly(h.start);
    final d1 = _dateOnly(h.endInclusive);
    if (t.isAfter(d1)) return _HolidayTiming.past;
    if (!t.isBefore(d0) && !t.isAfter(d1)) {
      return _HolidayTiming.withinOneMonth;
    }
    final daysUntil = d0.difference(t).inDays;
    if (daysUntil < 30) return _HolidayTiming.withinOneMonth;
    return _HolidayTiming.futureBeyond;
  }

  static _HolidayCardStyle _cardStyle(_HolidayTiming timing) {
    switch (timing) {
      case _HolidayTiming.past:
        return const _HolidayCardStyle(
          strip: Color(0xFFE53935),
          iconBg: Color(0xFFFFEBEE),
          iconFg: Color(0xFFC62828),
          dateFg: Color(0xFFB71C1C),
          dateChipBg: Color(0xFFFFEBEE),
          dateChipBorder: Color(0xFFEF9A9A),
          countdownBg: Color(0xFFF5F5F5),
          countdownFg: Color(0xFF616161),
          countdownIcon: Color(0xFF9E9E9E),
          durationChipBg: Color(0xFFEEEEEE),
          durationChipFg: Color(0xFF616161),
          cardBorder: Color(0xFFFFCDD2),
          titleMuted: true,
        );
      case _HolidayTiming.withinOneMonth:
        return const _HolidayCardStyle(
          strip: Color(0xFF43A047),
          iconBg: Color(0xFFE8F5E9),
          iconFg: Color(0xFF2E7D32),
          dateFg: Color(0xFF1B5E20),
          dateChipBg: Color(0xFFE8F5E9),
          dateChipBorder: Color(0xFFA5D6A7),
          countdownBg: Color(0xFFC8E6C9),
          countdownFg: Color(0xFF1B5E20),
          countdownIcon: Color(0xFF2E7D32),
          durationChipBg: Color(0xFFF1F8E9),
          durationChipFg: Color(0xFF33691E),
          cardBorder: Color(0xFFC8E6C9),
          titleMuted: false,
        );
      case _HolidayTiming.futureBeyond:
        return const _HolidayCardStyle(
          strip: Color(0xFFF9A825),
          iconBg: Color(0xFFFFF8E1),
          iconFg: Color(0xFFF57F17),
          dateFg: Color(0xFFE65100),
          dateChipBg: Color(0xFFFFF8E1),
          dateChipBorder: Color(0xFFFFE082),
          countdownBg: Color(0xFFFFECB3),
          countdownFg: Color(0xFFE65100),
          countdownIcon: Color(0xFFF57C00),
          durationChipBg: Color(0xFFFFFDE7),
          durationChipFg: Color(0xFFF57F17),
          cardBorder: Color(0xFFFFE082),
          titleMuted: false,
        );
    }
  }

  static IconData _countdownIcon(_HolidayTiming timing) {
    switch (timing) {
      case _HolidayTiming.past:
        return Icons.history_rounded;
      case _HolidayTiming.withinOneMonth:
        return Icons.event_available_rounded;
      case _HolidayTiming.futureBeyond:
        return Icons.event_note_rounded;
    }
  }

  static String _countdownText(PublicHoliday2026 h, DateTime now) {
    final t = _dateOnly(now);
    final d0 = _dateOnly(h.start);
    final d1 = _dateOnly(h.endInclusive);
    if (t.isAfter(d1)) return 'Geçti';
    if (!t.isBefore(d0) && !t.isAfter(d1)) {
      if (_sameDate(t, d0)) return 'Bugün';
      return 'Tatil devam ediyor';
    }
    final n = d0.difference(t).inDays;
    return n <= 0 ? 'Bugün' : '$n gün kaldı';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.drawerHolidays),
      ),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        itemCount: kPublicHolidays2026.length,
        itemBuilder: (context, index) {
          final h = kPublicHolidays2026[index];
          final countdown = _countdownText(h, now);
          final timing = _holidayTiming(h, now);
          final style = _cardStyle(timing);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 0,
              shadowColor: Colors.black26,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: style.cardBorder.withValues(alpha: 0.85),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              // [ListView] + [Row] + [Expanded]: içsel yükseklik 0 olur; kart görünmez.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 5, color: style.strip),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: style.iconBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: style.dateChipBorder.withValues(alpha: 0.65),
                                  ),
                                ),
                                child: Icon(
                                  Icons.event_outlined,
                                  color: style.iconFg,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      h.name,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: style.titleMuted
                                            ? AppColors.campaignSummaryMuted
                                            : AppColors.textPrimary,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: style.dateChipBg,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: style.dateChipBorder.withValues(alpha: 0.9),
                                        ),
                                      ),
                                      child: Text(
                                        h.dateLine,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: style.dateFg,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                label: Text(
                                  'Süre: ${h.durationLabel}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: style.durationChipFg,
                                  ),
                                ),
                                backgroundColor: style.durationChipBg,
                                side: BorderSide(
                                  color: style.dateChipBorder.withValues(alpha: 0.45),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                              ),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                avatar: Icon(
                                  _countdownIcon(timing),
                                  size: 16,
                                  color: style.countdownIcon,
                                ),
                                label: Text(
                                  countdown,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: style.countdownFg,
                                  ),
                                ),
                                backgroundColor: style.countdownBg,
                                side: BorderSide(
                                  color: style.dateChipBorder.withValues(alpha: 0.55),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
