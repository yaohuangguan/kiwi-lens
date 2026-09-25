import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
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
    points: [GeoPoint(-36.85, 174.76), GeoPoint(-36.84, 174.76)],
    provider: 'test',
    traffic: TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
    trafficIntervals: [],
    steps: [
      RouteStepInfo(
        instruction: 'Continue on Queen Street',
        distanceMeters: 1100,
        location: GeoPoint(-36.849, 174.76),
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
          .upcoming(const GeoPoint(-36.848, 174.76), route.points, matches)
          ?.camera
          .id,
      'on-route',
    );
    expect(
      matcher.upcoming(const GeoPoint(-36.843, 174.76), route.points, matches),
      isNull,
    );
  });
}
