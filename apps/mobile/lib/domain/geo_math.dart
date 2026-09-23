import 'dart:math' as math;

const _earthRadiusMeters = 6371008.8;

double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * _earthRadiusMeters * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final y = math.sin(dLon) * math.cos(p2);
  final x =
      math.cos(p1) * math.sin(p2) -
      math.sin(p1) * math.cos(p2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

double angleDifference(double a, double b) {
  return ((a - b + 540) % 360 - 180).abs();
}
