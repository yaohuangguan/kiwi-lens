import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/country_profile.dart';
import '../domain/map_provider.dart';
import '../domain/road_event.dart';
import '../domain/road_intelligence.dart';
import 'api_config.dart';

class NztaTrafficRoadEventProvider implements RoadEventProvider {
  NztaTrafficRoadEventProvider({
    http.Client? client,
    this.baseUrl = workerBaseUrl,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  String lastSyncStatus = 'not_loaded';
  DateTime? lastCheckedAt;

  @override
  bool supports(CountryProfile country) => country.code == 'NZ';

  @override
  Future<List<RoadEvent>> load() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/road-events'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Road events API failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    lastSyncStatus = body['syncStatus']?.toString() ?? 'unknown';
    lastCheckedAt = DateTime.tryParse(body['checkedAt']?.toString() ?? '');
    return (body['events'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_fromJson)
        .whereType<RoadEvent>()
        .toList(growable: false);
  }

  RoadEvent? _fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    final source = json['source'];
    if (location is! Map<String, dynamic> || source is! Map<String, dynamic>) {
      return null;
    }
    final latitude = (location['latitude'] as num?)?.toDouble();
    final longitude = (location['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;

    final geometry = (json['geometry'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((point) {
          final lat = (point['latitude'] as num?)?.toDouble();
          final lon = (point['longitude'] as num?)?.toDouble();
          return lat == null || lon == null ? null : GeoPoint(lat, lon);
        })
        .whereType<GeoPoint>()
        .toList(growable: false);

    return RoadEvent(
      id: json['id']?.toString() ?? '',
      type: _eventType(json['type']?.toString()),
      location: GeoPoint(latitude, longitude),
      geometry: geometry,
      source: RoadEventSource(
        provider: source['provider']?.toString() ?? 'NZTA Traffic and Travel',
        country: source['country']?.toString() ?? 'NZ',
        sourceId: source['sourceId']?.toString() ?? '',
        region: source['region']?.toString(),
        updatedAt: DateTime.tryParse(source['updatedAt']?.toString() ?? ''),
      ),
      severity: _severity(json['severity']?.toString()),
      observation: _observation(json['observation']?.toString()),
      roadName: json['roadName']?.toString(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
      validFrom: DateTime.tryParse(json['validFrom']?.toString() ?? ''),
      validUntil: DateTime.tryParse(json['validUntil']?.toString() ?? ''),
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }

  RoadEventType _eventType(String? value) => switch (value) {
        'roadClosure' => RoadEventType.roadClosure,
        'roadworks' => RoadEventType.roadworks,
        'flooding' => RoadEventType.flooding,
        'slip' => RoadEventType.slip,
        _ => RoadEventType.incident,
      };

  RoadEventObservation _observation(String? value) => switch (value) {
        'observed' => RoadEventObservation.observed,
        'forecast' => RoadEventObservation.forecast,
        'inferred' => RoadEventObservation.inferred,
        _ => RoadEventObservation.official,
      };

  RoadEventSeverity _severity(String? value) => switch (value) {
        'critical' => RoadEventSeverity.critical,
        'warning' => RoadEventSeverity.warning,
        'advisory' => RoadEventSeverity.advisory,
        _ => RoadEventSeverity.information,
      };
}
