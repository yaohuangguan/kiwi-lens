import 'dart:math' as math;

import 'package:google_navigation_flutter/google_navigation_flutter.dart';

const radarRangeMeters = 500.0;
const _earthRadiusMeters = 6371008.8;

LatLng pointAtDistance(LatLng origin, double bearingDegrees, double distanceMeters) {
  final latitude = origin.latitude * math.pi / 180;
  final longitude = origin.longitude * math.pi / 180;
  final bearing = bearingDegrees * math.pi / 180;
  final arc = distanceMeters / _earthRadiusMeters;
  final nextLatitude = math.asin(
    math.sin(latitude) * math.cos(arc) +
        math.cos(latitude) * math.sin(arc) * math.cos(bearing),
  );
  final nextLongitude = longitude + math.atan2(
    math.sin(bearing) * math.sin(arc) * math.cos(latitude),
    math.cos(arc) - math.sin(latitude) * math.sin(nextLatitude),
  );
  return LatLng(
    latitude: nextLatitude * 180 / math.pi,
    longitude: nextLongitude * 180 / math.pi,
  );
}

List<LatLng> radarSector(LatLng origin, double headingDegrees, {double rangeMeters = radarRangeMeters}) {
  return [
    origin,
    for (var offset = -34; offset <= 34; offset += 4)
      pointAtDistance(origin, headingDegrees + offset, rangeMeters),
  ];
}
