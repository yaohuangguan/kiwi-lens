import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../data/camera_repository.dart';
import '../data/speed_limit_repository.dart';
import '../domain/geo_math.dart';
import '../domain/route_option.dart';
import '../domain/safety_camera.dart';
import 'camera_matcher.dart';
import 'route_camera_matcher.dart';
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
  final RouteCameraMatcher _routeMatcher = const RouteCameraMatcher();

  List<SafetyCamera> _cameras = const [];
  RouteOption? _route;
  List<RouteCameraMatch> routeCameras = const [];
  List<SafetyCamera> get cameras => _cameras;
  int get routeCameraCount => routeCameras.length;
  LatLng? get snappedLocation => _lastSnappedLocation;
  LatLng? _lastSnappedLocation;
  LatLng? _lastSpeedLimitLocation;
  DateTime? _lastSpeedLimitLookup;
  bool _speedLimitLookupPending = false;
  double? _headingDegrees;
  Completer<void>? _roadSnappedFixCompleter;

  bool active = false;
  bool guidanceRunning = false;
  bool loadingCameras = false;
  double speedKph = 0;
  int? speedLimitKph;
  bool voiceEnabled = true;

  Future<void> setVoiceLanguage(String language) =>
      _voiceEngine.setLanguage(language);
  String? speedLimitZoneName;
  SpeedAlertSeverity speedSeverity = SpeedAlertSeverity.notSpeeding;
  double? percentageAboveLimit;
  SafetyCamera? upcomingCamera;
  double? upcomingCameraDistanceMeters;
  NavInfo? navInfo;
  String? error;

  Future<void> start() async {
    if (active) return;
    _roadSnappedFixCompleter = Completer<void>();
    active = true;
    error = null;
    notifyListeners();

    await _voiceEngine.initialize();
    await loadCameras(force: true);

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

  Future<void> loadCameras({bool force = false}) async {
    if (loadingCameras || (!force && _cameras.isNotEmpty)) return;
    loadingCameras = true;
    notifyListeners();
    try {
      _cameras = await _cameraRepository.fetchCameras();
      _recomputeRouteCameras();
      error = null;
    } catch (exception) {
      error = 'Could not load safety cameras: $exception';
    } finally {
      loadingCameras = false;
      notifyListeners();
    }
  }

  void setRoute(RouteOption? route) {
    _route = route;
    _spokenAlerts.clear();
    _recomputeRouteCameras();
    upcomingCamera = null;
    upcomingCameraDistanceMeters = null;
    notifyListeners();
  }

  void _recomputeRouteCameras() {
    routeCameras = _route == null
        ? const []
        : _routeMatcher.match(_route!, _cameras);
  }

  void _onRoadSnappedLocation(RoadSnappedLocationUpdatedEvent event) {
    final current = event.location;
    final fix = _roadSnappedFixCompleter;
    if (fix != null && !fix.isCompleted) fix.complete();
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

    CameraMatch? match;
    final route = _route;
    if (route != null) {
      final upcoming = _routeMatcher.upcoming(
        current,
        route.points,
        routeCameras,
      );
      final progress = _routeMatcher.project(current, route.points);
      if (upcoming != null && progress != null) {
        match = CameraMatch(
          camera: upcoming.camera,
          distanceMeters: (upcoming.alongMeters - progress.alongMeters).clamp(
            0,
            1200,
          ),
        );
      }
    } else {
      match = _cameraMatcher.findUpcoming(
        latitude: current.latitude,
        longitude: current.longitude,
        cameras: _cameras,
        headingDegrees: _headingDegrees,
      );
    }

    upcomingCamera = match?.camera;
    upcomingCameraDistanceMeters = match?.distanceMeters;

    if (match != null) {
      unawaited(_maybeAlert(match));
    }

    notifyListeners();
  }

  Future<bool> waitForRoadSnappedLocation({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_lastSnappedLocation != null) return true;
    final fix = _roadSnappedFixCompleter ??= Completer<void>();
    try {
      await fix.future.timeout(timeout);
      return _lastSnappedLocation != null;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> speakMessage(String message) async {
    if (!voiceEnabled) return;
    await _voiceEngine.guidance(message);
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
    if (!voiceEnabled) return;
    final distance = match.distanceMeters;
    if (distance <= 0) return;
    final threshold = distance <= 300
        ? 300
        : distance <= 800
        ? 800
        : null;
    if (threshold == null) return;
    if (threshold == 300) {
      _spokenAlerts.add('${match.camera.id}:800');
    }
    final key = '${match.camera.id}:$threshold';
    if (!_spokenAlerts.add(key)) return;
    await _voiceEngine.cameraAlert(
      distanceMeters: threshold,
      cameraType: match.camera.type,
      roadName: match.camera.location,
      speedLimit: speedLimitKph?.toString(),
    );
  }

  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _spokenAlerts.clear();
    _route = null;
    routeCameras = const [];
    active = false;
    guidanceRunning = false;
    upcomingCamera = null;
    upcomingCameraDistanceMeters = null;
    navInfo = null;
    speedKph = 0;
    speedLimitKph = null;
    speedLimitZoneName = null;
    _lastSpeedLimitLocation = null;
    _lastSnappedLocation = null;
    _roadSnappedFixCompleter = null;
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
