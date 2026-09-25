import 'camera_matcher.dart';

enum CameraAlertPhase { idle, approaching, passed }

class CameraAlertState {
  const CameraAlertState(this.phase, {this.cameraId, this.distanceMeters});
  const CameraAlertState.idle()
    : phase = CameraAlertPhase.idle,
      cameraId = null,
      distanceMeters = null;

  final CameraAlertPhase phase;
  final String? cameraId;
  final double? distanceMeters;
}

/// Tracks one camera at a time and suppresses repeated alerts after passage.
class CameraAlertLifecycle {
  CameraAlertLifecycle({
    this.passDistanceMeters = 120,
    this.passedDisplay = const Duration(seconds: 8),
    this.cooldown = const Duration(minutes: 5),
  });

  final double passDistanceMeters;
  final Duration passedDisplay;
  final Duration cooldown;
  final Map<String, DateTime> _completedAt = {};
  String? _trackingId;
  double? _lastDistance;
  DateTime? _passedAt;
  String? _passedId;

  CameraAlertState update(CameraMatch? match, DateTime now) {
    _completedAt.removeWhere((_, at) => now.difference(at) >= cooldown);
    if (_trackingId != null &&
        (match == null || match.camera.id != _trackingId)) {
      if (_lastDistance != null && _lastDistance! <= passDistanceMeters) {
        _completedAt[_trackingId!] = now;
        _passedId = _trackingId;
        _passedAt = now;
      }
      _trackingId = null;
      _lastDistance = null;
    }
    if (_passedAt != null && now.difference(_passedAt!) >= passedDisplay) {
      _passedAt = null;
      _passedId = null;
    }
    if (match != null && !_completedAt.containsKey(match.camera.id)) {
      _trackingId = match.camera.id;
      _lastDistance = match.distanceMeters;
      _passedAt = null;
      _passedId = null;
      return CameraAlertState(
        CameraAlertPhase.approaching,
        cameraId: match.camera.id,
        distanceMeters: match.distanceMeters,
      );
    }
    if (_passedId != null) {
      return CameraAlertState(CameraAlertPhase.passed, cameraId: _passedId);
    }
    return const CameraAlertState.idle();
  }

  void reset() {
    _trackingId = null;
    _lastDistance = null;
    _passedAt = null;
    _passedId = null;
    _completedAt.clear();
  }
}
