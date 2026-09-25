import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../domain/map_provider.dart';
import 'provider_contracts.dart';

/// Google browse-map adapter. The controller callback remains an intentional
/// bridge for the existing Google Navigation SDK overlays during migration.
class GoogleMapRenderer extends StatefulWidget {
  const GoogleMapRenderer({
    super.key,
    required this.initialViewport,
    required this.onReady,
    required this.onControllerCreated,
    required this.onViewportChanged,
    required this.onUserPan,
    required this.onMapPlace,
    required this.onExploreMarker,
    required this.onBlankTap,
    this.mapId,
  });

  final MapViewportState initialViewport;
  final String? mapId;
  final ValueChanged<MapRenderer> onReady;
  final Future<void> Function(GoogleMapViewController) onControllerCreated;
  final ValueChanged<MapViewportState> onViewportChanged;
  final VoidCallback onUserPan;
  final ValueChanged<PlaceSummary> onMapPlace;
  final ValueChanged<String> onExploreMarker;
  final VoidCallback onBlankTap;

  @override
  State<GoogleMapRenderer> createState() => _GoogleMapRendererState();
}

class _GoogleMapRendererState extends State<GoogleMapRenderer>
    implements MapRenderer {
  GoogleMapViewController? _controller;
  late MapViewportState _viewport = widget.initialViewport;
  bool _userPanning = false;

  @override
  MapProvider get provider => MapProvider.google;

  @override
  MapViewportState get viewport => _viewport;

  LatLng _latLng(GeoPoint point) =>
      LatLng(latitude: point.latitude, longitude: point.longitude);

  @override
  Future<void> moveTo(MapViewportState viewport) async {
    _viewport = viewport;
    await _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _latLng(viewport.center),
          zoom: viewport.zoom,
          bearing: viewport.bearing,
          tilt: viewport.pitch,
        ),
      ),
    );
  }

  Future<void> _created(GoogleMapViewController controller) async {
    _controller = controller;
    widget.onReady(this);
    await widget.onControllerCreated(controller);
  }

  void _cameraMoved(CameraPosition camera) {
    _viewport = MapViewportState(
      center: GeoPoint(camera.target.latitude, camera.target.longitude),
      zoom: camera.zoom,
      bearing: camera.bearing,
      pitch: camera.tilt,
    );
    widget.onViewportChanged(_viewport);
  }

  @override
  Widget build(BuildContext context) => GoogleMapsMapView(
    key: const ValueKey('google-browse-map'),
    onViewCreated: (controller) => unawaited(_created(controller)),
    mapId: widget.mapId,
    initialCameraPosition: CameraPosition(
      target: _latLng(widget.initialViewport.center),
      zoom: widget.initialViewport.zoom,
      bearing: widget.initialViewport.bearing,
      tilt: widget.initialViewport.pitch,
    ),
    initialCompassEnabled: true,
    initialRotateGesturesEnabled: true,
    initialTiltGesturesEnabled: true,
    initialScrollGesturesEnabledDuringRotateOrZoom: true,
    initialMapColorScheme: MapColorScheme.followSystem,
    onCameraMoveStarted: (_, isGesture) => _userPanning = isGesture,
    onCameraMove: _cameraMoved,
    onCameraIdle: (_) {
      if (_userPanning) {
        _userPanning = false;
        widget.onUserPan();
      }
    },
    onPoiClicked: (poi) => widget.onMapPlace(
      PlaceSummary(
        name: poi.name,
        location: GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
        reference: poi.placeID.isEmpty
            ? null
            : ProviderReference('google', poi.placeID),
      ),
    ),
    onMarkerClicked: widget.onExploreMarker,
    onMapClicked: (_) => widget.onBlankTap(),
    onMapLongClicked: (point) => widget.onMapPlace(
      PlaceSummary(
        name:
            '${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)}',
        location: GeoPoint(point.latitude, point.longitude),
        kind: PlaceKind.coordinate,
      ),
    ),
  );
}
