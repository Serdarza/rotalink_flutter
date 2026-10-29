import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/services/place_resolver.dart';

void main() {
  test('ilden ile arama varış ilini bulur, tesis adını il sanmaz', () {
    final izmir = PlaceResolver.travelDestination("Ankara'dan İzmir'e");
    expect(izmir?.name, 'İzmir');
    expect(izmir?.latitude, isNot(0));

    final istanbul = PlaceResolver.travelDestination('Ankara İstanbul');
    expect(istanbul?.name, 'İstanbul');

    final suffix = PlaceResolver.travelDestination("Bolu'ya");
    expect(suffix?.name, 'Bolu');

    expect(PlaceResolver.travelDestination('Düzce Cedidiye Camii'), isNull);
    expect(PlaceResolver.travelDestination('Ankara Çankaya'), isNull);
  });

  test('cami araması il adını sona alır ve camii ile camiyi eşler', () {
    expect(PlaceResolver.searchPhrase('Bursa Ulu Camii'), 'Ulu Camii, Bursa');
    expect(PlaceResolver.searchPhrase('Düzce Cedidiye Camii'), 'Cedidiye Camii, Düzce');
    expect(
      PlaceResolver.placeScore('Ulu Cami, Osmangazi, Bursa', 'Bursa Ulu Camii'),
      greaterThan(PlaceResolver.placeScore('Bursa', 'Bursa Ulu Camii')),
    );
  });
}
