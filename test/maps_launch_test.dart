import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/utils/maps_launch.dart';

void main() {
  test('Apple Haritalar arama ve yol tarifi adresi üretir', () {
    expect(
      appleMapSearchUri('Kayseri Öğretmenevi').toString(),
      'http://maps.apple.com/?q=Kayseri%20%C3%96%C4%9Fretmenevi',
    );
    expect(
      appleMapSearchUri('Tesis', latitude: 38.7, longitude: 35.4).toString(),
      'http://maps.apple.com/?ll=38.7,35.4&q=Tesis',
    );
    expect(
      appleDirectionsUri(
        origin: '39.9,32.8',
        destinations: ['38.7,35.4'],
        walking: true,
      ).toString(),
      'http://maps.apple.com/?dirflg=w&saddr=39.9,32.8&daddr=38.7,35.4',
    );
    expect(
      googleDirectionsUri(origin: '39.9,32.8', destination: '38.7,35.4').queryParameters['travelmode'],
      'driving',
    );
  });
}
