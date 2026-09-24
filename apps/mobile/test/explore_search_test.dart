import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
