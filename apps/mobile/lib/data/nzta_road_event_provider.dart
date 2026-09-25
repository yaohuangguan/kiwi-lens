import '../domain/country_profile.dart';
import '../domain/map_provider.dart';
import '../domain/road_event.dart';
import '../domain/road_intelligence.dart';
import 'camera_repository.dart';

/// Translates the Worker camera snapshot into the shared road-event domain.
class NztaRoadEventProvider implements RoadEventProvider {
  NztaRoadEventProvider(this.repository);

  final CameraRepository repository;
  CameraSnapshot? lastSnapshot;

  @override
  bool supports(CountryProfile country) => country.code == 'NZ';

  @override
  Future<List<RoadEvent>> load() async {
    final snapshot = await repository.fetchSnapshot();
    lastSnapshot = snapshot;
    return snapshot.cameras
        .map((camera) {
          return RoadEvent(
            id: 'nzta:camera:${camera.id}',
            type: RoadEventType.safetyCamera,
            location: GeoPoint(camera.latitude, camera.longitude),
            headingDegrees: _direction(camera.location),
            roadName: camera.location,
            source: RoadEventSource(
              provider: 'NZTA safety cameras',
              country: 'NZ',
              region: camera.region,
              sourceId: camera.id,
              updatedAt: snapshot.sourceUpdatedAt,
            ),
            metadata: {'cameraType': camera.type},
          );
        })
        .toList(growable: false);
  }

  double? _direction(String location) {
    final lower = location.toLowerCase();
    if (RegExp(r'\b(nb|northbound)\b').hasMatch(lower)) return 0;
    if (RegExp(r'\b(eb|eastbound)\b').hasMatch(lower)) return 90;
    if (RegExp(r'\b(sb|southbound)\b').hasMatch(lower)) return 180;
    if (RegExp(r'\b(wb|westbound)\b').hasMatch(lower)) return 270;
    return null;
  }
}
