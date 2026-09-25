import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/providers/provider_contracts.dart';
import 'package:kiwi_lens_mobile/widgets/full_screen_search.dart';

class _DelayedSearch implements SearchProvider {
  final queries = <String>[];
  final pending = <Completer<List<PlaceCandidate>>>[];

  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) {
    queries.add(query);
    final completer = Completer<List<PlaceCandidate>>();
    pending.add(completer);
    return completer.future;
  }
}

void main() {
  test('provider references do not silently cross map policies', () {
    const google = ProviderPolicy(MapProvider.google);
    const mapbox = ProviderPolicy(MapProvider.mapbox);
    expect(google.canDisplay(const ProviderReference('google', 'g1')), isTrue);
    expect(google.canDisplay(const ProviderReference('mapbox', 'm1')), isFalse);
    expect(mapbox.canDisplay(const ProviderReference('mapbox', 'm1')), isTrue);
    expect(mapbox.canDisplay(const ProviderReference('google', 'g1')), isFalse);
  });

  test('street addresses retain their exact first line', () {
    const address = PlaceCandidate(
      name: '18 Queen Street',
      address: '18 Queen Street, Auckland CBD, Auckland 1010',
      kind: PlaceKind.address,
    );
    expect(address.secondaryAddress, 'Auckland CBD, Auckland 1010');
    expect(
      address.toPlace(const GeoPoint(-36.844, 174.766)).name,
      '18 Queen Street',
    );
  });

  testWidgets('search waits 280 ms and ignores stale responses', (
    tester,
  ) async {
    final provider = _DelayedSearch();
    await tester.pumpWidget(
      MaterialApp(
        home: FullScreenSearch(
          provider: provider,
          resolve: (candidate) async => candidate.toPlace(candidate.location!),
          language: 'en',
          recent: const [],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Cordis');
    await tester.pump(const Duration(milliseconds: 279));
    expect(provider.queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(provider.queries, ['Cordis']);

    await tester.enterText(find.byType(TextField), 'Cordis Auckland');
    await tester.pump(const Duration(milliseconds: 280));
    expect(provider.queries, ['Cordis', 'Cordis Auckland']);

    provider.pending.first.complete(const [
      PlaceCandidate(name: 'Old result', location: GeoPoint(-36.8, 174.7)),
    ]);
    await tester.pump();
    expect(find.text('Old result'), findsNothing);

    provider.pending.last.complete(const [
      PlaceCandidate(
        name: 'Cordis Auckland',
        address: '83 Symonds Street, Grafton, Auckland',
        location: GeoPoint(-36.856, 174.764),
      ),
    ]);
    await tester.pump();
    expect(find.widgetWithText(ListTile, 'Cordis Auckland'), findsOneWidget);
    expect(find.text('83 Symonds Street, Grafton, Auckland'), findsOneWidget);
  });
}
