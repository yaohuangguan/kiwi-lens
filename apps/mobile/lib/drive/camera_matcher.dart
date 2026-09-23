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
  });

  final double maxDistanceMeters;
  final double maxHeadingDifferenceDegrees;

  CameraMatch? findUpcoming({
    required double latitude,
    required double longitude,
    required List<SafetyCamera> cameras,
    double? headingDegrees,
  }) {
    CameraMatch? best;

    for (final camera in cameras) {
      final distance = distanceMeters(
        latitude,
        longitude,
        camera.latitude,
        camera.longitude,
      );
      if (distance > maxDistanceMeters) continue;

      if (headingDegrees != null && distance > 80) {
        final cameraBearing = bearingDegrees(
          latitude,
          longitude,
          camera.latitude,
          camera.longitude,
        );
        if (angleDifference(headingDegrees, cameraBearing) >
            maxHeadingDifferenceDegrees) {
          continue;
        }
      }

      if (best == null || distance < best.distanceMeters) {
        best = CameraMatch(camera: camera, distanceMeters: distance);
      }
    }

    return best;
  }
}
