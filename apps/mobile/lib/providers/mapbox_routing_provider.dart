import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import 'provider_contracts.dart';

/// Translates Mapbox Directions into the existing route-preview model.
/// Google route tokens are deliberately never used on a Mapbox map.
class MapboxRoutingProvider implements RoutingProvider<RoutePlan> {
  MapboxRoutingProvider(this.accessToken, {http.Client? client})
    : _client = client ?? http.Client();

  final String accessToken;
  final http.Client _client;

  @override
  Future<RoutePlan> route({
    required GeoPoint origin,
    required GeoPoint destination,
    List<GeoPoint> stops = const [],
    required String language,
  }) async {
    if (accessToken.isEmpty) throw StateError('Mapbox token is not configured');
    final points = [origin, ...stops, destination];
    final path = points
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');
    final modes = <(KiwiTravelMode, String)>[
      (KiwiTravelMode.drive, 'driving-traffic'),
      (KiwiTravelMode.walk, 'walking'),
      (KiwiTravelMode.bicycle, 'cycling'),
    ];
    final responses = await Future.wait(
      modes.map(
        (entry) => _fetchMode(
          path,
          mode: entry.$1,
          profile: entry.$2,
          language: language,
        ),
      ),
    );
    final options = responses.expand((item) => item).toList(growable: false);
    if (options.isEmpty) throw StateError('No Mapbox routes available');
    return RoutePlan(
      options: options,
      trafficAvailable: false,
      provider: 'mapbox',
      stopsApplied: stops.length,
    );
  }

  Future<List<RouteOption>> _fetchMode(
    String path, {
    required KiwiTravelMode mode,
    required String profile,
    required String language,
  }) async {
    final uri = Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/$profile/$path',
      {
        'access_token': accessToken,
        'geometries': 'geojson',
        'overview': 'full',
        'alternatives': 'true',
        'steps': 'true',
        'language': language == 'zh' ? 'zh' : 'en',
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      if (mode != KiwiTravelMode.drive) return const [];
      throw StateError('Mapbox directions unavailable: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = body['routes'] as List<dynamic>? ?? const [];
    return routes
        .whereType<Map<String, dynamic>>()
        .indexed
        .map((entry) {
          final route = entry.$2;
          final geometry =
              route['geometry'] as Map<String, dynamic>? ?? const {};
          final coordinates =
              geometry['coordinates'] as List<dynamic>? ?? const [];
          final routePoints = coordinates
              .whereType<List<dynamic>>()
              .where((pair) => pair.length >= 2)
              .map(
                (pair) => GeoPoint(
                  (pair[1] as num).toDouble(),
                  (pair[0] as num).toDouble(),
                ),
              )
              .toList(growable: false);
          final steps = (route['legs'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .expand((leg) => leg['steps'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map((step) {
                final maneuver =
                    step['maneuver'] as Map<String, dynamic>? ?? const {};
                final point =
                    maneuver['location'] as List<dynamic>? ?? const [];
                if (point.length < 2) return null;
                return RouteStepInfo(
                  instruction: maneuver['instruction']?.toString() ?? '',
                  distanceMeters: (step['distance'] as num?)?.round() ?? 0,
                  location: GeoPoint(
                    (point[1] as num).toDouble(),
                    (point[0] as num).toDouble(),
                  ),
                );
              })
              .whereType<RouteStepInfo>()
              .toList(growable: false);
          return RouteOption(
            id: 'mapbox-${mode.name}-${entry.$1}',
            mode: mode,
            durationSeconds: (route['duration'] as num?)?.round() ?? 0,
            distanceMeters: (route['distance'] as num?)?.round() ?? 0,
            points: routePoints,
            provider: 'mapbox',
            traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
            trafficIntervals: const [],
            steps: steps,
            description: entry.$1 == 0 ? 'Fastest' : 'Alternative ${entry.$1}',
          );
        })
        .where((option) => option.points.length >= 2)
        .toList(growable: false);
  }

  void dispose() => _client.close();
}
