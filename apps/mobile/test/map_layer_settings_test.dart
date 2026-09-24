import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/domain/map_layer_settings.dart';
import 'package:kiwi_lens_mobile/domain/safety_camera.dart';

SafetyCamera camera(String type) => SafetyCamera(
  id: type,
  name: type,
  region: 'Auckland',
  suburb: 'City',
  location: 'Queen Street',
  type: type,
  latitude: -36.85,
  longitude: 174.76,
);

void main() {
  test(
    'NZTA camera categories are distinct and future lane data is supported',
    () {
      expect(
        CameraKindLabel.fromCamera(camera('Spot speed')),
        CameraKind.speed,
      );
      expect(
        CameraKindLabel.fromCamera(camera('Average speed')),
        CameraKind.speed,
      );
      expect(
        CameraKindLabel.fromCamera(camera('Red light')),
        CameraKind.redLight,
      );
      expect(CameraKindLabel.fromCamera(camera('Bus lane')), CameraKind.lane);
    },
  );

  test('layer switches only affect matching camera classes', () {
    const settings = MapLayerSettings();
    final withoutSpeed = settings.copyWith(speed: false);
    expect(withoutSpeed.shows(camera('Spot speed')), false);
    expect(withoutSpeed.shows(camera('Red light')), true);
    expect(
      withoutSpeed.copyWith(cameras: false).shows(camera('Red light')),
      false,
    );
  });
}
