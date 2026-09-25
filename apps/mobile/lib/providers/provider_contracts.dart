import '../domain/map_provider.dart';

abstract interface class MapRenderer {
  MapProvider get provider;
  MapViewportState get viewport;
  Future<void> moveTo(MapViewportState viewport);
}

abstract interface class SearchProvider {
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  });
}

abstract interface class PlaceProvider {
  Future<PlaceSummary> resolve(
    ProviderReference reference, {
    required String language,
  });
}

abstract interface class ExploreProvider {
  Future<List<PlaceSummary>> nearby(
    String category, {
    required GeoPoint center,
    required String language,
  });
}

abstract interface class RoutingProvider<TPlan> {
  Future<TPlan> route({
    required GeoPoint origin,
    required GeoPoint destination,
    List<GeoPoint> stops,
    required String language,
  });
}

abstract interface class NavigationEngine<TPlan> {
  Future<void> start(TPlan plan);
  Future<void> stop();
}
