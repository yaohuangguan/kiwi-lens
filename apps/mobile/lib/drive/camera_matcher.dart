import 'dart:math' as math;

import '../domain/geo_math.dart';
import '../domain/safety_camera.dart';

class CameraMatch {
  const CameraMatch({required this.camera, required this.distanceMeters});

  final SafetyCamera camera;
  final double distanceMeters;
}

class CameraMatcher {
  const CameraMatcher({
    this.maxDistanceMeters = 1200,
    this.maxHeadingDifferenceDegrees = 35,
    this.maxLateralDistanceMeters = 32,
  });

  final double maxDistanceMeters;
  final double maxHeadingDifferenceDegrees;
  final double maxLateralDistanceMeters;

  CameraMatch? findUpcoming({
    required double latitude,
    required double longitude,
    required List<SafetyCamera> cameras,
    double? headingDegrees,
  }) {
    // Without a travel heading a nearby camera could be on any road.
    if (headingDegrees == null) return null;
    CameraMatch? best;

    for (final camera in cameras) {
      final distance = distanceMeters(
        latitude,
        longitude,
        camera.latitude,
        camera.longitude,
      );
      if (distance > maxDistanceMeters) continue;

      final cameraBearing = bearingDegrees(
        latitude,
        longitude,
        camera.latitude,
        camera.longitude,
      );
      final difference = angleDifference(headingDegrees, cameraBearing);
      if (difference > maxHeadingDifferenceDegrees) continue;
      if (distance * math.sin(difference * math.pi / 180) >
          maxLateralDistanceMeters) {
        continue;
      }
      if (!_directionMatches(camera.location, headingDegrees)) continue;

      if (best == null || distance < best.distanceMeters) {
        best = CameraMatch(camera: camera, distanceMeters: distance);
      }
    }

    return best;
  }

  bool _directionMatches(String location, double heading) {
    final value = location.toLowerCase();
    double? direction;
    if (RegExp(r'\b(nb|northbound)\b').hasMatch(value)) direction = 0;
    if (RegExp(r'\b(eb|eastbound)\b').hasMatch(value)) direction = 90;
    if (RegExp(r'\b(sb|southbound)\b').hasMatch(value)) direction = 180;
    if (RegExp(r'\b(wb|westbound)\b').hasMatch(value)) direction = 270;
    return direction == null || angleDifference(direction, heading) <= 55;
  }
}
