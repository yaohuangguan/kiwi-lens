import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/domain/country_profile.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/road_event.dart';
import 'package:kiwi_lens_mobile/domain/road_intelligence.dart';
import 'package:kiwi_lens_mobile/domain/route_option.dart';

RoadEvent camera(String id, GeoPoint point, {DateTime? until}) => RoadEvent(
  id: id,
  type: RoadEventType.safetyCamera,
  location: point,
  source: RoadEventSource(provider: 'test', country: 'NZ', sourceId: id),
  validUntil: until,
);

RouteOption eastRoute() => const RouteOption(
  id: 'east',
  mode: KiwiTravelMode.drive,
  durationSeconds: 600,
  distanceMeters: 1112,
  points: [GeoPoint(0, 0), GeoPoint(0, .01)],
  provider: 'test',
  traffic: TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: [],
);

class CountingProvider implements RoadEventProvider {
  int calls = 0;
  @override
  bool supports(CountryProfile country) => country.code == 'NZ';
  @override
  Future<List<RoadEvent>> load() async {
    calls++;
    return [camera('one', const GeoPoint(0, .005))];
  }
}

class FailingProvider implements RoadEventProvider {
  @override
  bool supports(CountryProfile country) => true;

  @override
  Future<List<RoadEvent>> load() async => throw StateError('upstream failed');
}

void main() {
  test('NZ profile selects live provider; AU stays unsupported', () async {
    final provider = CountingProvider();
    final registry = RoadEventProviderRegistry([provider]);
    expect((await registry.load(CountryProfiles.nz)).length, 1);
    expect(await registry.load(CountryProfiles.au), isEmpty);
    expect(provider.calls, 1);
    expect(CountryProfiles.at(const GeoPoint(-36.85, 174.76))?.code, 'NZ');
    expect(CountryProfiles.at(const GeoPoint(-33.87, 151.21))?.code, 'AU');
  });

  test('route corridor keeps events ahead on route and removes stale data', () {
    final now = DateTime.utc(2026, 9, 26);
    final engine = RoadIntelligenceEngine();
    final results = engine.relevant(
      driver: const GeoPoint(0, .001),
      route: eastRoute(),
      now: now,
      events: [
        camera('ahead', const GeoPoint(0, .005)),
        camera('parallel', const GeoPoint(.001, .005)),
        camera('behind', const GeoPoint(0, 0)),
        camera(
          'stale',
          const GeoPoint(0, .006),
          until: now.subtract(const Duration(minutes: 1)),
        ),
        camera('ahead', const GeoPoint(0, .005)),
      ],
    );
    expect(results.map((event) => event.id), ['ahead']);
    expect(results.single.distanceAlongRoute, greaterThan(400));
  });

  test('Just Drive needs heading and excludes lateral roads', () {
    const engine = RoadIntelligenceEngine();
    final events = [
      camera('ahead', const GeoPoint(0, .005)),
      camera('side', const GeoPoint(.001, .005)),
    ];
    expect(
      engine.relevant(driver: const GeoPoint(0, 0), events: events),
      isEmpty,
    );
    final results = engine.relevant(
      driver: const GeoPoint(0, 0),
      headingDegrees: 90,
      events: events,
    );
    expect(results.map((event) => event.id), ['ahead']);
  });

  test('provider registry keeps partial road intelligence when one provider fails', () async {
    final registry = RoadEventProviderRegistry([
      CountingProvider(),
      FailingProvider(),
    ]);
    final events = await registry.load(CountryProfiles.nz);
    expect(events, hasLength(1));
    expect(registry.lastErrors, hasLength(1));
  });

  test('long road-event geometry matches near the driver even when midpoint is far away', () {
    const engine = RoadIntelligenceEngine(maxDistanceMeters: 1500);
    final event = RoadEvent(
      id: 'works',
      type: RoadEventType.roadworks,
      location: const GeoPoint(0, .05),
      geometry: const [
        GeoPoint(0, .005),
        GeoPoint(0, .02),
        GeoPoint(0, .05),
      ],
      source: const RoadEventSource(
        provider: 'test',
        country: 'NZ',
        sourceId: 'works',
      ),
    );
    final results = engine.relevant(
      driver: const GeoPoint(0, 0),
      headingDegrees: 90,
      events: [event],
    );
    expect(results.map((item) => item.id), ['works']);
    expect(results.single.distanceFromDriver, lessThan(600));
  });

}
