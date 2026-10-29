import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/widgets/rotalink_glass_bottom_nav.dart';

void main() {
  testWidgets('alt menü Rota yerine Harita gösterir', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: RotalinkGlassBottomNav(
            selected: RotalinkBottomNavItem.route,
            onHome: () {},
            onFavorites: () {},
            onSearch: () {},
            onRoutePlan: () {},
            onDiscover: () {},
          ),
        ),
      ),
    );
    expect(find.text('Harita'), findsOneWidget);
    expect(find.text('Rota'), findsNothing);
    expect(find.byIcon(Icons.map_rounded), findsOneWidget);
  });
}
