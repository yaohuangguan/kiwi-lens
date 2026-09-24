import 'safety_camera.dart';

enum CameraKind { speed, redLight, lane, other }

extension CameraKindLabel on CameraKind {
  String get label => switch (this) {
    CameraKind.speed => 'Speed cameras',
    CameraKind.redLight => 'Red-light cameras',
    CameraKind.lane => 'Lane cameras',
    CameraKind.other => 'Other cameras',
  };

  static CameraKind fromCamera(SafetyCamera camera) {
    final type = camera.type.toLowerCase();
    if (type.contains('red light')) return CameraKind.redLight;
    if (type.contains('lane') || type.contains('bus')) return CameraKind.lane;
    if (type.contains('speed')) return CameraKind.speed;
    return CameraKind.other;
  }
}

enum BaseMapStyle { standard, satellite, terrain, hybrid }

class MapLayerSettings {
  const MapLayerSettings({
    this.cameras = true,
    this.speed = true,
    this.redLight = true,
    this.lane = true,
    this.other = true,
    this.traffic = true,
    this.style = BaseMapStyle.standard,
  });

  final bool cameras;
  final bool speed;
  final bool redLight;
  final bool lane;
  final bool other;
  final bool traffic;
  final BaseMapStyle style;

  bool shows(SafetyCamera camera) {
    if (!cameras) return false;
    return switch (CameraKindLabel.fromCamera(camera)) {
      CameraKind.speed => speed,
      CameraKind.redLight => redLight,
      CameraKind.lane => lane,
      CameraKind.other => other,
    };
  }

  String get markerSignature => '$cameras:$speed:$redLight:$lane:$other';

  MapLayerSettings copyWith({
    bool? cameras,
    bool? speed,
    bool? redLight,
    bool? lane,
    bool? other,
    bool? traffic,
    BaseMapStyle? style,
  }) => MapLayerSettings(
    cameras: cameras ?? this.cameras,
    speed: speed ?? this.speed,
    redLight: redLight ?? this.redLight,
    lane: lane ?? this.lane,
    other: other ?? this.other,
    traffic: traffic ?? this.traffic,
    style: style ?? this.style,
  );
}
