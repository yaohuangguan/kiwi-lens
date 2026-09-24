import 'package:google_navigation_flutter/google_navigation_flutter.dart';

enum KiwiTravelMode { drive, transit, walk, bicycle }

extension KiwiTravelModeUi on KiwiTravelMode {
  String get apiValue => switch (this) {
    KiwiTravelMode.drive => 'drive',
    KiwiTravelMode.transit => 'transit',
    KiwiTravelMode.walk => 'walk',
    KiwiTravelMode.bicycle => 'bicycle',
  };

  String get label => switch (this) {
    KiwiTravelMode.drive => 'Drive',
    KiwiTravelMode.transit => 'Transit',
    KiwiTravelMode.walk => 'Walk',
    KiwiTravelMode.bicycle => 'Bike',
  };
}

class RouteOption {
  const RouteOption({
    required this.id,
    required this.mode,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.points,
    required this.provider,
    this.staticDurationSeconds,
    this.trafficDelaySeconds,
    this.routeToken,
    this.description = '',
    this.labels = const [],
    this.warnings = const [],
  });

  final String id;
  final KiwiTravelMode mode;
  final int durationSeconds;
  final int? staticDurationSeconds;
  final int? trafficDelaySeconds;
  final int distanceMeters;
  final List<LatLng> points;
  final String? routeToken;
  final String description;
  final List<String> labels;
  final List<String> warnings;
  final String provider;

  factory RouteOption.fromJson(Map<String, dynamic> json) {
    final mode = KiwiTravelMode.values.firstWhere(
      (value) => value.apiValue == json['mode'],
      orElse: () => KiwiTravelMode.drive,
    );
    final coordinates = (json['coordinates'] as List<dynamic>? ?? const [])
        .whereType<List<dynamic>>()
        .where((pair) => pair.length >= 2)
        .map((pair) => LatLng(
              latitude: (pair[1] as num).toDouble(),
              longitude: (pair[0] as num).toDouble(),
            ))
        .toList(growable: false);
    final encoded = json['encodedPolyline'] as String?;
    return RouteOption(
      id: json['id'] as String? ?? mode.apiValue,
      mode: mode,
      durationSeconds: (json['durationSeconds'] as num?)?.round() ?? 0,
      staticDurationSeconds: (json['staticDurationSeconds'] as num?)?.round(),
      trafficDelaySeconds: (json['trafficDelaySeconds'] as num?)?.round(),
      distanceMeters: (json['distanceMeters'] as num?)?.round() ?? 0,
      points: coordinates.isNotEmpty ? coordinates : decodePolyline(encoded ?? ''),
      routeToken: json['routeToken'] as String?,
      description: json['description'] as String? ?? '',
      labels: (json['labels'] as List<dynamic>? ?? const []).whereType<String>().toList(growable: false),
      warnings: (json['warnings'] as List<dynamic>? ?? const []).whereType<String>().toList(growable: false),
      provider: json['provider'] as String? ?? 'unknown',
    );
  }
}

class RoutePlan {
  const RoutePlan({
    required this.options,
    required this.trafficAvailable,
    required this.provider,
  });

  final List<RouteOption> options;
  final bool trafficAvailable;
  final String provider;

  Iterable<RouteOption> forMode(KiwiTravelMode mode) =>
      options.where((option) => option.mode == mode);
}

List<LatLng> decodePolyline(String encoded) {
  if (encoded.isEmpty) return const [];
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

    shift = 0;
    result = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    points.add(LatLng(latitude: lat / 1e5, longitude: lng / 1e5));
  }
  return points;
}
