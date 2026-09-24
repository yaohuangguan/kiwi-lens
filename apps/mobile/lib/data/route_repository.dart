import 'dart:convert';

import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:http/http.dart' as http;

import '../domain/route_option.dart';
import 'api_config.dart';

class RouteRepository {
  RouteRepository({http.Client? client, this.baseUrl = workerBaseUrl})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<RoutePlan> fetch({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final uri = Uri.parse('$baseUrl/api/route-options').replace(
      queryParameters: {
        'from': '${origin.longitude},${origin.latitude}',
        'to': '${destination.longitude},${destination.latitude}',
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw StateError('Route preview failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final options = (body['options'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RouteOption.fromJson)
        .where((option) => option.points.length >= 2 || option.mode != KiwiTravelMode.drive)
        .toList(growable: false);
    if (options.isEmpty) throw StateError('No routes available');
    return RoutePlan(
      options: options,
      trafficAvailable: body['trafficAvailable'] == true,
      provider: body['provider'] as String? ?? 'unknown',
    );
  }
}
