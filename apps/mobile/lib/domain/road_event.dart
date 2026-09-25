import 'map_provider.dart';

enum RoadEventType {
  safetyCamera,
  speedLimitChange,
  temporarySpeedLimit,
  roadworks,
  incident,
  congestion,
  schoolZone,
  sharpCurve,
  laneMerge,
  laneEnd,
  oneLaneBridge,
  flooding,
  slip,
  strongWind,
  lowVisibility,
  ice,
  roadClosure,
}

enum RoadEventSeverity { information, advisory, warning, critical }

enum RoadEventObservation { official, observed, forecast, inferred }

class RoadEventSource {
  const RoadEventSource({
    required this.provider,
    required this.country,
    required this.sourceId,
    this.region,
    this.updatedAt,
  });

  final String provider;
  final String country;
  final String sourceId;
  final String? region;
  final DateTime? updatedAt;
}

class RoadEvent {
  const RoadEvent({
    required this.id,
    required this.type,
    required this.location,
    required this.source,
    this.severity = RoadEventSeverity.information,
    this.observation = RoadEventObservation.official,
    this.headingDegrees,
    this.roadName,
    this.distanceFromDriver,
    this.distanceAlongRoute,
    this.confidence = 1,
    this.validFrom,
    this.validUntil,
    this.metadata = const {},
  });

  final String id;
  final RoadEventType type;
  final GeoPoint location;
  final RoadEventSource source;
  final RoadEventSeverity severity;
  final RoadEventObservation observation;
  final double? headingDegrees;
  final String? roadName;
  final double? distanceFromDriver;
  final double? distanceAlongRoute;
  final double confidence;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final Map<String, Object?> metadata;

  bool isCurrent(DateTime now) =>
      (validFrom == null || !now.isBefore(validFrom!)) &&
      (validUntil == null || now.isBefore(validUntil!));

  RoadEvent withDistance({required double fromDriver, double? alongRoute}) =>
      RoadEvent(
        id: id,
        type: type,
        location: location,
        source: source,
        severity: severity,
        observation: observation,
        headingDegrees: headingDegrees,
        roadName: roadName,
        distanceFromDriver: fromDriver,
        distanceAlongRoute: alongRoute,
        confidence: confidence,
        validFrom: validFrom,
        validUntil: validUntil,
        metadata: metadata,
      );
}
