import 'dart:math' as math;

import '../drive/route_camera_matcher.dart';
import 'country_profile.dart';
import 'geo_math.dart';
import 'map_provider.dart';
import 'road_event.dart';
import 'route_option.dart';

abstract class RoadEventProvider {
  bool supports(CountryProfile country);
  Future<List<RoadEvent>> load();
}

class RoadEventProviderRegistry {
  RoadEventProviderRegistry(this.providers);
  final List<RoadEventProvider> providers;
  List<Object> lastErrors = const [];

  Future<List<RoadEvent>> load(CountryProfile country) async {
    if (!country.roadIntelligenceAvailable) return const [];
    final available = providers.where((p) => p.supports(country));
    final events = <RoadEvent>[];
    final errors = <Object>[];
    for (final provider in available) {
      try {
        events.addAll(await provider.load());
      } catch (error) {
        errors.add(error);
      }
    }
    lastErrors = List.unmodifiable(errors);
    return events;
  }
}

class RoadIntelligenceEngine {
  const RoadIntelligenceEngine({
    this.maxDistanceMeters = 1500,
    this.routeCorridorMeters = 65,
    this.maxResults = 4,
  });

  final double maxDistanceMeters;
  final double routeCorridorMeters;
  final int maxResults;
  static const _routeMatcher = RouteCameraMatcher();

  List<RoadEvent> relevant({
    required GeoPoint driver,
    required List<RoadEvent> events,
    double? headingDegrees,
    RouteOption? route,
    DateTime? now,
  }) {
    if (events.isEmpty) return const [];
    final at = now ?? DateTime.now();
    final progress = route == null
        ? null
        : _routeMatcher.project(driver, route.points);
    final output = <RoadEvent>[];
    final seen = <String>{};
    for (final event in events) {
      if (!event.isCurrent(at) ||
          event.confidence < .5 ||
          !seen.add(event.id)) {
        continue;
      }
      // Rough bounding box prevents most distance and route projections.
      final latDelta = maxDistanceMeters / 110540;
      final lonDelta =
          maxDistanceMeters /
          (111320 *
              math.cos(driver.latitude * math.pi / 180).abs().clamp(.1, 1));
      if ((event.location.latitude - driver.latitude).abs() > latDelta ||
          (event.location.longitude - driver.longitude).abs() > lonDelta) {
        continue;
      }
      final distance = distanceMeters(
        driver.latitude,
        driver.longitude,
        event.location.latitude,
        event.location.longitude,
      );
      if (distance > maxDistanceMeters) continue;
      double? along;
      if (route != null && progress != null && progress.offsetMeters <= 100) {
        final projected = _routeMatcher.project(event.location, route.points);
        if (projected == null || projected.offsetMeters > routeCorridorMeters) {
          continue;
        }
        along = projected.alongMeters - progress.alongMeters;
        if (along < -15 || along > maxDistanceMeters) continue;
        if (event.headingDegrees != null &&
            angleDifference(event.headingDegrees!, projected.bearingDegrees) >
                55) {
          continue;
        }
      } else {
        if (headingDegrees == null) continue;
        final bearing = bearingDegrees(
          driver.latitude,
          driver.longitude,
          event.location.latitude,
          event.location.longitude,
        );
        final difference = angleDifference(headingDegrees, bearing);
        if (difference > 45 ||
            distance * math.sin(difference * math.pi / 180) > 65) {
          continue;
        }
        if (event.headingDegrees != null &&
            angleDifference(event.headingDegrees!, headingDegrees) > 55) {
          continue;
        }
      }
      output.add(event.withDistance(fromDriver: distance, alongRoute: along));
    }
    output.sort((a, b) {
      final byDistance = (a.distanceAlongRoute ?? a.distanceFromDriver ?? 0)
          .compareTo(b.distanceAlongRoute ?? b.distanceFromDriver ?? 0);
      if (byDistance != 0) return byDistance;
      return b.severity.index.compareTo(a.severity.index);
    });
    return output.take(maxResults).toList(growable: false);
  }
}
