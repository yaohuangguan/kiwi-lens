import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/domain/safety_camera.dart';
import 'package:kiwi_lens_mobile/drive/camera_matcher.dart';

void main() {
  const matcher = CameraMatcher();
  const ahead = SafetyCamera(
    id: 'ahead',
    name: 'Ahead camera',
    region: 'Auckland',
    suburb: 'City',
    location: 'Queen Street',
    type: 'Spot speed',
    latitude: -36.8440,
    longitude: 174.7633,
  );
  const behind = SafetyCamera(
    id: 'behind',
    name: 'Behind camera',
    region: 'Auckland',
    suburb: 'City',
    location: 'Queen Street',
    type: 'Spot speed',
    latitude: -36.8530,
    longitude: 174.7633,
  );

  const adjacent = SafetyCamera(
    id: 'adjacent',
    name: 'Parallel road camera',
    region: 'Auckland',
    suburb: 'City',
    location: 'Parallel Road NB',
    type: 'Spot speed',
    latitude: -36.8440,
    longitude: 174.7640,
  );
  const opposite = SafetyCamera(
    id: 'opposite',
    name: 'Opposite direction',
    region: 'Auckland',
    suburb: 'City',
    location: 'Queen Street SB',
    type: 'Spot speed',
    latitude: -36.8440,
    longitude: 174.7633,
  );

  test('prefers a camera ahead of the driving heading', () {
    final match = matcher.findUpcoming(
      latitude: -36.8485,
      longitude: 174.7633,
      cameras: const [behind, ahead],
      headingDegrees: 0,
    );

    expect(match?.camera.id, 'ahead');
  });

  test('ignores adjacent and opposite-direction cameras', () {
    final match = matcher.findUpcoming(
      latitude: -36.8485,
      longitude: 174.7633,
      cameras: const [adjacent, opposite, ahead],
      headingDegrees: 0,
    );
    expect(match?.camera.id, 'ahead');
  });

  test('waits for travel heading before any Drive Mode alert', () {
    expect(
      matcher.findUpcoming(
        latitude: -36.8485,
        longitude: 174.7633,
        cameras: const [ahead],
      ),
      isNull,
    );
  });

  test('does not report cameras outside the forward cone', () {
    final match = matcher.findUpcoming(
      latitude: -36.8485,
      longitude: 174.7633,
      cameras: const [ahead],
      headingDegrees: 180,
    );

    expect(match, isNull);
  });
}
