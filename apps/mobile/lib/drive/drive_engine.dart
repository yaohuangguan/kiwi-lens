import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../data/camera_repository.dart';
import '../data/speed_limit_repository.dart';
import '../domain/geo_math.dart';
import '../domain/safety_camera.dart';
import 'camera_matcher.dart';
import 'voice_engine.dart';

class DriveEngine extends ChangeNotifier {
  DriveEngine({
    CameraRepository? cameraRepository,
    CameraMatcher? cameraMatcher,
    VoiceEngine? voiceEngine,
    SpeedLimitRepository? speedLimitRepository,
  }) : _cameraRepository = cameraRepository ?? CameraRepository(),
       _cameraMatcher = cameraMatcher ?? const CameraMatcher(),
       _voiceEngine = voiceEngine ?? VoiceEngine(),
       _speedLimitRepository = speedLimitRepository ?? SpeedLimitRepository();

  final CameraRepository _cameraRepository;
  final CameraMatcher _cameraMatcher;
  final VoiceEngine _voiceEngine;
  final SpeedLimitRepository _speedLimitRepository;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<String> _spokenAlerts = <String>{};

  List<SafetyCamera> _cameras = const [];
  LatLng? _lastSnappedLocation;
  LatLng? _lastSpeedLimitLocation;
  DateTime? _lastSpeedLimitLookup;
  bool _speedLimitLookupPending = false;
  double? _headingDegrees;

  bool active = false;
  bool guidanceRunning = false;
  bool loadingCameras = false;
  double speedKph = 0;
  int? speedLimitKph;
  String? speedLimitZoneName;
  SpeedAlertSeverity speedSeverity = SpeedAlertSeverity.notSpeeding;
  double? percentageAboveLimit;
  SafetyCamera? upcomingCamera;
  double? upcomingCameraDistanceMeters;
  NavInfo? navInfo;
  String? error;

  Future<void> start() async {
    if (active) return;
    active = true;
    error = null;
    notifyListeners();

    await _voiceEngine.initialize();
    await _loadCameras();

    final snapped =
        await GoogleMapsNavigator.setRoadSnappedLocationUpdatedListener(
          _onRoadSnappedLocation,
        );
    _subscriptions.add(snapped);

    _subscriptions.add(
      GoogleMapsNavigator.setSpeedingUpdatedListener((event) {
        speedSeverity = event.severity;
        percentageAboveLimit = event.percentageAboveLimit;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      GoogleMapsNavigator.setNavInfoListener((event) {
        navInfo = event.navInfo;
        guidanceRunning =
            event.navInfo.navState == NavState.enroute ||
            event.navInfo.navState == NavState.rerouting;
        notifyListeners();
      }, numNextStepsToPreview: 3),
    );

    _subscriptions.add(
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        ),
      ).listen((position) {
        final metresPerSecond = position.speed.isFinite && position.speed > 0
            ? position.speed
            : 0;
        speedKph = metresPerSecond * 3.6;
        notifyListeners();
      }),
    );
  }

  Future<void> _loadCameras() async {
    loadingCameras = true;
    notifyListeners();
    try {
      _cameras = await _cameraRepository.fetchCameras();
    } catch (exception) {
      error = 'Could not load safety cameras: $exception';
    } finally {
      loadingCameras = false;
      notifyListeners();
    }
  }

  void _onRoadSnappedLocation(RoadSnappedLocationUpdatedEvent event) {
    final current = event.location;
    final previous = _lastSnappedLocation;

    if (previous != null) {
      final travelled = distanceMeters(
        previous.latitude,
        previous.longitude,
        current.latitude,
        current.longitude,
      );
      if (travelled >= 8) {
        _headingDegrees = bearingDegrees(
          previous.latitude,
          previous.longitude,
          current.latitude,
          current.longitude,
        );
      }
    }

    _lastSnappedLocation = current;
    unawaited(_refreshSpeedLimit(current));

    final match = _cameraMatcher.findUpcoming(
      latitude: current.latitude,
      longitude: current.longitude,
      cameras: _cameras,
      headingDegrees: _headingDegrees,
    );

    upcomingCamera = match?.camera;
    upcomingCameraDistanceMeters = match?.distanceMeters;

    if (match != null) {
      unawaited(_maybeAlert(match));
    }

    notifyListeners();
  }

  Future<void> _refreshSpeedLimit(LatLng current) async {
    if (_speedLimitLookupPending) return;
    final now = DateTime.now();
    final last = _lastSpeedLimitLocation;
    final moved = last == null
        ? double.infinity
        : distanceMeters(
            last.latitude,
            last.longitude,
            current.latitude,
            current.longitude,
          );
    final recent =
        _lastSpeedLimitLookup != null &&
        now.difference(_lastSpeedLimitLookup!).inSeconds < 15;
    if (recent && moved < 75) return;

    _speedLimitLookupPending = true;
    _lastSpeedLimitLookup = now;
    _lastSpeedLimitLocation = current;
    try {
      final info = await _speedLimitRepository.fetch(
        latitude: current.latitude,
        longitude: current.longitude,
      );
      speedLimitKph = info.speedLimitKph;
      speedLimitZoneName = info.zoneName;
      notifyListeners();
    } catch (_) {
      // Retain the last known legal limit during short network interruptions.
    } finally {
      _speedLimitLookupPending = false;
    }
  }

  Future<void> _maybeAlert(CameraMatch match) async {
    final distance = match.distanceMeters;

    if (distance <= 150) {
      final key = '${match.camera.id}:150';
      if (_spokenAlerts.add(key)) {
        _spokenAlerts.add('${match.camera.id}:500');
        await _voiceEngine.cameraAlert(
          distanceMeters: 150,
          cameraType: match.camera.type,
        );
      }
      return;
    }

    if (distance <= 500) {
      final key = '${match.camera.id}:500';
      if (_spokenAlerts.add(key)) {
        await _voiceEngine.cameraAlert(
          distanceMeters: 500,
          cameraType: match.camera.type,
        );
      }
    }
  }

  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _spokenAlerts.clear();
    active = false;
    guidanceRunning = false;
    upcomingCamera = null;
    upcomingCameraDistanceMeters = null;
    navInfo = null;
    speedKph = 0;
    speedLimitKph = null;
    speedLimitZoneName = null;
    _lastSpeedLimitLocation = null;
    _lastSpeedLimitLookup = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_voiceEngine.dispose());
    super.dispose();
  }
}
