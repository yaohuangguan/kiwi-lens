import 'dart:math' as math;

import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../domain/geo_math.dart';
import '../domain/route_option.dart';
import '../domain/safety_camera.dart';

class RouteProjection {
  const RouteProjection({
    required this.alongMeters,
    required this.offsetMeters,
    required this.bearingDegrees,
  });
  final double alongMeters;
  final double offsetMeters;
  final double bearingDegrees;
}

class RouteCameraMatch {
  const RouteCameraMatch({
    required this.camera,
    required this.alongMeters,
    required this.offsetMeters,
    required this.highConfidence,
  });
  final SafetyCamera camera;
  final double alongMeters;
  final double offsetMeters;
  final bool highConfidence;
}

/// A narrow route corridor limits alerts from adjacent roads. Only
/// high-confidence matches can trigger automatic speech.
class RouteCameraMatcher {
  const RouteCameraMatcher();

  RouteProjection? project(LatLng point, List<LatLng> route) {
    if (route.length < 2) return null;
    RouteProjection? best;
    var travelled = 0.0;
    for (var index = 0; index < route.length - 1; index++) {
      final start = route[index];
      final end = route[index + 1];
      final latitudeRadians = (start.latitude + end.latitude) * math.pi / 360;
      final metresPerLongitude = 111320 * math.cos(latitudeRadians);
      const metresPerLatitude = 110540.0;
      final x = (point.longitude - start.longitude) * metresPerLongitude;
      final y = (point.latitude - start.latitude) * metresPerLatitude;
      final dx = (end.longitude - start.longitude) * metresPerLongitude;
      final dy = (end.latitude - start.latitude) * metresPerLatitude;
      final lengthSquared = dx * dx + dy * dy;
      final fraction = lengthSquared == 0
          ? 0.0
          : ((x * dx + y * dy) / lengthSquared).clamp(0.0, 1.0);
      final offset = math.sqrt(
        math.pow(x - fraction * dx, 2) + math.pow(y - fraction * dy, 2),
      );
      final segmentLength = distanceMeters(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      if (best == null || offset < best.offsetMeters) {
        best = RouteProjection(
          alongMeters: travelled + segmentLength * fraction,
          offsetMeters: offset,
          bearingDegrees: bearingDegrees(
            start.latitude,
            start.longitude,
            end.latitude,
            end.longitude,
          ),
        );
      }
      travelled += segmentLength;
    }
    return best;
  }

  List<RouteCameraMatch> match(RouteOption route, List<SafetyCamera> cameras) {
    if (route.points.length < 2 || cameras.isEmpty) return const [];
    final stepPositions = [
      for (final step in route.steps)
        (
          instruction: step.instruction,
          projection: project(step.location, route.points),
        ),
    ];
    final matches = <RouteCameraMatch>[];
    for (final camera in cameras) {
      final projection = project(
        LatLng(latitude: camera.latitude, longitude: camera.longitude),
        route.points,
      );
      if (projection == null ||
          !_directionMatches(camera.location, projection.bearingDegrees)) {
        continue;
      }
      final sameRoad = stepPositions.any(
        (step) =>
            step.projection != null &&
            (step.projection!.alongMeters - projection.alongMeters).abs() <
                300 &&
            _roadMatches(camera.location, step.instruction),
      );
      final isRedLight = camera.type.toLowerCase().contains('red light');
      final maxOffset = sameRoad
          ? 65.0
          : isRedLight
          ? 18.0
          : 28.0;
      if (projection.offsetMeters > maxOffset) continue;
      matches.add(
        RouteCameraMatch(
          camera: camera,
          alongMeters: projection.alongMeters,
          offsetMeters: projection.offsetMeters,
          highConfidence:
              projection.offsetMeters <= 18 ||
              (sameRoad && projection.offsetMeters <= 40),
        ),
      );
    }
    matches.sort((a, b) => a.alongMeters.compareTo(b.alongMeters));
    return matches;
  }

  RouteCameraMatch? upcoming(
    LatLng position,
    List<LatLng> route,
    List<RouteCameraMatch> matches,
  ) {
    final progress = project(position, route);
    if (progress == null || progress.offsetMeters > 100) return null;
    for (final match in matches) {
      final ahead = match.alongMeters - progress.alongMeters;
      if (match.highConfidence && ahead >= -15 && ahead <= 1200) return match;
    }
    return null;
  }

  bool _directionMatches(String location, double routeBearing) {
    final value = location.toLowerCase();
    double? bearing;
    if (RegExp(r'\b(nb|northbound)\b').hasMatch(value)) bearing = 0;
    if (RegExp(r'\b(eb|eastbound)\b').hasMatch(value)) bearing = 90;
    if (RegExp(r'\b(sb|southbound)\b').hasMatch(value)) bearing = 180;
    if (RegExp(r'\b(wb|westbound)\b').hasMatch(value)) bearing = 270;
    return bearing == null || angleDifference(bearing, routeBearing) <= 55;
  }

  bool _roadMatches(String cameraLocation, String instruction) {
    final cameraRoad = _normalise(
      cameraLocation.split(RegExp(r'\band\b|/')).first,
    );
    return cameraRoad.length >= 3 &&
        _normalise(instruction).contains(cameraRoad);
  }

  String _normalise(String value) => value
      .toLowerCase()
      .replaceAllMapped(
        RegExp(r'state highway\s*(\d+)'),
        (match) => 'sh${match.group(1) ?? ''}',
      )
      .replaceAll(
        RegExp(
          r'\b(road|rd|street|st|avenue|ave|drive|dr|lane|ln|camera|northbound|southbound|eastbound|westbound|nb|sb|eb|wb)\b',
        ),
        '',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}
