import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_lens_mobile/data/account_repository.dart';
import 'package:kiwi_lens_mobile/data/parking_repository.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/route_option.dart';
import 'package:kiwi_lens_mobile/theme/tasman_theme.dart';
import 'package:kiwi_lens_mobile/widgets/profile_page.dart';
import 'package:kiwi_lens_mobile/widgets/route_preview_sheet.dart';

void main() {
  const destination = GeoPoint(-36.8485, 174.7633);

  test('AT parking is filtered, ordered and keeps capacity separate', () async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/query'));
      expect(request.url.queryParameters['distance'], '1500');
      return http.Response(
        jsonEncode({
          'features': [
            {
              'properties': {
                'OBJECTID': 1,
                'SHORTDESCRIPTION': 'Far car park',
                'STATUS': 'Open',
                'TOTALSPACES': 300,
              },
              'geometry': {
                'coordinates': [174.770, -36.8485],
              },
            },
            {
              'properties': {
                'OBJECTID': 2,
                'SHORTDESCRIPTION': 'Closed car park',
                'STATUS': 'Closed',
                'TOTALSPACES': 100,
              },
              'geometry': {
                'coordinates': [174.7634, -36.8485],
              },
            },
            {
              'properties': {
                'OBJECTID': 3,
                'SHORTDESCRIPTION': 'Near car park',
                'STREET': 'Queen Street',
                'STATUS': 'Open',
                'TOTALSPACES': 150,
                'MOBILITYSPACES': 4,
                'CLEARANCEMETERS': 2.1,
              },
              'geometry': {
                'coordinates': [174.764, -36.8485],
              },
            },
          ],
        }),
        200,
      );
    });
    final repository = ParkingRepository(client: client);
    final places = await repository.nearby(
      destination: destination,
      allowGoogleFallback: false,
    );
    expect(places.map((place) => place.id), ['at-3', 'at-1']);
    expect(places.first.totalSpaces, 150);
    expect(places.first.mobilitySpaces, 4);
    expect(places.first.clearanceMeters, 2.1);
    expect(places.first.toPlaceSummary().reference, isNull);
    repository.dispose();
  });

  test('Google parking fills regions without AT records', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/query')) {
        return http.Response('{"features":[]}', 200);
      }
      expect(request.url.path, '/api/explore');
      expect(request.url.queryParameters['category'], 'parking');
      return http.Response(
        jsonEncode([
          {
            'placeId': 'test-parking',
            'name': 'Nearby garage',
            'address': 'Auckland',
            'latitude': -36.8484,
            'longitude': 174.7634,
          },
        ]),
        200,
      );
    });
    final repository = ParkingRepository(client: client);
    final places = await repository.nearby(
      destination: destination,
      allowGoogleFallback: true,
    );
    expect(places.single.source, 'Google');
    expect(places.single.toPlaceSummary().reference?.id, 'test-parking');
    repository.dispose();
  });

  testWidgets('My Tasman uses the dark scaffold background', (tester) async {
    final account = AccountRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: TasmanTheme.dark,
        home: ProfilePage(
          account: account,
          voiceEnabled: true,
          lanesEnabled: true,
          appLanguage: 'en',
          voiceLanguage: 'en-NZ',
          onVoiceChanged: (_) {},
          onLanesChanged: (_) {},
          onAppLanguageChanged: (_) {},
          onLanguageChanged: (_) {},
          onMapLayers: () {},
          mapProvider: MapProvider.google,
          locationMarker: LocationMarkerStyle.kiwi,
          onMapProviderChanged: (value) async => value,
          onLocationMarkerChanged: (_) {},
          mapboxAvailable: false,
          notifySafetyCameras: false,
          notifyRoadIncidents: false,
          notifyCommunityReports: false,
          notifySavedRouteDisruptions: false,
          onNotifySafetyCamerasChanged: (_) {},
          onNotifyRoadIncidentsChanged: (_) {},
          onNotifyCommunityReportsChanged: (_) {},
          onNotifySavedRouteDisruptionsChanged: (_) {},
        ),
      ),
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, TasmanColors.midnightOcean);
    await tester.pumpWidget(const SizedBox.shrink());
    account.dispose();
  });
  testWidgets('route preview selects a parking destination', (tester) async {
    ParkingPlace? selected;
    const place = ParkingPlace(
      id: 'at-3',
      name: 'Near car park',
      address: 'Queen Street',
      location: destination,
      distanceMeters: 120,
      source: 'AT',
      totalSpaces: 150,
    );
    const route = RouteOption(
      id: 'drive-1',
      mode: KiwiTravelMode.drive,
      durationSeconds: 600,
      distanceMeters: 3000,
      points: [destination],
      provider: 'google',
      traffic: TrafficSummary(normal: 1, slow: 0, trafficJam: 0),
      trafficIntervals: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: TasmanTheme.dark,
        home: Scaffold(
          body: RoutePreviewSheet(
            destinationTitle: 'City Library',
            originTitle: 'Current location',
            plan: const RoutePlan(
              options: [route],
              trafficAvailable: false,
              provider: 'google',
              stopsApplied: 0,
            ),
            selectedMode: KiwiTravelMode.drive,
            selectedRouteId: 'drive-1',
            busy: false,
            stopCount: 0,
            cameraCount: 0,
            customOrigin: false,
            onModeChanged: (_) {},
            onRouteSelected: (_) {},
            onStart: () {},
            onAddStop: () {},
            onSave: () {},
            isFavorite: false,
            onFavorite: () {},
            onReview: () {},
            onClose: () {},
            parkingPlaces: const [place],
            onParkingSelected: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Near car park'));
    await tester.tap(find.text('Near car park'));
    expect(selected?.id, 'at-3');
    expect(find.text('150 total spaces'), findsOneWidget);
  });

  testWidgets('parking continuation opens walking leg', (tester) async {
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: TasmanTheme.dark,
        home: Scaffold(
          body: ParkingContinuationCard(
            destinationTitle: 'City Library',
            parkingTitle: 'Near car park',
            onContinue: () => continued = true,
            onEnd: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Continue on foot'));
    expect(continued, isTrue);
  });
}
