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

class TransitLeg {
  const TransitLeg({
    required this.lineName,
    required this.headsign,
    required this.vehicleType,
    required this.vehicleName,
    required this.departureStop,
    required this.arrivalStop,
    required this.stopCount,
    this.departureTime,
    this.arrivalTime,
    this.agencies = const [],
  });

  final String lineName;
  final String headsign;
  final String vehicleType;
  final String vehicleName;
  final String departureStop;
  final String arrivalStop;
  final int stopCount;
  final String? departureTime;
  final String? arrivalTime;
  final List<String> agencies;

  factory TransitLeg.fromJson(Map<String, dynamic> json) => TransitLeg(
    lineName: json['lineName'] as String? ?? '',
    headsign: json['headsign'] as String? ?? '',
    vehicleType: json['vehicleType'] as String? ?? '',
    vehicleName: json['vehicleName'] as String? ?? '',
    departureStop: json['departureStop'] as String? ?? '',
    arrivalStop: json['arrivalStop'] as String? ?? '',
    stopCount: (json['stopCount'] as num?)?.round() ?? 0,
    departureTime: json['departureTime'] as String?,
    arrivalTime: json['arrivalTime'] as String?,
    agencies: (json['agencies'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false),
  );
}

class RouteStepInfo {
  const RouteStepInfo({
    required this.instruction,
    required this.distanceMeters,
    required this.location,
  });

  final String instruction;
  final int distanceMeters;
  final LatLng location;

  factory RouteStepInfo.fromJson(Map<String, dynamic> json) {
    final pair = json['location'] as List<dynamic>? ?? const [];
    return RouteStepInfo(
      instruction: json['instruction'] as String? ?? '',
      distanceMeters: (json['distance'] as num?)?.round() ?? 0,
      location: LatLng(
        latitude: pair.length > 1 ? (pair[1] as num).toDouble() : 0,
        longitude: pair.isNotEmpty ? (pair[0] as num).toDouble() : 0,
      ),
    );
  }
}

class TrafficInterval {
  const TrafficInterval({
    required this.startPolylinePointIndex,
    required this.endPolylinePointIndex,
    required this.speed,
  });

  final int startPolylinePointIndex;
  final int endPolylinePointIndex;
  final String speed;

  factory TrafficInterval.fromJson(Map<String, dynamic> json) =>
      TrafficInterval(
        startPolylinePointIndex:
            (json['startPolylinePointIndex'] as num?)?.round() ?? 0,
        endPolylinePointIndex:
            (json['endPolylinePointIndex'] as num?)?.round() ?? 0,
        speed: json['speed'] as String? ?? 'normal',
      );
}

class TrafficSummary {
  const TrafficSummary({
    required this.normal,
    required this.slow,
    required this.trafficJam,
  });

  final int normal;
  final int slow;
  final int trafficJam;

  bool get hasIssues => slow > 0 || trafficJam > 0;

  factory TrafficSummary.fromJson(Map<String, dynamic>? json) => TrafficSummary(
    normal: (json?['normal'] as num?)?.round() ?? 0,
    slow: (json?['slow'] as num?)?.round() ?? 0,
    trafficJam: (json?['trafficJam'] as num?)?.round() ?? 0,
  );
}

class RouteOption {
  const RouteOption({
    required this.id,
    required this.mode,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.points,
    required this.provider,
    required this.traffic,
    required this.trafficIntervals,
    this.staticDurationSeconds,
    this.trafficDelaySeconds,
    this.routeToken,
    this.description = '',
    this.labels = const [],
    this.warnings = const [],
    this.transit = const [],
    this.steps = const [],
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
  final List<TransitLeg> transit;
  final List<RouteStepInfo> steps;
  final TrafficSummary traffic;
  final List<TrafficInterval> trafficIntervals;
  final String provider;

  factory RouteOption.fromJson(Map<String, dynamic> json) {
    final mode = KiwiTravelMode.values.firstWhere(
      (value) => value.apiValue == json['mode'],
      orElse: () => KiwiTravelMode.drive,
    );
    final coordinates = (json['coordinates'] as List<dynamic>? ?? const [])
        .whereType<List<dynamic>>()
        .where((pair) => pair.length >= 2)
        .map(
          (pair) => LatLng(
            latitude: (pair[1] as num).toDouble(),
            longitude: (pair[0] as num).toDouble(),
          ),
        )
        .toList(growable: false);
    final encoded = json['encodedPolyline'] as String?;
    return RouteOption(
      id: json['id'] as String? ?? mode.apiValue,
      mode: mode,
      durationSeconds: (json['durationSeconds'] as num?)?.round() ?? 0,
      staticDurationSeconds: (json['staticDurationSeconds'] as num?)?.round(),
      trafficDelaySeconds: (json['trafficDelaySeconds'] as num?)?.round(),
      distanceMeters: (json['distanceMeters'] as num?)?.round() ?? 0,
      points: coordinates.isNotEmpty
          ? coordinates
          : decodePolyline(encoded ?? ''),
      routeToken: json['routeToken'] as String?,
      description: json['description'] as String? ?? '',
      labels: (json['labels'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      transit: (json['transit'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TransitLeg.fromJson)
          .toList(growable: false),
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RouteStepInfo.fromJson)
          .toList(growable: false),
      traffic: TrafficSummary.fromJson(
        json['traffic'] as Map<String, dynamic>?,
      ),
      trafficIntervals: (json['trafficIntervals'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TrafficInterval.fromJson)
          .toList(growable: false),
      provider: json['provider'] as String? ?? 'unknown',
    );
  }
}

class RoutePlan {
  const RoutePlan({
    required this.options,
    required this.trafficAvailable,
    required this.provider,
    required this.stopsApplied,
  });

  final List<RouteOption> options;
  final bool trafficAvailable;
  final String provider;
  final int stopsApplied;

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
