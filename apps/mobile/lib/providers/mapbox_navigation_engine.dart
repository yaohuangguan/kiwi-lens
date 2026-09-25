import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import '../drive/drive_engine.dart';
import '../drive/route_camera_matcher.dart';
import 'provider_contracts.dart';

/// Mapbox route guidance powered by the route's maneuvers and the device
/// location feed. It never starts a Google Navigation SDK session.
class MapboxNavigationEngine extends ChangeNotifier
    implements NavigationEngine<RouteOption> {
  MapboxNavigationEngine(this.drive);

  final DriveEngine drive;
  final RouteCameraMatcher _matcher = const RouteCameraMatcher();
  RouteOption? _route;
  RouteStepInfo? _nextStep;
  double _distanceToStep = 0;
  double _remainingMeters = 0;
  final Set<String> _spokenSteps = {};

  RouteOption? get route => _route;
  RouteStepInfo? get nextStep => _nextStep;
  double get distanceToStepMeters => _distanceToStep;
  double get remainingDistanceMeters => _remainingMeters;
  bool get active => _route != null && drive.active;
  int get remainingSeconds {
    final route = _route;
    if (route == null || route.distanceMeters <= 0) return 0;
    return (route.durationSeconds * (_remainingMeters / route.distanceMeters))
        .round();
  }

  @override
  Future<void> start(RouteOption route) async {
    if (route.provider != 'mapbox') {
      throw StateError('Mapbox navigation requires a Mapbox route');
    }
    _route = route;
    _spokenSteps.clear();
    _remainingMeters = route.distanceMeters.toDouble();
    drive.setRoute(route);
    drive.addListener(_onLocation);
    try {
      await drive.startLocal();
    } catch (_) {
      drive.removeListener(_onLocation);
      _route = null;
      rethrow;
    }
    notifyListeners();
  }

  void _onLocation() {
    final route = _route;
    final location = drive.snappedLocation;
    if (route == null || location == null) return;
    final progress = _matcher.project(
      GeoPoint(location.latitude, location.longitude),
      route.points,
    );
    if (progress == null) return;
    _remainingMeters = math.max(0, route.distanceMeters - progress.alongMeters);
    RouteStepInfo? next;
    var distance = 0.0;
    for (final step in route.steps) {
      final projected = _matcher.project(step.location, route.points);
      if (projected == null ||
          projected.alongMeters <= progress.alongMeters + 15) {
        continue;
      }
      next = step;
      distance = projected.alongMeters - progress.alongMeters;
      break;
    }
    _nextStep = next;
    _distanceToStep = distance;
    if (next != null && drive.voiceEnabled) {
      final key = route.steps.indexOf(next);
      if (distance < 220 && _spokenSteps.add('$key:approach')) {
        unawaited(drive.speakMessage(next.instruction));
      }
      if (distance < 55 && _spokenSteps.add('$key:turn')) {
        unawaited(drive.speakMessage(next.instruction));
      }
    }
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    drive.removeListener(_onLocation);
    await drive.stop();
    _route = null;
    _nextStep = null;
    _distanceToStep = 0;
    _remainingMeters = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    drive.removeListener(_onLocation);
    super.dispose();
  }
}
