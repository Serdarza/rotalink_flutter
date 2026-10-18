import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/deeplink/deep_link_target.dart';
import 'package:rotalink_flutter/services/calendar_event_service.dart';
import 'package:rotalink_flutter/services/view_counter_service.dart';

void main() {
  test('Türkçe sayı biçimi', () {
    expect(ViewCounterService.formatTr(0), '0');
    expect(ViewCounterService.formatTr(7), '7');
    expect(ViewCounterService.formatTr(999), '999');
    expect(ViewCounterService.formatTr(1000), '1.000');
    expect(ViewCounterService.formatTr(1248), '1.248');
    expect(ViewCounterService.formatTr(1234567), '1.234.567');
  });

  test('belge kimliği: her kategori ayrı, aynı kayıt aynı kimlik', () {
    final all = [
      for (final c in ViewCategory.values)
        ViewCounterService.keyFor(c, 'Düzce', 'Yığılca Öğretmenevi'),
    ];
    expect(all.toSet().length, ViewCategory.values.length);
    expect(
      ViewCounterService.keyFor(
        ViewCategory.konaklama,
        'Düzce',
        ' Yığılca Öğretmenevi ',
      ),
      ViewCounterService.keyFor(
        ViewCategory.konaklama,
        'Düzce',
        'Yığılca Öğretmenevi',
      ),
    );
    for (final id in all) {
      expect(id.contains('/'), isFalse);
      expect(id.startsWith('__'), isFalse);
    }
    expect(ViewCounterService.keyFor(ViewCategory.kamp, 'Düzce', '  '), '');
  });

  test('takvim bağlantısı tesis detayına değil açılış ekranına gider', () {
    final target = DeepLinkTarget.fromUri(
      Uri.parse(CalendarEventService.appLink),
    );
    expect(target, isNotNull);
    expect(target!.kind, DeepLinkKind.home);
    expect(target.facilitySlug, isNull);
    expect(
      CalendarEventService.notesFor(),
      contains(CalendarEventService.appLink),
    );
  });
}
