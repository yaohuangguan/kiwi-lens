import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../domain/map_layer_settings.dart';
import '../domain/map_provider.dart';
import '../domain/safety_camera.dart';
import 'location_marker_art.dart';
import 'provider_contracts.dart';

void initializeMapboxMaps(String accessToken) {
  if (accessToken.isNotEmpty) {
    mb.MapboxOptions.setAccessToken(accessToken);
  }
}

class MapboxMapRenderer extends StatefulWidget {
  const MapboxMapRenderer({
    super.key,
    required this.initialViewport,
    required this.layers,
    required this.locationMarker,
    required this.locationEnabled,
    required this.moving,
    required this.language,
    required this.cameras,
    required this.route,
    required this.selectedPlace,
    required this.explorePlaces,
    required this.onExplorePlace,
    required this.onReady,
    required this.onViewportChanged,
    required this.onMapPlace,
    required this.onUserPan,
    required this.onBlankTap,
  });

  final MapViewportState initialViewport;
  final MapLayerSettings layers;
  final LocationMarkerStyle locationMarker;
  final bool locationEnabled;
  final bool moving;
  final String language;
  final List<SafetyCamera> cameras;
  final List<GeoPoint> route;
  final PlaceSummary? selectedPlace;
  final List<PlaceSummary> explorePlaces;
  final ValueChanged<PlaceSummary> onExplorePlace;
  final ValueChanged<MapRenderer> onReady;
  final ValueChanged<MapViewportState> onViewportChanged;
  final ValueChanged<PlaceSummary> onMapPlace;
  final VoidCallback onUserPan;
  final VoidCallback onBlankTap;

  @override
  State<MapboxMapRenderer> createState() => _MapboxMapRendererState();
}

class _MapboxMapRendererState extends State<MapboxMapRenderer>
    implements MapRenderer {
  mb.MapboxMap? _map;
  mb.CircleAnnotationManager? _cameraManager;
  mb.CircleAnnotationManager? _selectedManager;
  mb.CircleAnnotationManager? _exploreManager;
  final Map<String, PlaceSummary> _exploreAnnotations = {};
  mb.PolylineAnnotationManager? _routeManager;
  int _syncVersion = 0;
  Future<void> _overlayQueue = Future<void>.value();
  bool _userPanning = false;
  late MapViewportState _viewport = widget.initialViewport;

  @override
  MapProvider get provider => MapProvider.mapbox;

  @override
  MapViewportState get viewport => _viewport;

  mb.Point _point(GeoPoint point) =>
      mb.Point(coordinates: mb.Position(point.longitude, point.latitude));

  GeoPoint _geo(mb.Point point) => GeoPoint(
    point.coordinates.lat.toDouble(),
    point.coordinates.lng.toDouble(),
  );

  String get _styleUri => switch (widget.layers.style) {
    BaseMapStyle.standard => mb.MapboxStyles.STANDARD,
    BaseMapStyle.satellite => mb.MapboxStyles.STANDARD_SATELLITE,
    BaseMapStyle.terrain => mb.MapboxStyles.OUTDOORS,
    BaseMapStyle.hybrid => mb.MapboxStyles.SATELLITE_STREETS,
  };

  @override
  void didUpdateWidget(covariant MapboxMapRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layers.style != widget.layers.style) {
      final map = _map;
      if (map != null) unawaited(map.loadStyleURI(_styleUri));
    }
    if (oldWidget.locationMarker != widget.locationMarker ||
        oldWidget.locationEnabled != widget.locationEnabled ||
        oldWidget.moving != widget.moving) {
      unawaited(_setLocationPuck());
    }
    if (!listEquals(oldWidget.cameras, widget.cameras) ||
        !listEquals(oldWidget.route, widget.route) ||
        oldWidget.selectedPlace != widget.selectedPlace ||
        !listEquals(oldWidget.explorePlaces, widget.explorePlaces) ||
        oldWidget.layers != widget.layers) {
      unawaited(_syncOverlays());
    }
  }

  @override
  Future<void> moveTo(MapViewportState viewport) async {
    _viewport = viewport;
    await _map?.easeTo(
      mb.CameraOptions(
        center: _point(viewport.center),
        zoom: viewport.zoom,
        bearing: viewport.bearing,
        pitch: viewport.pitch,
      ),
      mb.MapAnimationOptions(duration: 400),
    );
  }

  Future<void> _onCreated(mb.MapboxMap map) async {
    _map = map;
    map.addInteraction(
      mb.TapInteraction.onMap((gesture) => unawaited(_onTap(gesture))),
    );
    map.addInteraction(mb.LongTapInteraction.onMap(_onLongTap));
    _cameraManager = await map.annotations.createCircleAnnotationManager();
    _routeManager = await map.annotations.createPolylineAnnotationManager();
    _selectedManager = await map.annotations.createCircleAnnotationManager();
    _exploreManager = await map.annotations.createCircleAnnotationManager();
    _exploreManager!.tapEvents(
      onTap: (annotation) {
        final place = _exploreAnnotations[annotation.id];
        if (place != null) widget.onExplorePlace(place);
      },
    );
    await _setLocationPuck();
    if (!mounted || !identical(_map, map)) return;
    widget.onReady(this);
    await _syncOverlays();
  }

  Future<void> _setLocationPuck() async {
    final map = _map;
    if (map == null) return;
    final style = widget.locationMarker;
    final image = style == LocationMarkerStyle.classic
        ? null
        : await LocationMarkerArt.png(style);
    if (!mounted || !identical(_map, map)) return;
    await map.location.updateSettings(
      mb.LocationComponentSettings(
        enabled: widget.locationEnabled,
        showAccuracyRing: true,
        accuracyRingColor: const Color(0x443B9DFF).toARGB32(),
        puckBearingEnabled: style != LocationMarkerStyle.classic,
        puckBearing: widget.moving
            ? mb.PuckBearing.COURSE
            : mb.PuckBearing.HEADING,
        locationPuck: image == null
            ? null
            : mb.LocationPuck(
                locationPuck2D: mb.LocationPuck2D(bearingImage: image),
              ),
      ),
    );
  }

  Future<void> _syncOverlays() {
    final version = ++_syncVersion;
    _overlayQueue = _overlayQueue
        .then((_) async {
          if (!mounted || version != _syncVersion) return;
          await _renderOverlays(version);
        })
        .catchError((Object _) {
          // The native map can disappear during a rapid provider switch.
        });
    return _overlayQueue;
  }

  Future<void> _renderOverlays(int version) async {
    final cameras = _cameraManager;
    final selected = _selectedManager;
    final routes = _routeManager;
    final explore = _exploreManager;
    if (cameras == null ||
        selected == null ||
        routes == null ||
        explore == null) {
      return;
    }
    await cameras.deleteAll();
    await routes.deleteAll();
    await selected.deleteAll();
    await explore.deleteAll();
    _exploreAnnotations.clear();
    if (!mounted || version != _syncVersion) return;

    final visibleCameras = widget.cameras
        .where(widget.layers.shows)
        .map(
          (camera) => mb.CircleAnnotationOptions(
            geometry: _point(GeoPoint(camera.latitude, camera.longitude)),
            circleRadius: 7,
            circleColor: switch (CameraKindLabel.fromCamera(camera)) {
              CameraKind.speed => const Color(0xFF1670B9).toARGB32(),
              CameraKind.redLight => const Color(0xFFD95640).toARGB32(),
              CameraKind.lane => const Color(0xFF735CC8).toARGB32(),
              CameraKind.other => const Color(0xFF325A77).toARGB32(),
            },
            circleStrokeColor: Colors.white.toARGB32(),
            circleStrokeWidth: 2,
          ),
        )
        .toList(growable: false);
    if (visibleCameras.isNotEmpty) await cameras.createMulti(visibleCameras);
    if (!mounted || version != _syncVersion) return;
    for (final place in widget.explorePlaces) {
      if (version != _syncVersion) {
        return;
      }
      final annotation = await explore.create(
        mb.CircleAnnotationOptions(
          geometry: _point(place.location),
          circleRadius: 9,
          circleColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeColor: const Color(0xFF1479FF).toARGB32(),
          circleStrokeWidth: 3,
        ),
      );
      _exploreAnnotations[annotation.id] = place;
    }
    if (!mounted || version != _syncVersion) return;

    if (widget.route.length >= 2) {
      await routes.create(
        mb.PolylineAnnotationOptions(
          geometry: mb.LineString(
            coordinates: widget.route
                .map((point) => mb.Position(point.longitude, point.latitude))
                .toList(growable: false),
          ),
          lineColor: const Color(0xFF1479FF).toARGB32(),
          lineWidth: 7,
          lineOpacity: 0.9,
        ),
      );
    }
    if (!mounted || version != _syncVersion) return;
    final place = widget.selectedPlace;
    if (place != null) {
      await selected.create(
        mb.CircleAnnotationOptions(
          geometry: _point(place.location),
          circleRadius: 12,
          circleColor: const Color(0xFF1479FF).toARGB32(),
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 4,
        ),
      );
    }
  }

  void _cameraChanged(mb.CameraChangedEventData event) {
    final state = event.cameraState;
    _viewport = MapViewportState(
      center: _geo(state.center),
      zoom: state.zoom,
      bearing: state.bearing,
      pitch: state.pitch,
    );
    widget.onViewportChanged(_viewport);
  }

  Future<void> _onTap(mb.MapContentGestureContext gesture) async {
    final map = _map;
    if (map == null) return;
    try {
      final features = await map.queryRenderedFeatures(
        mb.RenderedQueryGeometry.fromScreenCoordinate(gesture.touchPosition),
        mb.RenderedQueryOptions(),
      );
      for (final result in features) {
        final properties = result?.queriedFeature.feature['properties'];
        if (properties is! Map) continue;
        final name =
            (widget.language == 'zh'
                ? properties['name_zh']?.toString()
                : properties['name_en']?.toString()) ??
            properties['name']?.toString();
        if (name == null || name.trim().isEmpty) continue;
        final category = properties['class']?.toString() ?? '';
        if (category == 'road' || category == 'landuse') continue;
        widget.onMapPlace(
          PlaceSummary(
            name: name,
            location: _geo(gesture.point),
            category: category,
          ),
        );
        return;
      }
      widget.onBlankTap();
    } catch (_) {
      widget.onBlankTap();
    }
  }

  void _onLongTap(mb.MapContentGestureContext gesture) {
    widget.onMapPlace(
      PlaceSummary(
        name:
            '${gesture.point.coordinates.lat.toStringAsFixed(5)}, '
            '${gesture.point.coordinates.lng.toStringAsFixed(5)}',
        location: _geo(gesture.point),
        kind: PlaceKind.coordinate,
      ),
    );
  }

  @override
  void dispose() {
    ++_syncVersion;
    _map = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => mb.MapWidget(
    key: const ValueKey('mapbox-browse-map'),
    styleUri: _styleUri,
    viewport: mb.CameraViewportState(
      center: _point(widget.initialViewport.center),
      zoom: widget.initialViewport.zoom,
      bearing: widget.initialViewport.bearing,
      pitch: widget.initialViewport.pitch,
    ),
    onMapCreated: _onCreated,
    onStyleLoadedListener: (_) => unawaited(_syncOverlays()),
    onCameraChangeListener: _cameraChanged,
    onScrollListener: (_) => _userPanning = true,
    onMapIdleListener: (_) {
      if (_userPanning) {
        _userPanning = false;
        widget.onUserPan();
      }
    },
  );
}
