import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:kiwi_lens_mobile/widgets/explore_search.dart';

void main() {
  testWidgets('destination icon is painted and visible without an icon font', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExploreSearch(currentLocation: null, onSelected: (_) {}),
        ),
      ),
    );
    final icon = find.byKey(const Key('destinationSearchIcon'));
    expect(icon, findsOneWidget);
    final box = tester.renderObject<RenderBox>(icon);
    expect(box.size.width, 20);
    expect(box.size.height, 20);
  });

  testWidgets(
    'recent results show the full name, street address and distance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExploreSearch(
              currentLocation: const LatLng(
                latitude: -36.8485,
                longitude: 174.7633,
              ),
              recent: const [
                DestinationSuggestion(
                  label: 'Auckland Art Gallery, Auckland, New Zealand',
                  name: 'Auckland Art Gallery Toi o Tāmaki',
                  address: 'Wellesley Street East, Auckland Central',
                  location: LatLng(latitude: -36.8509, longitude: 174.7666),
                ),
              ],
              onSelected: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField).last);
      await tester.pump();

      expect(find.text('Auckland Art Gallery Toi o Tāmaki'), findsOneWidget);
      expect(
        find.text('Wellesley Street East, Auckland Central'),
        findsOneWidget,
      );
      expect(
        find.textContaining(RegExp(r'\d+(?:\.\d+)? (?:m|km)')),
        findsOneWidget,
      );
    },
  );
}
