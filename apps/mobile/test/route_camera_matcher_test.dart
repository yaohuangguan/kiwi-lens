import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:kiwi_lens_mobile/domain/route_option.dart';
import 'package:kiwi_lens_mobile/domain/safety_camera.dart';
import 'package:kiwi_lens_mobile/drive/route_camera_matcher.dart';

void main() {
  const matcher = RouteCameraMatcher();
  const route = RouteOption(
    id: 'northbound',
    mode: KiwiTravelMode.drive,
    durationSeconds: 200,
    distanceMeters: 1100,
    points: [
      LatLng(latitude: -36.85, longitude: 174.76),
      LatLng(latitude: -36.84, longitude: 174.76),
    ],
    provider: 'test',
    traffic: TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
    trafficIntervals: [],
    steps: [
      RouteStepInfo(
        instruction: 'Continue on Queen Street',
        distanceMeters: 1100,
        location: LatLng(latitude: -36.849, longitude: 174.76),
      ),
    ],
  );
  const onRoute = SafetyCamera(
    id: 'on-route',
    name: 'Queen St camera',
    region: 'Auckland',
    suburb: 'City',
    location: 'Queen Street NB',
    type: 'Spot speed',
    latitude: -36.845,
    longitude: 174.7601,
  );
  const parallel = SafetyCamera(
    id: 'parallel',
    name: 'Parallel road camera',
    region: 'Auckland',
    suburb: 'City',
    location: 'Parallel Road',
    type: 'Spot speed',
    latitude: -36.845,
    longitude: 174.761,
  );
  const opposite = SafetyCamera(
    id: 'opposite',
    name: 'Opposite direction',
    region: 'Auckland',
    suburb: 'City',
    location: 'Queen Street SB',
    type: 'Spot speed',
    latitude: -36.846,
    longitude: 174.76,
  );

  test(
    'matches a route camera while excluding adjacent and opposite roads',
    () {
      final matches = matcher.match(route, [onRoute, parallel, opposite]);
      expect(matches.map((match) => match.camera.id), ['on-route']);
      expect(matches.single.highConfidence, isTrue);
    },
  );

  test('upcoming is based on distance along the route, not raw radius', () {
    final matches = matcher.match(route, [onRoute]);
    expect(
      matcher
          .upcoming(
            const LatLng(latitude: -36.848, longitude: 174.76),
            route.points,
            matches,
          )
          ?.camera
          .id,
      'on-route',
    );
    expect(
      matcher.upcoming(
        const LatLng(latitude: -36.843, longitude: 174.76),
        route.points,
        matches,
      ),
      isNull,
    );
  });
}
