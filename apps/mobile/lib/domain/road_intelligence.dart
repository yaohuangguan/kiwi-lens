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

      final candidates = event.geometry.isEmpty
          ? <GeoPoint>[event.location]
          : event.geometry;
      final nearby = candidates
          .map((point) => (
                point: point,
                distance: distanceMeters(
                  driver.latitude,
                  driver.longitude,
                  point.latitude,
                  point.longitude,
                ),
              ))
          .where((entry) => entry.distance <= maxDistanceMeters)
          .toList(growable: false);
      if (nearby.isEmpty) continue;

      GeoPoint? matchedPoint;
      double? fromDriver;
      double? along;

      if (route != null && progress != null && progress.offsetMeters <= 100) {
        double bestOffset = double.infinity;
        for (final entry in nearby) {
          final projected = _routeMatcher.project(entry.point, route.points);
          if (projected == null || projected.offsetMeters > routeCorridorMeters) {
            continue;
          }
          final candidateAlong = projected.alongMeters - progress.alongMeters;
          if (candidateAlong < -15 || candidateAlong > maxDistanceMeters) continue;
          if (event.headingDegrees != null &&
              angleDifference(event.headingDegrees!, projected.bearingDegrees) > 55) {
            continue;
          }
          if (projected.offsetMeters < bestOffset) {
            bestOffset = projected.offsetMeters;
            matchedPoint = entry.point;
            fromDriver = entry.distance;
            along = candidateAlong;
          }
        }
      } else {
        if (headingDegrees == null) continue;
        double bestDistance = double.infinity;
        for (final entry in nearby) {
          final bearing = bearingDegrees(
            driver.latitude,
            driver.longitude,
            entry.point.latitude,
            entry.point.longitude,
          );
          final difference = angleDifference(headingDegrees, bearing);
          if (difference > 45 ||
              entry.distance * math.sin(difference * math.pi / 180) > 65) {
            continue;
          }
          if (event.headingDegrees != null &&
              angleDifference(event.headingDegrees!, headingDegrees) > 55) {
            continue;
          }
          if (entry.distance < bestDistance) {
            bestDistance = entry.distance;
            matchedPoint = entry.point;
            fromDriver = entry.distance;
          }
        }
      }

      if (matchedPoint == null || fromDriver == null) continue;
      output.add(event.withDistance(fromDriver: fromDriver, alongRoute: along));
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
