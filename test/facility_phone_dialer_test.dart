import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';
import 'package:rotalink_flutter/utils/facility_phone_dialer.dart';

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];

  setUp(() {
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'canLaunch') return true;
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
        return true;
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  Misafirhane facility(String first, [String second = '']) => Misafirhane(
    isim: 'Konya Orduevi',
    il: 'Konya',
    adres: '',
    telefon: first,
    telefon2: second,
    latitude: 0,
    longitude: 0,
    tip: 'Orduevi',
  );

  Future<void> render(WidgetTester tester, Misafirhane item) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => FacilityPhoneDialer.open(context, item),
                child: const Text('Ara'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ara'));
    await tester.pumpAndSettle();
  }

  testWidgets('tek numara seçimsiz arama ekranına gider', (tester) async {
    await render(tester, facility('(0332) 321 14 11'));
    expect(find.text('Aramak istediğiniz numarayı seçin'), findsNothing);
    expect(launched, ['tel:03323211411']);
  });

  testWidgets('iki numara yalnız seçilen numarayı arar', (tester) async {
    await render(tester, facility('(0332) 321 14 11', '0532 123 45 67'));
    expect(launched, isEmpty);
    expect(find.text('Aramak istediğiniz numarayı seçin'), findsOneWidget);
    await tester.tap(find.text('0532 123 45 67'));
    await tester.pumpAndSettle();
    expect(launched, ['tel:05321234567']);
  });

  testWidgets('eski birleşik numarada da seçim yaptırır', (tester) async {
    await render(tester, facility('(0332) 321 14 11 / 0532 123 45 67'));
    expect(launched, isEmpty);
    await tester.tap(find.text('0532 123 45 67'));
    await tester.pumpAndSettle();
    expect(launched, ['tel:05321234567']);
  });

  testWidgets('numara yoksa arama açılmaz', (tester) async {
    await render(tester, facility(''));
    expect(launched, isEmpty);
    expect(find.text('Telefon numarası mevcut değil.'), findsOneWidget);
  });
}
