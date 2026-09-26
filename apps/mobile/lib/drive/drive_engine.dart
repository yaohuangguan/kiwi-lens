import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../data/camera_repository.dart';
import '../data/nzta_road_event_provider.dart';
import '../data/nzta_traffic_road_event_provider.dart';
import '../data/speed_limit_repository.dart';
import '../domain/country_profile.dart';
import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/road_event.dart';
import '../domain/road_intelligence.dart';
import '../domain/route_option.dart';
import '../domain/safety_camera.dart';
import 'camera_alert_lifecycle.dart';
import 'camera_matcher.dart';
import 'route_camera_matcher.dart';
import 'voice_engine.dart';

class DriveEngine extends ChangeNotifier {
  DriveEngine({
    CameraRepository? cameraRepository,
    CameraMatcher? cameraMatcher,
    VoiceEngine? voiceEngine,
    SpeedLimitRepository? speedLimitRepository,
    RoadIntelligenceEngine? roadIntelligence,
    CameraAlertLifecycle? cameraLifecycle,
  }) : _cameraMatcher = cameraMatcher ?? const CameraMatcher(),
       _voiceEngine = voiceEngine ?? VoiceEngine(),
       _speedLimitRepository = speedLimitRepository ?? SpeedLimitRepository(),
       _roadIntelligence = roadIntelligence ?? RoadIntelligenceEngine(),
       _cameraLifecycle = cameraLifecycle ?? CameraAlertLifecycle() {
    _nztaProvider = NztaRoadEventProvider(
      cameraRepository ?? CameraRepository(),
    );
    _trafficProvider = NztaTrafficRoadEventProvider();
    _providerRegistry = RoadEventProviderRegistry([_nztaProvider, _trafficProvider]);
  }

  final CameraMatcher _cameraMatcher;
  final VoiceEngine _voiceEngine;
  final SpeedLimitRepository _speedLimitRepository;
  final RoadIntelligenceEngine _roadIntelligence;
  final CameraAlertLifecycle _cameraLifecycle;
  late final NztaRoadEventProvider _nztaProvider;
  late final NztaTrafficRoadEventProvider _trafficProvider;
  late final RoadEventProviderRegistry _providerRegistry;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _roadIntelligenceRefreshTimer;
  final Set<String> _spokenAlerts = <String>{};
  final RouteCameraMatcher _routeMatcher = const RouteCameraMatcher();

  List<SafetyCamera> _cameras = const [];
  RouteOption? _route;
  Set<String> _highConfidenceCameraIds = const {};
  List<RouteCameraMatch> routeCameras = const [];
  List<SafetyCamera> get cameras => _cameras;
  List<RoadEvent> roadEvents = const [];
  List<RoadEvent> upcomingRoadEvents = const [];
  String roadIntelligenceStatus = 'not_loaded';
  bool get roadIntelligenceStale => roadIntelligenceStatus == 'stale';
  int get routeCameraCount => routeCameras.length;
  LatLng? get snappedLocation => _lastSnappedLocation;
  LatLng? _lastSnappedLocation;
  LatLng? _lastSpeedLimitLocation;
  DateTime? _lastSpeedLimitLookup;
  DateTime? _lastRoadEventEvaluationAt;
  LatLng? _lastRoadEventEvaluationLocation;
  bool _speedLimitLookupPending = false;
  double? _headingDegrees;
  Completer<void>? _roadSnappedFixCompleter;

  bool active = false;
  bool guidanceRunning = false;
  bool loadingCameras = false;
  double speedKph = 0;
  int? speedLimitKph;
  bool voiceEnabled = true;
  bool Function(SafetyCamera) _cameraAlertFilter = (_) => true;

  void setCameraAlertFilter(bool Function(SafetyCamera) filter) {
    _cameraAlertFilter = filter;
    _recomputeRouteCameras();
    notifyListeners();
  }

  Future<void> setVoiceLanguage(String language) =>
      _voiceEngine.setLanguage(language);
  String? speedLimitZoneName;
  SpeedAlertSeverity speedSeverity = SpeedAlertSeverity.notSpeeding;
  double? percentageAboveLimit;
  SafetyCamera? upcomingCamera;
  double? upcomingCameraDistanceMeters;
  SafetyCamera? passedCamera;
  CameraAlertState cameraAlertState = const CameraAlertState.idle();
  bool get routed => _route != null;
  NavInfo? navInfo;
  String? error;

  Future<void> start() async {
    if (active) return;
    _roadSnappedFixCompleter = Completer<void>();
    error = null;

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
    active = true;
    _startRoadIntelligenceRefreshTimer();
    notifyListeners();
  }

  /// Local location feed for a non-Google map renderer. Camera alerts keep
  /// using the same matching and voice logic, without starting Google SDK.
  Future<void> startLocal() async {
    if (active) return;
    _roadSnappedFixCompleter = Completer<void>();
    active = true;
    guidanceRunning = true;
    error = null;
    notifyListeners();
    await _voiceEngine.initialize();
    await loadCameras(force: true);
    _startRoadIntelligenceRefreshTimer();
    _subscriptions.add(
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        ),
      ).listen((position) {
        speedKph =
            (position.speed.isFinite && position.speed > 0
                ? position.speed
                : 0) *
            3.6;
        _onLocation(
          LatLng(latitude: position.latitude, longitude: position.longitude),
        );
      }),
    );
  }

  Future<void> loadCameras({bool force = false}) async {
    if (loadingCameras || (!force && _cameras.isNotEmpty)) return;
    loadingCameras = true;
    notifyListeners();
    try {
      roadEvents = await _providerRegistry.load(CountryProfiles.nz);
      final snapshot = _nztaProvider.lastSnapshot;
      _cameras = snapshot?.cameras ?? const [];
      final cameraStatus = snapshot?.syncStatus ?? 'unavailable';
      final trafficStatus = _trafficProvider.lastSyncStatus;
      final providerErrors = _providerRegistry.lastErrors;
      roadIntelligenceStatus =
          cameraStatus == 'stale' || trafficStatus == 'stale'
              ? 'stale'
              : (providerErrors.isNotEmpty ||
                    cameraStatus == 'unavailable' ||
                    trafficStatus == 'unavailable' ||
                    trafficStatus == 'not_loaded'
                    ? 'partial'
                    : 'live');
      _recomputeRouteCameras();
      error = null;
    } catch (exception) {
      roadIntelligenceStatus = 'unavailable';
      error = 'Could not load safety cameras: $exception';
    } finally {
      loadingCameras = false;
      notifyListeners();
    }
  }

  void _startRoadIntelligenceRefreshTimer() {
    _roadIntelligenceRefreshTimer?.cancel();
    _roadIntelligenceRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(loadCameras(force: true)),
    );
  }

  void setRoute(RouteOption? route) {
    _route = route;
    _spokenAlerts.clear();
    _lastRoadEventEvaluationAt = null;
    _recomputeRouteCameras();
    _cameraLifecycle.reset();
    cameraAlertState = const CameraAlertState.idle();
    upcomingCamera = null;
    upcomingCameraDistanceMeters = null;
    notifyListeners();
  }

  void _recomputeRouteCameras() {
    routeCameras = _route == null
        ? const []
        : _routeMatcher.match(_route!, _cameras.where(_cameraAlertFilter).toList(growable: false));
    _highConfidenceCameraIds = routeCameras
        .where((match) => match.highConfidence)
        .map((match) => match.camera.id)
        .toSet();
  }

  void _onRoadSnappedLocation(RoadSnappedLocationUpdatedEvent event) {
    _onLocation(event.location);
  }

  void _onLocation(LatLng current) {
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
    final country = CountryProfiles.at(
      GeoPoint(current.latitude, current.longitude),
    );
    if (country?.code != 'NZ') {
      roadIntelligenceStatus = 'unsupported';
      _cameraLifecycle.reset();
      upcomingRoadEvents = const [];
      upcomingCamera = null;
      upcomingCameraDistanceMeters = null;
      passedCamera = null;
      cameraAlertState = const CameraAlertState.idle();
      speedLimitKph = null;
      speedLimitZoneName = null;
      notifyListeners();
      return;
    }
    unawaited(_refreshSpeedLimit(current));

    CameraMatch? match;
    final route = _route;
    if (route != null) {
      final upcoming = _routeMatcher.upcoming(
        GeoPoint(current.latitude, current.longitude),
        route.points,
        routeCameras,
      );
      final progress = _routeMatcher.project(
        GeoPoint(current.latitude, current.longitude),
        route.points,
      );
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
        cameras: _cameras.where(_cameraAlertFilter).toList(growable: false),
        headingDegrees: _headingDegrees,
      );
    }

    final now = DateTime.now();
    final lastEventLocation = _lastRoadEventEvaluationLocation;
    final eventMove = lastEventLocation == null
        ? double.infinity
        : distanceMeters(
            lastEventLocation.latitude,
            lastEventLocation.longitude,
            current.latitude,
            current.longitude,
          );
    if (_lastRoadEventEvaluationAt == null ||
        now.difference(_lastRoadEventEvaluationAt!).inSeconds >= 5 ||
        eventMove >= 35) {
      upcomingRoadEvents = _roadIntelligence.relevant(
        driver: GeoPoint(current.latitude, current.longitude),
        events: route == null
            ? roadEvents
            : roadEvents
                  .where(
                    (event) =>
                        event.type != RoadEventType.safetyCamera ||
                        _highConfidenceCameraIds.contains(
                          event.source.sourceId,
                        ),
                  )
                  .toList(growable: false),
        headingDegrees: _headingDegrees,
        route: route,
        now: now,
      );
      _lastRoadEventEvaluationAt = now;
      _lastRoadEventEvaluationLocation = current;
    }

    cameraAlertState = _cameraLifecycle.update(match, DateTime.now());
    if (cameraAlertState.phase == CameraAlertPhase.approaching) {
      upcomingCamera = match?.camera;
      upcomingCameraDistanceMeters = match?.distanceMeters;
      passedCamera = null;
      if (match != null) unawaited(_maybeAlert(match));
    } else if (cameraAlertState.phase == CameraAlertPhase.passed) {
      upcomingCamera = null;
      upcomingCameraDistanceMeters = null;
      passedCamera = _cameras
          .where((camera) => camera.id == cameraAlertState.cameraId)
          .firstOrNull;
    } else {
      upcomingCamera = null;
      upcomingCameraDistanceMeters = null;
      passedCamera = null;
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
      final latest = _lastSnappedLocation;
      if (latest != null &&
          distanceMeters(
                current.latitude,
                current.longitude,
                latest.latitude,
                latest.longitude,
              ) <
              100 &&
          CountryProfiles.at(GeoPoint(latest.latitude, latest.longitude))
                  ?.code ==
              'NZ') {
        speedLimitKph = info.speedLimitKph;
        speedLimitZoneName = info.zoneName;
        notifyListeners();
      }
    } catch (_) {
      // An old limit may belong to a different road or region.
      speedLimitKph = null;
      speedLimitZoneName = null;
      notifyListeners();
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
    _roadIntelligenceRefreshTimer?.cancel();
    _roadIntelligenceRefreshTimer = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _spokenAlerts.clear();
    _cameraLifecycle.reset();
    _route = null;
    routeCameras = const [];
    upcomingRoadEvents = const [];
    active = false;
    guidanceRunning = false;
    upcomingCamera = null;
    upcomingCameraDistanceMeters = null;
    passedCamera = null;
    cameraAlertState = const CameraAlertState.idle();
    navInfo = null;
    speedKph = 0;
    speedLimitKph = null;
    speedLimitZoneName = null;
    _lastSpeedLimitLocation = null;
    _lastSnappedLocation = null;
    _roadSnappedFixCompleter = null;
    _lastSpeedLimitLookup = null;
    _lastRoadEventEvaluationAt = null;
    _lastRoadEventEvaluationLocation = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _roadIntelligenceRefreshTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_voiceEngine.dispose());
    super.dispose();
  }
}
