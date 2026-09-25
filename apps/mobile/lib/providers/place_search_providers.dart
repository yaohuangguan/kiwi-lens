import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../data/api_config.dart';
import '../domain/map_provider.dart';
import 'provider_contracts.dart';

class WorkerSearchProvider implements SearchProvider, ExploreProvider {
  WorkerSearchProvider({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) async {
    final uri = Uri.parse('$workerBaseUrl/api/suggest').replace(
      queryParameters: {
        'q': query,
        'lang': language,
        if (proximity != null)
          'near': '${proximity.longitude},${proximity.latitude}',
      },
    );
    var response = await _client.get(uri);
    if (response.statusCode == 503) {
      response = await _client.get(
        Uri.parse('$workerBaseUrl/api/search')
            .replace(queryParameters: {'q': query, 'lang': language}),
      );
    }
    if (response.statusCode != 200) {
      throw StateError('Search unavailable: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final latitude = item['latitude'];
          final longitude = item['longitude'];
          if (latitude is! num || longitude is! num) return null;
          final label = item['label']?.toString() ?? '';
          final name = item['name']?.toString().trim() ?? '';
          final address = item['address']?.toString().trim() ?? '';
          final displayName = name.isEmpty ? label : name;
          final isAddress = RegExp(r'^\d+\s').hasMatch(displayName);
          return PlaceCandidate(
            name: displayName,
            address: address.isEmpty ? label : address,
            kind: isAddress ? PlaceKind.address : PlaceKind.poi,
            location: GeoPoint(latitude.toDouble(), longitude.toDouble()),
            reference: ProviderReference(
              'geoapify',
              item['id']?.toString() ?? label,
            ),
          );
        })
        .whereType<PlaceCandidate>()
        .toList(growable: false);
  }

  void dispose() => _client.close();

  @override
  Future<List<PlaceSummary>> nearby(
    String category, {
    required GeoPoint center,
    required String language,
  }) async {
    final results = await search(
      category,
      proximity: center,
      language: language,
    );
    return results
        .where((result) => result.location != null)
        .map((result) => result.toPlace(result.location!))
        .toList(growable: false);
  }
}

/// Search Box suggestions have no coordinates; the selected result must be
/// retrieved with the same session token before it enters SelectedPlace.
class MapboxSearchProvider
    implements SearchProvider, PlaceProvider, ExploreProvider {
  MapboxSearchProvider(this.accessToken, {http.Client? client})
    : _client = client ?? http.Client();

  final String accessToken;
  final http.Client _client;
  String _sessionToken = _newSessionToken();

  static String _newSessionToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) async {
    if (accessToken.isEmpty) throw StateError('Mapbox token is not configured');
    final uri = Uri.https('api.mapbox.com', '/search/searchbox/v1/suggest', {
      'q': query,
      'access_token': accessToken,
      'session_token': _sessionToken,
      'country': 'NZ',
      'language': language == 'zh' ? 'zh' : 'en',
      'limit': '8',
      if (proximity != null)
        'proximity': '${proximity.longitude},${proximity.latitude}',
    });
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw StateError('Mapbox search unavailable: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['suggestions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final id = item['mapbox_id']?.toString() ?? '';
          if (id.isEmpty) return null;
          final type = item['feature_type']?.toString() ?? '';
          return PlaceCandidate(
            name:
                item['name_preferred']?.toString() ??
                item['name']?.toString() ??
                '',
            address:
                item['full_address']?.toString() ??
                item['place_formatted']?.toString() ??
                '',
            category: item['poi_category'] is List
                ? (item['poi_category'] as List).join(', ')
                : '',
            kind: type == 'address' || type == 'street'
                ? PlaceKind.address
                : PlaceKind.poi,
            reference: ProviderReference('mapbox', id),
          );
        })
        .whereType<PlaceCandidate>()
        .toList(growable: false);
  }

  @override
  Future<PlaceSummary> resolve(
    ProviderReference reference, {
    required String language,
  }) async {
    if (reference.provider != 'mapbox') {
      throw StateError('Cannot retrieve a non-Mapbox reference');
    }
    final uri = Uri.https(
      'api.mapbox.com',
      '/search/searchbox/v1/retrieve/${Uri.encodeComponent(reference.id)}',
      {'access_token': accessToken, 'session_token': _sessionToken},
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw StateError('Mapbox place unavailable: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final features = body['features'] as List<dynamic>? ?? const [];
    if (features.isEmpty || features.first is! Map<String, dynamic>) {
      throw StateError('Selected place has no location');
    }
    final feature = features.first as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>? ?? const {};
    final coordinates = geometry['coordinates'] as List<dynamic>? ?? const [];
    if (coordinates.length < 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num) {
      throw StateError('Selected place has no coordinates');
    }
    final props = feature['properties'] as Map<String, dynamic>? ?? const {};
    final coordinatesPoint = GeoPoint(
      (coordinates[1] as num).toDouble(),
      (coordinates[0] as num).toDouble(),
    );
    _sessionToken = _newSessionToken();
    return PlaceSummary(
      name:
          props['name_preferred']?.toString() ??
          props['name']?.toString() ??
          'Selected place',
      location: coordinatesPoint,
      address: placeSecondaryAddress(
        props['name_preferred']?.toString() ?? props['name']?.toString() ?? '',
        props['full_address']?.toString() ??
            props['place_formatted']?.toString() ??
            '',
      ),
      category: props['poi_category']?.toString() ?? '',
      kind: props['feature_type'] == 'address'
          ? PlaceKind.address
          : PlaceKind.poi,
      reference: reference,
    );
  }

  void dispose() => _client.close();

  Future<PlaceSummary?> reverseNear(
    GeoPoint point, {
    required String language,
    required String preferredName,
  }) async {
    if (accessToken.isEmpty) return null;
    final uri = Uri.https('api.mapbox.com', '/search/searchbox/v1/reverse', {
      'longitude': point.longitude.toString(),
      'latitude': point.latitude.toString(),
      'access_token': accessToken,
      'language': language == 'zh' ? 'zh' : 'en',
      'limit': '5',
      'types': 'poi,address',
    });
    final response = await _client.get(uri);
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final features = body['features'] as List<dynamic>? ?? const [];
    for (final feature in features.whereType<Map<String, dynamic>>()) {
      final props = feature['properties'] as Map<String, dynamic>? ?? const {};
      final geometry = feature['geometry'] as Map<String, dynamic>? ?? const {};
      final pair = geometry['coordinates'] as List<dynamic>? ?? const [];
      if (pair.length < 2 || pair[0] is! num || pair[1] is! num) continue;
      final candidate = GeoPoint(
        (pair[1] as num).toDouble(),
        (pair[0] as num).toDouble(),
      );
      final deltaLatitude = (candidate.latitude - point.latitude).abs();
      final deltaLongitude = (candidate.longitude - point.longitude).abs();
      if (deltaLatitude > 0.001 || deltaLongitude > 0.001) continue;
      final name = preferredName.isNotEmpty
          ? preferredName
          : props['name']?.toString() ?? 'Selected place';
      return PlaceSummary(
        name: name,
        location: point,
        address: placeSecondaryAddress(
          name,
          props['full_address']?.toString() ??
              props['place_formatted']?.toString() ??
              '',
        ),
        category: props['poi_category']?.toString() ?? '',
        kind: props['feature_type'] == 'address'
            ? PlaceKind.address
            : PlaceKind.poi,
        reference: props['mapbox_id'] == null
            ? null
            : ProviderReference('mapbox', props['mapbox_id'].toString()),
      );
    }
    return null;
  }

  @override
  Future<List<PlaceSummary>> nearby(
    String category, {
    required GeoPoint center,
    required String language,
  }) async {
    if (accessToken.isEmpty) throw StateError('Mapbox token is not configured');
    final uri = Uri.https('api.mapbox.com', '/search/searchbox/v1/forward', {
      'q': category,
      'access_token': accessToken,
      'country': 'NZ',
      'types': 'poi',
      'language': language == 'zh' ? 'zh' : 'en',
      'proximity': '${center.longitude},${center.latitude}',
      'limit': '12',
    });
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw StateError('Explore unavailable: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['features'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((feature) {
          final geometry =
              feature['geometry'] as Map<String, dynamic>? ?? const {};
          final pair = geometry['coordinates'] as List<dynamic>? ?? const [];
          if (pair.length < 2 || pair[0] is! num || pair[1] is! num) {
            return null;
          }
          final props =
              feature['properties'] as Map<String, dynamic>? ?? const {};
          return PlaceSummary(
            name:
                props['name_preferred']?.toString() ??
                props['name']?.toString() ??
                category,
            address:
                props['full_address']?.toString() ??
                props['place_formatted']?.toString() ??
                '',
            location: GeoPoint(
              (pair[1] as num).toDouble(),
              (pair[0] as num).toDouble(),
            ),
            category: category,
            reference: props['mapbox_id'] == null
                ? null
                : ProviderReference('mapbox', props['mapbox_id'].toString()),
          );
        })
        .whereType<PlaceSummary>()
        .toList(growable: false);
  }
}
