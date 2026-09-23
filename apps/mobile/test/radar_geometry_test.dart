import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:kiwi_lens_mobile/domain/geo_math.dart';
import 'package:kiwi_lens_mobile/domain/radar_geometry.dart';

void main() {
  const origin = LatLng(latitude: -36.8485, longitude: 174.7633);

  test('radar sector has a 500 metre range in the chosen direction', () {
    final points = radarSector(origin, 0);
    expect(points, hasLength(19));
    expect(points.first.latitude, origin.latitude);
    expect(points.first.longitude, origin.longitude);
    for (final point in points.skip(1)) {
      expect(distanceMeters(origin.latitude, origin.longitude,
          point.latitude, point.longitude), closeTo(500, 0.1));
      expect(point.latitude, greaterThan(origin.latitude));
    }
  });

  test('the sector rotates east with device heading', () {
    final points = radarSector(origin, 90);
    for (final point in points.skip(1)) {
      expect(point.longitude, greaterThan(origin.longitude));
    }
  });
}
