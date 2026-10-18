import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/providers/facility_filter_provider.dart';
import 'package:rotalink_flutter/theme/ara_ui.dart';
import 'package:rotalink_flutter/widgets/facility_type_filter_chips.dart';

void main() {
  testWidgets(
    'seçili çip dolu turkuaz, pasif çip beyaz; seçim filtreyi değiştirir',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(height: 48, child: FacilityTypeFilterChips()),
            ),
          ),
        ),
      );

      FilterChip chipOf(String label) =>
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));

      expect(chipOf(kFacilityFilterAll).selected, isTrue);
      expect(chipOf(kFacilityFilterAll).selectedColor, AraUi.activeFill);
      expect(chipOf('Orduevi').selected, isFalse);
      expect(chipOf('Orduevi').backgroundColor, AraUi.inactiveFill);

      await tester.tap(find.widgetWithText(FilterChip, 'Orduevi'));
      await tester.pump();

      expect(container.read(facilityTypeFilterProvider), 'Orduevi');
      expect(chipOf('Orduevi').selected, isTrue);
      expect(chipOf(kFacilityFilterAll).selected, isFalse);
    },
  );
}
