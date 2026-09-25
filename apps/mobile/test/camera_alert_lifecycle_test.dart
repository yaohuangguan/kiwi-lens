import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/domain/safety_camera.dart';
import 'package:kiwi_lens_mobile/drive/camera_alert_lifecycle.dart';
import 'package:kiwi_lens_mobile/drive/camera_matcher.dart';

const camera = SafetyCamera(
  id: 'camera-1',
  name: 'Test camera',
  region: 'Auckland',
  suburb: 'Test',
  location: 'Test Road',
  type: 'Spot speed',
  latitude: -36.85,
  longitude: 174.76,
);

void main() {
  test('camera alerts pass once and obey cooldown', () {
    final lifecycle = CameraAlertLifecycle();
    final start = DateTime.utc(2026, 9, 26, 12);
    expect(
      lifecycle
          .update(const CameraMatch(camera: camera, distanceMeters: 180), start)
          .phase,
      CameraAlertPhase.approaching,
    );
    lifecycle.update(
      const CameraMatch(camera: camera, distanceMeters: 60),
      start.add(const Duration(seconds: 10)),
    );
    final passed = lifecycle.update(
      null,
      start.add(const Duration(seconds: 12)),
    );
    expect(passed.phase, CameraAlertPhase.passed);
    expect(passed.cameraId, camera.id);
    expect(
      lifecycle
          .update(
            const CameraMatch(camera: camera, distanceMeters: 80),
            start.add(const Duration(seconds: 14)),
          )
          .phase,
      CameraAlertPhase.passed,
    );
    expect(
      lifecycle.update(null, start.add(const Duration(seconds: 21))).phase,
      CameraAlertPhase.idle,
    );
    expect(
      lifecycle
          .update(
            const CameraMatch(camera: camera, distanceMeters: 500),
            start.add(const Duration(minutes: 6)),
          )
          .phase,
      CameraAlertPhase.approaching,
    );
  });

  test('losing a distant camera does not claim it was passed', () {
    final lifecycle = CameraAlertLifecycle();
    final start = DateTime.utc(2026, 9, 26, 12);
    lifecycle.update(
      const CameraMatch(camera: camera, distanceMeters: 400),
      start,
    );
    expect(
      lifecycle.update(null, start.add(const Duration(seconds: 2))).phase,
      CameraAlertPhase.idle,
    );
  });
}
