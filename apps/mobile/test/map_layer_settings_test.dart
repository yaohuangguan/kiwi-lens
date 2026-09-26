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
  test('NZTA fixed camera categories stay distinct', () {
    expect(CameraKindLabel.fromCamera(camera('Spot speed')), CameraKind.spotSpeed);
    expect(CameraKindLabel.fromCamera(camera('Average speed')), CameraKind.averageSpeed);
    expect(CameraKindLabel.fromCamera(camera('Red light')), CameraKind.redLight);
    expect(
      CameraKindLabel.fromCamera(camera('Dual red light or speed')),
      CameraKind.dualRedLightSpeed,
    );
    expect(CameraKindLabel.fromCamera(camera('Future camera')), CameraKind.other);
  });

  test('visibility and alert switches are independent', () {
    const settings = MapLayerSettings();
    final next = settings.copyWith(spotSpeed: false, alertSpotSpeed: true);
    expect(next.shows(camera('Spot speed')), false);
    expect(next.alerts(camera('Spot speed')), true);
    expect(next.shows(camera('Average speed')), true);
    expect(next.copyWith(cameras: false).shows(camera('Red light')), false);
  });
}
