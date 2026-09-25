enum MapProvider { google, mapbox }

enum LocationMarkerStyle { kiwi, arrow, car, classic }

enum MapAppearance { standard, satellite, terrain, hybrid }

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      latitude == other.latitude &&
      longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

class MapViewportState {
  const MapViewportState({
    required this.center,
    this.zoom = 14,
    this.bearing = 0,
    this.pitch = 0,
  });

  final GeoPoint center;
  final double zoom;
  final double bearing;
  final double pitch;

  MapViewportState copyWith({
    GeoPoint? center,
    double? zoom,
    double? bearing,
    double? pitch,
  }) => MapViewportState(
    center: center ?? this.center,
    zoom: zoom ?? this.zoom,
    bearing: bearing ?? this.bearing,
    pitch: pitch ?? this.pitch,
  );
}

class ProviderReference {
  const ProviderReference(this.provider, this.id);

  final String provider;
  final String id;
}

enum PlaceKind { poi, address, coordinate }

class PlaceSummary {
  const PlaceSummary({
    required this.name,
    required this.location,
    this.address = '',
    this.category = '',
    this.kind = PlaceKind.poi,
    this.reference,
  });

  final String name;
  final GeoPoint location;
  final String address;
  final String category;
  final PlaceKind kind;
  final ProviderReference? reference;
}

class PlaceCandidate {
  const PlaceCandidate({
    required this.name,
    this.address = '',
    this.category = '',
    this.kind = PlaceKind.poi,
    this.location,
    this.reference,
  });

  final String name;
  final String address;
  final String category;
  final PlaceKind kind;
  final GeoPoint? location;
  final ProviderReference? reference;

  String get secondaryAddress => placeSecondaryAddress(name, address);

  PlaceSummary toPlace(GeoPoint resolvedLocation) => PlaceSummary(
    name: name,
    location: resolvedLocation,
    address: secondaryAddress,
    category: category,
    kind: kind,
    reference: reference,
  );
}

String placeSecondaryAddress(String name, String address) {
  final trimmed = address.trim();
  final prefix = '${name.trim()},';
  if (trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
    return trimmed.substring(prefix.length).trim();
  }
  return trimmed;
}

enum SelectionSource {
  search,
  map,
  explore,
  saved,
  recent,
  home,
  work,
  frequent,
  longPress,
}

class SelectedPlace {
  const SelectedPlace(this.place, this.source, {required this.originMap});

  final PlaceSummary place;
  final SelectionSource source;
  final MapProvider originMap;
}

enum JourneyPhase { idle, searching, placeSelected, routePreview, navigating }

/// Provider choices are explicit. Google Places/Routes content is never
/// displayed on Mapbox merely because the renderer changed.
class ProviderPolicy {
  const ProviderPolicy(this.map);

  final MapProvider map;

  ProviderCapabilities get capabilities => switch (map) {
    MapProvider.google => const ProviderCapabilities(
      trafficAwareRouting: true,
      transitRouting: true,
      nativeTurnGuidance: true,
      persistProviderPlaces: true,
    ),
    MapProvider.mapbox => const ProviderCapabilities(
      trafficAwareRouting: false,
      transitRouting: false,
      nativeTurnGuidance: false,
      persistProviderPlaces: false,
    ),
  };

  String get searchProvider => switch (map) {
    MapProvider.google => 'geoapify',
    MapProvider.mapbox => 'mapbox',
  };
  String get placeProvider => switch (map) {
    MapProvider.google => 'google',
    MapProvider.mapbox => 'mapbox',
  };
  String get routingProvider => switch (map) {
    MapProvider.google => 'google',
    MapProvider.mapbox => 'mapbox',
  };
  String get navigationEngine => switch (map) {
    MapProvider.google => 'google',
    MapProvider.mapbox => 'mapbox',
  };

  bool canDisplay(ProviderReference? reference) =>
      reference == null ||
      reference.provider == placeProvider ||
      (map == MapProvider.google && reference.provider == 'geoapify');
}

class ProviderCapabilities {
  const ProviderCapabilities({
    required this.trafficAwareRouting,
    required this.transitRouting,
    required this.nativeTurnGuidance,
    required this.persistProviderPlaces,
  });

  final bool trafficAwareRouting;
  final bool transitRouting;
  final bool nativeTurnGuidance;
  final bool persistProviderPlaces;
}
