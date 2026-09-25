import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import 'data/account_repository.dart';
import 'data/explore_repository.dart';
import 'data/place_details_repository.dart';
import 'data/route_repository.dart';
import 'domain/radar_geometry.dart';
import 'domain/map_layer_settings.dart';
import 'domain/map_provider.dart';
import 'domain/geo_math.dart';
import 'domain/route_option.dart';
import 'drive/device_heading.dart';
import 'drive/drive_engine.dart';
import 'providers/google_map_renderer.dart';
import 'providers/mapbox_map_renderer.dart';
import 'providers/mapbox_navigation_engine.dart';
import 'providers/mapbox_routing_provider.dart';
import 'providers/place_search_providers.dart';
import 'providers/provider_contracts.dart';
import 'widgets/map_symbols.dart';
import 'widgets/mapbox_navigation_overlay.dart';
import 'widgets/drive_hud.dart';
import 'widgets/explore_search.dart';
import 'widgets/explore_page.dart';
import 'widgets/full_screen_search.dart';
import 'widgets/navigation_overlay.dart';
import 'widgets/place_details_content.dart';
import 'widgets/profile_page.dart';
import 'widgets/map_layer_sheet.dart';
import 'widgets/splash_gate.dart';
import 'widgets/route_preview_sheet.dart';
import 'widgets/transit_trip_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KiwiLensApp());
}

class KiwiLensApp extends StatelessWidget {
  const KiwiLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    const kiwiGreen = Color(0xFFC8F169);
    const ink = Color(0xFF0B1717);

    return MaterialApp(
      title: 'Kiwi Lens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kiwiGreen,
          brightness: Brightness.light,
          surface: const Color(0xFFF6F8F4),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8F4),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
      ),
      home: const SplashGate(child: MapHomePage()),
    );
  }
}

class MapHomePage extends StatefulWidget {
  const MapHomePage({super.key});

  @override
  State<MapHomePage> createState() => _MapHomePageState();
}

class _MapHomePageState extends State<MapHomePage> {
  static const _mapId = String.fromEnvironment('MAP_ID');
  static const _mapboxToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  static const _auckland = LatLng(latitude: -36.8485, longitude: 174.7633);

  final DriveEngine _driveEngine = DriveEngine();
  late final MapboxNavigationEngine _mapboxNavigation;
  final AccountRepository _account = AccountRepository();
  final PlaceDetailsRepository _placeDetailsRepository =
      PlaceDetailsRepository();
  final RouteRepository _routeRepository = RouteRepository();
  final WorkerSearchProvider _workerSearch = WorkerSearchProvider();
  late final MapboxSearchProvider _mapboxSearch = MapboxSearchProvider(
    _mapboxToken,
  );
  late final MapboxRoutingProvider _mapboxRoutes = MapboxRoutingProvider(
    _mapboxToken,
  );
  MapProvider _mapProvider = MapProvider.google;
  MapProvider? _requestedMapProvider;
  Future<void> _providerSwitchQueue = Future<void>.value();
  LocationMarkerStyle _locationMarker = LocationMarkerStyle.kiwi;
  MapRenderer? _browseRenderer;
  MapViewportState _viewport = const MapViewportState(
    center: GeoPoint(-36.8485, 174.7633),
  );
  GeoPoint _areaSearchAnchor = const GeoPoint(-36.8485, 174.7633);
  bool _showSearchArea = false;
  List<PlaceSummary> _exploreResults = const [];
  List<Marker> _exploreMarkers = [];
  final Map<String, PlaceSummary> _exploreMarkerPlaces = {};
  final ValueNotifier<PlaceSummary?> _exploreMarkerFocus =
      ValueNotifier<PlaceSummary?>(null);
  List<String> _quickActions = [
    'Home',
    'Work',
    'Frequent',
    'Restaurants',
    'Shopping',
    'Gas',
  ];
  final Map<String, PlaceSummary> _quickLocations = {};
  final Map<String, MapProvider> _quickLocationProviders = {};
  GoogleMapViewController? _browseController;
  GoogleNavigationViewController? _navigationController;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<double>? _headingSubscription;
  Timer? _mapRefreshTimer;
  LatLng? _gpsLocation;
  DestinationSuggestion? _manualOrigin;
  final List<DestinationSuggestion> _guestRecent = [];
  CameraPosition? _lastBrowseCamera;
  List<Marker> _cameraMarkers = [];
  Marker? _carMarker;
  Circle? _accuracyCircle;
  String _markerSignature = '';
  bool _markerSyncing = false;
  bool _useCarMarker = false;
  MapLayerSettings _layers = const MapLayerSettings();
  bool _northUp = false;
  bool _junctionZoomed = false;
  String _appLanguage = 'en';
  String _voiceLanguage = 'en-NZ';
  double? _gpsAccuracy;
  double? _deviceHeading;
  double? _travelHeading;
  double? _smoothedLocationHeading;
  Polygon? _radarPolygon;
  bool _mapRefreshing = false;
  bool _refreshAgain = false;
  bool _following = true;
  bool _voiceEnabled = true;
  bool _lanesEnabled = true;
  String _destinationTitle = 'Destination';
  RoutePlan? _routePlan;
  KiwiTravelMode _selectedMode = KiwiTravelMode.drive;
  String? _selectedRouteId;
  bool _routePreviewLoading = false;
  int _routeRequest = 0;
  bool _transitTripRunning = false;
  RouteOption? _activeTransitRoute;
  RouteOption? _activeNavigationRoute;
  final List<DestinationSuggestion> _routeStops = <DestinationSuggestion>[];

  SelectedPlace? _selectedPlace;
  JourneyPhase _journeyPhase = JourneyPhase.idle;
  PointOfInterest? get _selectedPoi {
    final place = _selectedPlace?.place;
    if (place == null) return null;
    return PointOfInterest(
      placeID: place.reference?.provider == 'google' ? place.reference!.id : '',
      name: place.name,
      latLng: LatLng(
        latitude: place.location.latitude,
        longitude: place.location.longitude,
      ),
    );
  }

  PlaceDetails? _placeDetails;
  bool _placeDetailsLoading = false;
  String? _placeDetailsError;
  int _placeDetailsRequest = 0;
  bool _navigationSessionInitialized = false;
  bool _guidanceRunning = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _mapboxNavigation = MapboxNavigationEngine(_driveEngine);
    initializeMapboxMaps(_mapboxToken);
    _account.addListener(_onAccountChanged);
    _driveEngine.addListener(_onEngineChanged);
    unawaited(_account.restore());
    unawaited(_driveEngine.loadCameras());
    unawaited(_restoreMapSettings());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startTracking());
    });
  }

  void _onAccountChanged() {
    if (mounted) setState(() {});
  }

  void _onEngineChanged() {
    if (!mounted) return;
    final distance = _driveEngine.navInfo?.distanceToCurrentStepMeters;
    final shouldZoom =
        _guidanceRunning && _following && distance != null && distance < 200;
    if (shouldZoom != _junctionZoomed) {
      _junctionZoomed = shouldZoom;
      final controller = _navigationController;
      if (controller != null && _following) {
        unawaited(
          controller.followMyLocation(
            _northUp
                ? CameraPerspective.topDownNorthUp
                : CameraPerspective.tilted,
            zoomLevel: shouldZoom ? 18.5 : 16.0,
          ),
        );
      }
    }
    final signature =
        '${_driveEngine.cameras.length}:${_driveEngine.routeCameras.map((match) => match.camera.id).join(',')}:${_layers.markerSignature}';
    if (signature != _markerSignature) {
      unawaited(_syncCameraMarkers());
      if (_routePlan != null || _mapProvider == MapProvider.mapbox) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    }
  }

  Future<void> _restoreMapSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _useCarMarker = prefs.getBool('kiwi.map.car_marker') ?? false;
    _mapProvider = MapProvider.values.firstWhere(
      (value) => value.name == prefs.getString('kiwi.map.provider'),
      orElse: () => MapProvider.google,
    );
    if (_mapProvider == MapProvider.mapbox && _mapboxToken.isEmpty) {
      _mapProvider = MapProvider.google;
    }
    _locationMarker = LocationMarkerStyle.values.firstWhere(
      (value) => value.name == prefs.getString('kiwi.map.location_marker'),
      orElse: () => LocationMarkerStyle.kiwi,
    );
    _useCarMarker = _locationMarker != LocationMarkerStyle.classic;
    _quickActions = prefs.getStringList('kiwi.quick_actions') ?? _quickActions;
    if (_mapProvider == MapProvider.google) _restoreGoogleRecent(prefs);
    for (final action in ['Home', 'Work']) {
      final record = prefs.getString('kiwi.quick_location.$action');
      if (record == null) continue;
      try {
        final item = jsonDecode(record) as Map<String, dynamic>;
        _quickLocations[action] = PlaceSummary(
          name: item['name']?.toString() ?? action,
          address: item['address']?.toString() ?? '',
          location: GeoPoint(
            (item['latitude'] as num).toDouble(),
            (item['longitude'] as num).toDouble(),
          ),
        );
        _quickLocationProviders[action] = MapProvider.google;
      } catch (_) {
        // Ignore an invalid old shortcut rather than blocking map startup.
      }
    }
    _appLanguage = prefs.getString('kiwi.app.language') ?? 'en';
    _voiceLanguage = prefs.getString('kiwi.voice.language') ?? 'en-NZ';
    _voiceEnabled = prefs.getBool('kiwi.voice.enabled') ?? true;
    _lanesEnabled = prefs.getBool('kiwi.nav.lanes') ?? true;
    _driveEngine.voiceEnabled = _voiceEnabled;
    _layers = MapLayerSettings(
      cameras: prefs.getBool('kiwi.layers.cameras') ?? true,
      speed: prefs.getBool('kiwi.layers.speed') ?? true,
      redLight: prefs.getBool('kiwi.layers.red_light') ?? true,
      lane: prefs.getBool('kiwi.layers.lane') ?? true,
      other: prefs.getBool('kiwi.layers.other') ?? true,
      traffic: prefs.getBool('kiwi.layers.traffic') ?? true,
      style: BaseMapStyle.values.firstWhere(
        (value) => value.name == prefs.getString('kiwi.layers.style'),
        orElse: () => BaseMapStyle.standard,
      ),
    );
    await _driveEngine.setVoiceLanguage(_voiceLanguage);
    final controller = _driveEngine.active
        ? _navigationController
        : _browseController;
    if (controller != null) {
      await _applyMapLayers(controller);
      await controller.setMyLocationEnabled(!_useCarMarker || _guidanceRunning);
      _markerSignature = '';
      unawaited(_syncCameraMarkers());
      _queueMapRefresh();
    }
    if (mounted) setState(() {});
  }

  List<DestinationSuggestion> get _recentDestinations {
    final profile = _account.profile;
    if (profile == null || _mapProvider == MapProvider.mapbox) {
      return _guestRecent;
    }
    return profile.recentDestinations
        .map((item) {
          final latitude = item['latitude'];
          final longitude = item['longitude'];
          if (latitude is! num || longitude is! num) return null;
          return DestinationSuggestion(
            label: item['label']?.toString() ?? 'Recent destination',
            location: LatLng(
              latitude: latitude.toDouble(),
              longitude: longitude.toDouble(),
            ),
          );
        })
        .whereType<DestinationSuggestion>()
        .toList(growable: false);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _headingSubscription?.cancel();
    _mapRefreshTimer?.cancel();
    _account.removeListener(_onAccountChanged);
    _driveEngine.removeListener(_onEngineChanged);
    _mapboxNavigation.dispose();
    _exploreMarkerFocus.dispose();
    _workerSearch.dispose();
    _mapboxSearch.dispose();
    _mapboxRoutes.dispose();
    _account.dispose();
    _placeDetailsRepository.dispose();
    _driveEngine.dispose();
    if (_navigationSessionInitialized) {
      GoogleMapsNavigator.cleanup();
    }
    super.dispose();
  }

  Future<bool> _ensureLocationPermission() async {
    final whenInUse = await Permission.locationWhenInUse.request();
    if (whenInUse.isGranted || whenInUse.isLimited) return true;

    if (!mounted) return false;
    setState(() {
      _message = whenInUse.isPermanentlyDenied
          ? 'Location is disabled for Kiwi Lens. Enable it in system settings.'
          : 'Location permission is required for navigation.';
    });
    return false;
  }

  Future<void> _startTracking() async {
    if (_positionSubscription != null || !await _ensureLocationPermission()) {
      return;
    }
    _headingSubscription = DeviceHeading.readings.listen(
      (heading) {
        _deviceHeading = heading;
        _queueMapRefresh();
      },
      onError: (_) {
        /* iOS simulator and non-iOS use GPS course. */
      },
    );
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 2,
          ),
        ).listen(
          _onPosition,
          onError: (Object error) {
            if (mounted) {
              setState(() => _message = 'Location unavailable: $error');
            }
          },
        );
    try {
      _onPosition(
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
          ),
        ),
      );
    } catch (_) {
      /* The location stream will retry. */
    }
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    _gpsLocation = LatLng(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    _gpsAccuracy = position.accuracy.isFinite ? position.accuracy : null;
    if (position.speed >= 1.5 &&
        position.heading.isFinite &&
        position.heading >= 0) {
      _travelHeading = position.heading % 360;
    } else {
      _travelHeading = null;
    }
    setState(() {});
    _queueMapRefresh();
  }

  void _queueMapRefresh() {
    _mapRefreshTimer?.cancel();
    _mapRefreshTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_refreshMap()),
    );
  }

  Future<void> _refreshMap() async {
    if (_mapProvider == MapProvider.mapbox) {
      final location = _gpsLocation;
      if (_following && location != null && _browseRenderer != null) {
        await _browseRenderer!.moveTo(
          _viewport.copyWith(
            center: GeoPoint(location.latitude, location.longitude),
            zoom: _mapboxNavigation.active ? 16 : _viewport.zoom,
          ),
        );
      }
      return;
    }
    if (_mapRefreshing) {
      _refreshAgain = true;
      return;
    }
    final controller = _driveEngine.active
        ? _navigationController
        : _browseController;
    final location = _gpsLocation;
    final heading = _deviceHeading ?? _travelHeading;
    if (controller == null || location == null) return;
    _mapRefreshing = true;
    try {
      if (heading != null) {
        final options = PolygonOptions(
          points: radarSector(location, heading),
          fillColor: const Color(0x332196F3),
          strokeColor: const Color(0xAA1976D2),
          strokeWidth: 1.4,
          geodesic: true,
          zIndex: 5,
        );
        if (_radarPolygon == null) {
          final polygon = (await controller.addPolygons([options])).first;
          if (controller ==
              (_driveEngine.active
                  ? _navigationController
                  : _browseController)) {
            _radarPolygon = polygon;
          }
        } else {
          final polygon = (await controller.updatePolygons([
            _radarPolygon!.copyWith(options: options),
          ])).first;
          if (controller ==
              (_driveEngine.active
                  ? _navigationController
                  : _browseController)) {
            _radarPolygon = polygon;
          }
        }
      } else if (_radarPolygon != null) {
        await controller.removePolygons([_radarPolygon!]);
        _radarPolygon = null;
      }
      if (_useCarMarker && !_guidanceRunning) {
        await _syncCarMarker(controller, location);
      }
      // During Drive/Navigation the native SDK owns the camera. Manually
      // moving it on every GPS/heading update causes visible tug-of-war.
      if (_following && !_driveEngine.active) {
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: location, bearing: 0, tilt: 0, zoom: 16),
          ),
        );
      }
    } catch (_) {
      /* View may have been replaced during a mode change. */
    } finally {
      _mapRefreshing = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        _queueMapRefresh();
      }
    }
  }

  void _recenter() {
    _following = true;
    if (_mapProvider == MapProvider.mapbox) {
      _queueMapRefresh();
      return;
    }
    final navigationController = _navigationController;
    if (_driveEngine.active && navigationController != null) {
      unawaited(
        navigationController.followMyLocation(
          _northUp
              ? CameraPerspective.topDownNorthUp
              : CameraPerspective.tilted,
        ),
      );
      return;
    }
    _queueMapRefresh();
  }

  Future<void> _rotateMap(double degrees) async {
    if (_mapProvider == MapProvider.mapbox) {
      _following = false;
      await _browseRenderer?.moveTo(
        _viewport.copyWith(bearing: (_viewport.bearing + degrees + 360) % 360),
      );
      return;
    }
    final controller = _driveEngine.active
        ? _navigationController
        : _browseController;
    if (controller == null) return;
    try {
      final camera = await controller.getCameraPosition();
      _following = false;
      await controller.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: camera.target,
            zoom: camera.zoom,
            tilt: camera.tilt,
            bearing: (camera.bearing + degrees + 360) % 360,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Map rotation unavailable: $error');
      }
    }
  }

  void _showRouteOverview() {
    _following = false;
    final controller = _navigationController;
    if (controller != null) unawaited(controller.showRouteOverview());
  }

  void _toggleCompass() {
    setState(() => _northUp = !_northUp);
    _recenter();
  }

  Future<void> _clearRoutePreview() async {
    ++_routeRequest;
    _driveEngine.setRoute(null);
    final controller = _browseController;
    if (controller != null) {
      try {
        await controller.clearPolylines();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _routePlan = null;
      _selectedRouteId = null;
      _selectedMode = KiwiTravelMode.drive;
      _routePreviewLoading = false;
      _selectedPlace = null;
      _journeyPhase = JourneyPhase.idle;
      _placeDetails = null;
      _placeDetailsLoading = false;
      _placeDetailsError = null;
      _placeDetailsRequest++;
      _routeStops.clear();
    });
  }

  Future<void> _loadRoutePreview(PointOfInterest poi) async {
    final origin = _manualOrigin?.location ?? _gpsLocation;
    if (origin == null) {
      setState(() => _message = 'Waiting for GPS before calculating routes.');
      return;
    }
    final request = ++_routeRequest;
    setState(() {
      _routePreviewLoading = true;
      _routePlan = null;
      _selectedMode = KiwiTravelMode.drive;
      _selectedRouteId = null;
      _message = null;
    });
    try {
      final plan = _mapProvider == MapProvider.mapbox
          ? await _mapboxRoutes.route(
              origin: GeoPoint(origin.latitude, origin.longitude),
              destination: GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
              stops: _routeStops
                  .map(
                    (stop) => GeoPoint(
                      stop.location.latitude,
                      stop.location.longitude,
                    ),
                  )
                  .toList(growable: false),
              language: _appLanguage,
            )
          : await _routeRepository.fetch(
              origin: origin,
              destination: poi.latLng,
              stops: _routeStops
                  .map((stop) => stop.location)
                  .toList(growable: false),
            );
      final firstDrive = plan.forMode(KiwiTravelMode.drive).firstOrNull;
      if (!mounted || request != _routeRequest) return;
      setState(() {
        _routePlan = plan;
        _selectedRouteId = firstDrive?.id;
        _journeyPhase = JourneyPhase.routePreview;
      });
      _driveEngine.setRoute(firstDrive);
      await _renderRoutePreview();
    } catch (error) {
      if (mounted && request == _routeRequest) {
        setState(() => _message = 'Could not preview routes: $error');
      }
    } finally {
      if (mounted && request == _routeRequest) {
        setState(() => _routePreviewLoading = false);
      }
    }
  }

  RouteOption? get _selectedRoute {
    final plan = _routePlan;
    if (plan == null) return null;
    for (final route in plan.forMode(_selectedMode)) {
      if (route.id == _selectedRouteId) return route;
    }
    return plan.forMode(_selectedMode).firstOrNull;
  }

  Color _trafficColor(String speed, bool active) {
    final alpha = active ? 0xFF : 0x66;
    final rgb = speed == 'trafficJam'
        ? 0xEA4335
        : speed == 'slow'
        ? 0xF9AB00
        : speed == 'normal'
        ? 0x34A853
        : 0x087D58;
    return Color((alpha << 24) | rgb);
  }

  String _placeKey(PointOfInterest poi) => poi.placeID.isNotEmpty
      ? poi.placeID
      : 'coords:${poi.latLng.latitude.toStringAsFixed(5)},${poi.latLng.longitude.toStringAsFixed(5)}';

  bool _isFavorite(PointOfInterest poi) =>
      _account.profile?.places.any(
        (place) =>
            place['placeId'] == _placeKey(poi) && place['isFavorite'] == true,
      ) ??
      false;

  void _showProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePage(
          account: _account,
          voiceEnabled: _voiceEnabled,
          lanesEnabled: _lanesEnabled,
          appLanguage: _appLanguage,
          voiceLanguage: _voiceLanguage,
          onVoiceChanged: _setVoiceEnabled,
          onLanesChanged: _setLanesEnabled,
          onAppLanguageChanged: (value) => unawaited(_setAppLanguage(value)),
          onLanguageChanged: (value) => unawaited(_setVoiceLanguage(value)),
          onMapLayers: _showMapLayers,
          mapProvider: _mapProvider,
          locationMarker: _locationMarker,
          mapboxAvailable: _mapboxToken.isNotEmpty,
          onMapProviderChanged: (value) async {
            await _setMapProvider(value);
            return _mapProvider;
          },
          onLocationMarkerChanged: (value) =>
              unawaited(_setLocationMarker(value)),
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(PointOfInterest poi) async {
    if (_mapProvider == MapProvider.mapbox &&
        _selectedPlace?.source != SelectionSource.longPress) {
      setState(
        () => _message =
            'Saving Mapbox search/map content needs a storage licence. '
            'You can still use saved personal coordinates.',
      );
      return;
    }
    if (_account.profile == null) {
      _showProfile();
      return;
    }
    try {
      await _account.saveFavorite(
        placeId: _placeKey(poi),
        name: poi.name,
        latitude: poi.latLng.latitude,
        longitude: poi.latLng.longitude,
        favorite: !_isFavorite(poi),
      );
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }

  Future<void> _reviewPlace(PointOfInterest poi) async {
    if (_mapProvider == MapProvider.mapbox &&
        _selectedPlace?.source != SelectionSource.longPress) {
      setState(
        () => _message =
            'Reviews for Mapbox-sourced places are unavailable until '
            'persistent storage is licensed.',
      );
      return;
    }
    if (_account.profile == null) {
      _showProfile();
      return;
    }
    final existing = _account.profile?.reviews
        .where((review) => review['placeId'] == _placeKey(poi))
        .firstOrNull;
    final comment = TextEditingController(
      text: existing?['comment'] as String? ?? '',
    );
    var rating = (existing?['rating'] as num?)?.round() ?? 5;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            'My review · ${poi.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: rating,
                decoration: const InputDecoration(labelText: 'Rating'),
                items: [
                  for (var value = 1; value <= 5; value++)
                    DropdownMenuItem(
                      value: value,
                      child: Text('${'★' * value} ($value/5)'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) update(() => rating = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: comment,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Private comment',
                  border: OutlineInputBorder(),
                ),
              ),
              const Text(
                'Saved to Kiwi Lens only; not published to Google.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      try {
        await _account.saveReview(
          placeId: _placeKey(poi),
          placeName: poi.name,
          rating: rating,
          comment: comment.text.trim(),
        );
      } catch (error) {
        if (mounted) setState(() => _message = '$error');
      }
    }
    comment.dispose();
  }

  Future<void> _renderRoutePreview() async {
    final controller = _browseController;
    final plan = _routePlan;
    if (controller == null || plan == null) return;
    await controller.clearPolylines();
    final selected = _selectedRoute;
    final options = <PolylineOptions>[];

    for (final route in plan.forMode(_selectedMode)) {
      if (route.points.length < 2) continue;
      final active = route.id == selected?.id;
      options.add(
        PolylineOptions(
          points: route.points
              .map(
                (point) => LatLng(
                  latitude: point.latitude,
                  longitude: point.longitude,
                ),
              )
              .toList(growable: false),
          strokeColor: _selectedMode == KiwiTravelMode.drive
              ? (active ? const Color(0xCC60716A) : const Color(0x3560716A))
              : (active ? const Color(0xFF4285F4) : const Color(0x554285F4)),
          strokeWidth: active ? 8 : 6,
          zIndex: active ? 18 : 8,
          clickable: false,
        ),
      );

      if (_selectedMode == KiwiTravelMode.drive) {
        final intervals = route.trafficIntervals.isEmpty
            ? <TrafficInterval>[
                TrafficInterval(
                  startPolylinePointIndex: 0,
                  endPolylinePointIndex: route.points.length - 1,
                  speed: 'unknown',
                ),
              ]
            : route.trafficIntervals;
        for (final interval in intervals) {
          final start = interval.startPolylinePointIndex
              .clamp(0, route.points.length - 1)
              .toInt();
          if (start >= route.points.length - 1) continue;
          final end = interval.endPolylinePointIndex
              .clamp(start + 1, route.points.length - 1)
              .toInt();
          final segment = route.points.sublist(start, end + 1);
          if (segment.length < 2) continue;
          options.add(
            PolylineOptions(
              points: segment
                  .map(
                    (point) => LatLng(
                      latitude: point.latitude,
                      longitude: point.longitude,
                    ),
                  )
                  .toList(growable: false),
              strokeColor: _trafficColor(interval.speed, active),
              strokeWidth: active ? 8 : 6,
              zIndex: active ? 25 : 12,
              clickable: false,
            ),
          );
        }
      }
    }

    if (options.isNotEmpty) await controller.addPolylines(options);
    if (selected != null && selected.points.length >= 2) {
      final bounds = LatLngBounds.createBoundsFromPoints(
        selected.points
            .map(
              (point) =>
                  LatLng(latitude: point.latitude, longitude: point.longitude),
            )
            .toList(growable: false),
      );
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding: 72),
        duration: const Duration(milliseconds: 420),
      );
    }
  }

  void _selectMode(KiwiTravelMode mode) {
    final plan = _routePlan;
    if (plan == null || plan.forMode(mode).isEmpty) return;
    setState(() {
      _selectedMode = mode;
      _selectedRouteId = plan.forMode(mode).first.id;
    });
    _driveEngine.setRoute(_selectedRoute);
    unawaited(_renderRoutePreview());
  }

  void _selectRoute(RouteOption route) {
    setState(() => _selectedRouteId = route.id);
    _driveEngine.setRoute(route);
    unawaited(_renderRoutePreview());
  }

  Future<void> _addStop() async {
    final stop = await showModalBottomSheet<DestinationSuggestion>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 18,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
        ),
        child: ExploreSearch(
          currentLocation: _gpsLocation,
          onSelected: (selection) => Navigator.of(sheetContext).pop(selection),
        ),
      ),
    );
    if (stop == null || _selectedPoi == null) return;
    setState(() => _routeStops.add(stop));
    await _loadRoutePreview(_selectedPoi!);
  }

  Future<void> _saveCurrentRoute() async {
    final poi = _selectedPoi;
    final selected = _selectedRoute;
    if (poi == null || selected == null) return;
    if (_mapProvider == MapProvider.mapbox) {
      setState(
        () => _message =
            'Saving Mapbox route content requires a storage licence.',
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('kiwi.saved.routes') ?? <String>[];
    final record = jsonEncode({
      'savedAt': DateTime.now().toIso8601String(),
      'destination': {
        'name': poi.name,
        'latitude': poi.latLng.latitude,
        'longitude': poi.latLng.longitude,
      },
      'mode': selected.mode.apiValue,
      'provider': selected.provider,
      'durationSeconds': selected.durationSeconds,
      'distanceMeters': selected.distanceMeters,
      'stops': _routeStops
          .map(
            (stop) => {
              'label': stop.label,
              'latitude': stop.location.latitude,
              'longitude': stop.location.longitude,
            },
          )
          .toList(),
    });
    saved.removeWhere((item) {
      try {
        final existing = jsonDecode(item) as Map<String, dynamic>;
        final destination = existing['destination'] as Map<String, dynamic>?;
        return destination?['name'] == poi.name;
      } catch (_) {
        return false;
      }
    });
    saved.insert(0, record);
    if (saved.length > 20) saved.removeRange(20, saved.length);
    await prefs.setStringList('kiwi.saved.routes', saved);
    if (_account.profile != null && _mapProvider == MapProvider.google) {
      try {
        await _account.recordRoute(
          destinationName: poi.name,
          latitude: poi.latLng.latitude,
          longitude: poi.latLng.longitude,
          mode: selected.mode.apiValue,
          distanceMeters: selected.distanceMeters,
          durationSeconds: selected.durationSeconds,
        );
      } catch (_) {
        /* The on-device save remains available while offline. */
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route saved on this device')),
      );
    }
  }

  void _toggleVoice() => _setVoiceEnabled(!_voiceEnabled);

  void _setVoiceEnabled(bool value) {
    setState(() => _voiceEnabled = value);
    _driveEngine.voiceEnabled = value;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool('kiwi.voice.enabled', value),
      ),
    );
    unawaited(
      GoogleMapsNavigator.setAudioGuidance(
        NavigationAudioGuidanceSettings(
          guidanceType: value
              ? NavigationAudioGuidanceType.alertsAndGuidance
              : NavigationAudioGuidanceType.silent,
          isBluetoothAudioEnabled: true,
          isVibrationEnabled: true,
        ),
      ),
    );
  }

  void _setLanesEnabled(bool value) {
    setState(() => _lanesEnabled = value);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool('kiwi.nav.lanes', value),
      ),
    );
  }

  Future<bool> _ensureNavigationSession() async {
    final nativeInitialized = await GoogleMapsNavigator.isInitialized();
    if (_navigationSessionInitialized && nativeInitialized) {
      if (!_driveEngine.active) await _driveEngine.start();
      return true;
    }
    _navigationSessionInitialized = false;
    if (!await _ensureLocationPermission()) return false;

    if (!await GoogleMapsNavigator.areTermsAccepted()) {
      final accepted = await GoogleMapsNavigator.showTermsAndConditionsDialog(
        'Kiwi Lens Navigation',
        'Kiwi Lens',
      );
      if (!accepted) return false;
    }

    try {
      await GoogleMapsNavigator.initializeNavigationSession(
        taskRemovedBehavior: TaskRemovedBehavior.continueService,
      );
    } on SessionInitializationException catch (error) {
      if (!mounted) return false;
      final message = switch (error.code) {
        SessionInitializationError.termsNotAccepted =>
          'Accept the Google Navigation terms to continue.',
        SessionInitializationError.locationPermissionMissing =>
          'Location permission is required for navigation.',
        SessionInitializationError.notAuthorized => 'Navigation SDK authorization failed. Check the iOS API key and Bundle ID.',
      };
      setState(() => _message = message);
      return false;
    }
    await GoogleMapsNavigator.setAudioGuidance(
      NavigationAudioGuidanceSettings(
        guidanceType: _voiceEnabled
            ? NavigationAudioGuidanceType.alertsAndGuidance
            : NavigationAudioGuidanceType.silent,
        isBluetoothAudioEnabled: true,
        isVibrationEnabled: true,
      ),
    );
    _navigationSessionInitialized = await GoogleMapsNavigator.isInitialized();
    if (!_navigationSessionInitialized) {
      if (mounted) {
        setState(
          () => _message = 'Navigation session did not finish initializing. Please try again.',
        );
      }
      return false;
    }
    try {
      await _driveEngine.start();
    } on SessionNotInitializedException {
      await GoogleMapsNavigator.initializeNavigationSession(
        taskRemovedBehavior: TaskRemovedBehavior.continueService,
      );
      _navigationSessionInitialized = await GoogleMapsNavigator.isInitialized();
      if (!_navigationSessionInitialized) return false;
      await _driveEngine.start();
    }
    return true;
  }

  NavigationTravelMode? get _nativeTravelMode => switch (_selectedMode) {
    KiwiTravelMode.drive => NavigationTravelMode.driving,
    KiwiTravelMode.walk => NavigationTravelMode.walking,
    KiwiTravelMode.bicycle => NavigationTravelMode.cycling,
    KiwiTravelMode.transit => null,
  };

  Future<void> _startTransitTrip(PointOfInterest poi, RouteOption route) async {
    setState(() {
      _transitTripRunning = true;
      _activeTransitRoute = route;
      _destinationTitle = poi.name;
      _selectedPlace = null;
      _journeyPhase = JourneyPhase.idle;
      _following = true;
    });
    await _driveEngine.speakMessage(
      'Transit trip started. Follow the itinerary.',
    );
    _queueMapRefresh();
  }

  Future<void> _stopTransitTrip() async {
    if (!_transitTripRunning) return;
    final route = _activeTransitRoute;
    if (_account.profile != null && route != null && route.points.isNotEmpty) {
      final destination = route.points.last;
      unawaited(
        _account
            .recordRoute(
              destinationName: _destinationTitle,
              latitude: destination.latitude,
              longitude: destination.longitude,
              mode: KiwiTravelMode.transit.apiValue,
              distanceMeters: route.distanceMeters,
              durationSeconds: route.durationSeconds,
            )
            .catchError((_) {}),
      );
    }
    setState(() {
      _transitTripRunning = false;
      _activeTransitRoute = null;
      _destinationTitle = 'Destination';
    });
  }

  Future<void> _navigateToSelectedPoi() async {
    final poi = _selectedPoi;
    final selectedRoute = _selectedRoute;
    if (poi == null || selectedRoute == null || _busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      if (_mapProvider == MapProvider.mapbox) {
        if (!await _ensureLocationPermission()) return;
        await _mapboxNavigation.start(selectedRoute);
        if (!mounted) return;
        setState(() {
          _guidanceRunning = true;
          _destinationTitle = poi.name;
          _activeNavigationRoute = selectedRoute;
          _routePlan = null;
          _selectedRouteId = null;
          _selectedPlace = null;
          _journeyPhase = JourneyPhase.navigating;
          _routeStops.clear();
          _following = true;
        });
        _queueMapRefresh();
        return;
      }
      if (_selectedMode == KiwiTravelMode.transit) {
        await _startTransitTrip(poi, selectedRoute);
        return;
      }

      if (!await _ensureNavigationSession()) return;

      final hasNavigationLocation = await _driveEngine
          .waitForRoadSnappedLocation();
      if (!hasNavigationLocation) {
        if (mounted) {
          setState(() {
            _message =
                'Waiting for an accurate GPS fix before starting navigation.';
          });
        }
        return;
      }

      final routeToken = selectedRoute.routeToken;
      final travelMode = _nativeTravelMode!;
      final useRouteToken =
          _selectedMode == KiwiTravelMode.drive &&
          routeToken != null &&
          routeToken.isNotEmpty;
      final status = await GoogleMapsNavigator.setDestinations(
        Destinations(
          waypoints: <NavigationWaypoint>[
            for (final stop in _routeStops)
              NavigationWaypoint.withLatLngTarget(
                title: stop.label,
                target: stop.location,
              ),
            if (poi.placeID.isNotEmpty)
              NavigationWaypoint.withPlaceID(
                title: poi.name,
                placeID: poi.placeID,
              )
            else
              NavigationWaypoint.withLatLngTarget(
                title: poi.name,
                target: poi.latLng,
              ),
          ],
          displayOptions: NavigationDisplayOptions(
            showDestinationMarkers: true,
            showStopSigns: true,
            showTrafficLights: true,
          ),
          routeTokenOptions: useRouteToken
              ? RouteTokenOptions(
                  routeToken: routeToken,
                  travelMode: travelMode,
                )
              : null,
          routingOptions: !useRouteToken
              ? RoutingOptions(
                  travelMode: travelMode,
                  alternateRoutesStrategy:
                      NavigationAlternateRoutesStrategy.one,
                )
              : null,
        ),
      );

      if (status != NavigationRouteStatus.statusOk) {
        if (!mounted) return;
        setState(() {
          _message =
              status == NavigationRouteStatus.locationUnavailable ||
                  status == NavigationRouteStatus.locationUnknown
              ? 'Waiting for a GPS fix. Try again once your location is available.'
              : 'Route unavailable: ${status.name}';
        });
        return;
      }

      _driveEngine.setRoute(selectedRoute);
      await GoogleMapsNavigator.startGuidance();
      await _navigationController?.setNavigationUIEnabled(true);
      await _navigationController?.followMyLocation(CameraPerspective.tilted);
      if (_useCarMarker && _navigationController != null) {
        final controller = _navigationController!;
        if (_carMarker != null) {
          try {
            await controller.removeMarkers([_carMarker!]);
          } catch (_) {}
          _carMarker = null;
        }
        await controller.setMyLocationEnabled(true);
      }
      if (!mounted) return;
      setState(() {
        _guidanceRunning = true;
        _destinationTitle = poi.name;
        _activeNavigationRoute = selectedRoute;
        _routePlan = null;
        _selectedRouteId = null;
        _selectedPlace = null;
        _journeyPhase = JourneyPhase.navigating;
        _routeStops.clear();
        _following = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Could not start navigation: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopNavigation() async {
    if (!_guidanceRunning) return;
    if (_mapboxNavigation.active) {
      // Search Box and Directions content stays session-scoped. Persisting
      // Mapbox-derived route data needs a separate storage entitlement.
      await _mapboxNavigation.stop();
      if (!mounted) return;
      setState(() {
        _guidanceRunning = false;
        _activeNavigationRoute = null;
        _destinationTitle = 'Destination';
        _journeyPhase = JourneyPhase.idle;
      });
      return;
    }
    final route = _activeNavigationRoute;
    if (_account.profile != null && route != null && route.points.isNotEmpty) {
      final destination = route.points.last;
      unawaited(
        _account
            .recordRoute(
              destinationName: _destinationTitle,
              latitude: destination.latitude,
              longitude: destination.longitude,
              mode: _selectedMode.apiValue,
              distanceMeters: route.distanceMeters,
              durationSeconds: route.durationSeconds,
            )
            .catchError((_) {}),
      );
    }
    _driveEngine.setRoute(null);
    await GoogleMapsNavigator.stopGuidance();
    await GoogleMapsNavigator.clearDestinations();
    await _navigationController?.setNavigationUIEnabled(false);
    await _navigationController?.followMyLocation(CameraPerspective.tilted);
    if (!mounted) return;
    setState(() {
      _guidanceRunning = false;
      _junctionZoomed = false;
      _activeNavigationRoute = null;
      _destinationTitle = 'Destination';
    });
    if (_useCarMarker && _navigationController != null) {
      await _navigationController!.setMyLocationEnabled(false);
      _queueMapRefresh();
    }
  }

  Future<void> _startDriveMode() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_gpsLocation == null) {
        await _startTracking();
      }
      if (_gpsLocation == null) {
        if (mounted) {
          setState(
            () => _message =
                'Waiting for current GPS position before opening Drive Mode.',
          );
        }
        return;
      }
      if (_mapProvider == MapProvider.mapbox) {
        await _driveEngine.startLocal();
        if (mounted) setState(() {});
        return;
      }
      _lastBrowseCamera =
          await _browseController?.getCameraPosition() ?? _lastBrowseCamera;
      if (!await _ensureNavigationSession()) return;
      if (!await _driveEngine.waitForRoadSnappedLocation()) {
        await _driveEngine.stop();
        await GoogleMapsNavigator.cleanup();
        _navigationSessionInitialized = false;
        if (mounted) {
          setState(
            () => _message =
                'Waiting for a road-snapped GPS fix. Try Drive Mode again.',
          );
        }
        return;
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not start Drive Mode: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopDriveMode() async {
    if (_guidanceRunning) await _stopNavigation();
    await _driveEngine.stop();
    if (_navigationSessionInitialized) {
      await GoogleMapsNavigator.cleanup();
      _navigationSessionInitialized = false;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadPlaceDetails(PointOfInterest poi) async {
    final request = ++_placeDetailsRequest;
    if (poi.placeID.isEmpty) {
      if (mounted) {
        setState(() {
          _placeDetails = null;
          _placeDetailsLoading = false;
          _placeDetailsError = null;
        });
      }
      return;
    }
    setState(() {
      _placeDetails = null;
      _placeDetailsLoading = true;
      _placeDetailsError = null;
    });
    try {
      final details = await _placeDetailsRepository.fetch(
        poi.placeID,
        language: _appLanguage,
      );
      if (!mounted || request != _placeDetailsRequest) return;
      setState(() {
        _placeDetails = details;
        _placeDetailsLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _placeDetailsRequest) return;
      setState(() {
        _placeDetailsLoading = false;
        _placeDetailsError = 'More place details are temporarily unavailable.';
      });
    }
  }

  void _onPoiClicked(PointOfInterest poi) {
    if (_driveEngine.active || _transitTripRunning) return;
    _selectPlace(
      PlaceSummary(
        name: poi.name,
        location: GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
        reference: poi.placeID.isEmpty
            ? null
            : ProviderReference('google', poi.placeID),
      ),
      SelectionSource.map,
    );
  }

  void _selectPlace(PlaceSummary place, SelectionSource source) {
    if (_driveEngine.active || _transitTripRunning) return;
    if (!const ProviderPolicy(MapProvider.google).canDisplay(place.reference) &&
        _mapProvider == MapProvider.google) {
      setState(() => _message = 'This place cannot be shown on Google Maps.');
      return;
    }
    if (_mapProvider == MapProvider.mapbox &&
        !const ProviderPolicy(MapProvider.mapbox).canDisplay(place.reference)) {
      setState(() => _message = 'This place belongs to another map provider.');
      return;
    }
    setState(() {
      _selectedPlace = SelectedPlace(place, source, originMap: _mapProvider);
      _journeyPhase = JourneyPhase.placeSelected;
      _routePlan = null;
      _selectedRouteId = null;
      _message = null;
    });
    if (place.reference?.provider == 'google') {
      unawaited(_loadPlaceDetails(_selectedPoi!));
    } else {
      _placeDetailsRequest++;
      _placeDetails = null;
      _placeDetailsLoading = false;
      _placeDetailsError = null;
    }
    if (_mapProvider == MapProvider.mapbox &&
        (source == SelectionSource.map ||
            source == SelectionSource.longPress) &&
        place.address.isEmpty) {
      unawaited(_enrichMapboxSelection(place, source));
    }
  }

  Future<void> _enrichMapboxSelection(
    PlaceSummary original,
    SelectionSource source,
  ) async {
    try {
      final resolved = await _mapboxSearch.reverseNear(
        original.location,
        language: _appLanguage,
        preferredName:
            original.kind == PlaceKind.coordinate &&
                source != SelectionSource.longPress
            ? ''
            : original.name,
      );
      if (!mounted ||
          resolved == null ||
          _mapProvider != MapProvider.mapbox ||
          !identical(_selectedPlace?.place, original)) {
        return;
      }
      setState(
        () => _selectedPlace = SelectedPlace(
          PlaceSummary(
            name:
                original.kind == PlaceKind.coordinate &&
                    source != SelectionSource.longPress
                ? resolved.name
                : original.name,
            location: original.location,
            address: resolved.address,
            category: original.category.isEmpty
                ? resolved.category
                : original.category,
            kind:
                original.kind == PlaceKind.coordinate &&
                    source != SelectionSource.longPress
                ? resolved.kind
                : original.kind,
            reference: source == SelectionSource.longPress
                ? null
                : resolved.reference,
          ),
          source,
          originMap: _mapProvider,
        ),
      );
    } catch (_) {
      // A map feature remains selectable if reverse lookup is unavailable.
    }
  }

  void _rememberDestination(DestinationSuggestion suggestion) {
    _guestRecent.removeWhere((item) => item.label == suggestion.label);
    _guestRecent.insert(0, suggestion);
    if (_guestRecent.length > 12) _guestRecent.removeLast();
    if (_mapProvider == MapProvider.google) {
      unawaited(_persistGoogleRecent());
    }
    if (_account.profile != null && _mapProvider == MapProvider.google) {
      unawaited(
        _account
            .recordDestination(
              label: suggestion.label,
              latitude: suggestion.location.latitude,
              longitude: suggestion.location.longitude,
            )
            .catchError((_) {}),
      );
    }
  }

  void _restoreGoogleRecent(SharedPreferences prefs) {
    _guestRecent.clear();
    for (final record
        in prefs.getStringList('kiwi.recent.google') ?? const []) {
      try {
        final item = jsonDecode(record) as Map<String, dynamic>;
        _guestRecent.add(
          DestinationSuggestion(
            label: item['label']?.toString() ?? '',
            name: item['name']?.toString(),
            address: item['address']?.toString(),
            location: LatLng(
              latitude: (item['latitude'] as num).toDouble(),
              longitude: (item['longitude'] as num).toDouble(),
            ),
          ),
        );
      } catch (_) {
        // A malformed historic record should not prevent search.
      }
    }
  }

  Future<void> _persistGoogleRecent() async {
    final records = [
      for (final item in _guestRecent)
        jsonEncode({
          'label': item.label,
          'name': item.name,
          'address': item.address,
          'latitude': item.location.latitude,
          'longitude': item.location.longitude,
        }),
    ];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('kiwi.recent.google', records);
  }

  Future<void> _syncCameraMarkers() async {
    if (_markerSyncing) return;
    final controller = _driveEngine.active
        ? _navigationController
        : _browseController;
    if (controller == null || _driveEngine.cameras.isEmpty) return;
    _markerSyncing = true;
    final signature =
        '${_driveEngine.cameras.length}:${_driveEngine.routeCameras.map((match) => match.camera.id).join(',')}:${_layers.markerSignature}';
    try {
      try {
        await MapSymbols.ensureRegistered();
      } catch (_) {
        /* Default pins remain visible. */
      }
      if (_cameraMarkers.isNotEmpty) {
        await controller.removeMarkers(_cameraMarkers);
      }
      final onRoute = _driveEngine.routeCameras
          .map((match) => match.camera.id)
          .toSet();
      final options = [
        for (final camera in _driveEngine.cameras)
          if (_layers.shows(camera))
            MarkerOptions(
              position: LatLng(
                latitude: camera.latitude,
                longitude: camera.longitude,
              ),
              icon:
                  MapSymbols.camera(
                    CameraKindLabel.fromCamera(camera),
                    onRoute: onRoute.contains(camera.id),
                  ) ??
                  ImageDescriptor.defaultImage,
              zIndex: onRoute.contains(camera.id) ? 40 : 12,
              infoWindow: InfoWindow(
                title: '${camera.type} · ${camera.location}',
                snippet:
                    '${camera.suburb} · GPS ${camera.latitude.toStringAsFixed(5)}, ${camera.longitude.toStringAsFixed(5)}',
              ),
            ),
      ];
      _cameraMarkers = options.isEmpty
          ? []
          : (await controller.addMarkers(options)).whereType<Marker>().toList();
      _markerSignature = signature;
    } catch (_) {
      _markerSignature = signature;
    } finally {
      _markerSyncing = false;
      final latest =
          '${_driveEngine.cameras.length}:${_driveEngine.routeCameras.map((match) => match.camera.id).join(',')}:${_layers.markerSignature}';
      if (mounted && _markerSignature != latest) {
        Future<void>.delayed(
          const Duration(milliseconds: 200),
          _syncCameraMarkers,
        );
      }
    }
  }

  Future<void> _syncCarMarker(
    GoogleMapViewController controller,
    LatLng location,
  ) async {
    try {
      await MapSymbols.ensureRegistered();
      if (_guidanceRunning) return;
      final heading = _travelHeading ?? _deviceHeading ?? 0;
      final previous = _smoothedLocationHeading;
      final delta = previous == null
          ? 0.0
          : (heading - previous + 540) % 360 - 180;
      _smoothedLocationHeading = previous == null
          ? heading
          : (previous + delta * 0.35 + 360) % 360;
      final options = MarkerOptions(
        position: location,
        icon:
            MapSymbols.location(_locationMarker) ??
            MapSymbols.car ??
            ImageDescriptor.defaultImage,
        zIndex: 80,
        flat: true,
        rotation: _smoothedLocationHeading!,
        anchor: const MarkerAnchor(u: 0.5, v: 0.5),
      );
      if (_carMarker == null) {
        _carMarker = (await controller.addMarkers([options])).first;
      } else {
        _carMarker = (await controller.updateMarkers([
          _carMarker!.copyWith(options: options),
        ])).first;
      }
      final accuracy = _gpsAccuracy;
      if (accuracy != null && accuracy > 0) {
        final halo = CircleOptions(
          position: location,
          radius: accuracy.clamp(5, 150).toDouble(),
          strokeWidth: 1,
          strokeColor: const Color(0x882E86C9),
          fillColor: const Color(0x222E86C9),
          zIndex: 1,
        );
        if (_accuracyCircle == null) {
          _accuracyCircle = (await controller.addCircles([halo])).first;
        } else {
          _accuracyCircle = (await controller.updateCircles([
            _accuracyCircle!.copyWith(options: halo),
          ])).first;
        }
      }
    } catch (_) {
      /* The native location indicator remains the fallback. */
    }
  }

  Future<void> _setCarMarker(bool value) async {
    setState(() => _useCarMarker = value);
    final controller = _driveEngine.active
        ? _navigationController
        : _browseController;
    if (controller != null) {
      // Navigation's built-in chevron is retained during active guidance.
      await controller.setMyLocationEnabled(!value || _guidanceRunning);
      if ((!value || _guidanceRunning) && _carMarker != null) {
        try {
          await controller.removeMarkers([_carMarker!]);
        } catch (_) {}
        _carMarker = null;
      } else if (value && _gpsLocation != null) {
        await _syncCarMarker(controller, _gpsLocation!);
      }
      if ((!value || _guidanceRunning) && _accuracyCircle != null) {
        try {
          await controller.removeCircles([_accuracyCircle!]);
        } catch (_) {}
        _accuracyCircle = null;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('kiwi.map.car_marker', value);
    _queueMapRefresh();
  }

  Future<void> _setLocationMarker(LocationMarkerStyle style) async {
    setState(() => _locationMarker = style);
    await _setCarMarker(style != LocationMarkerStyle.classic);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kiwi.map.location_marker', style.name);
    if (_carMarker != null) {
      final controller = _driveEngine.active
          ? _navigationController
          : _browseController;
      if (controller != null) {
        try {
          await controller.removeMarkers([_carMarker!]);
        } catch (_) {}
        _carMarker = null;
      }
    }
    _queueMapRefresh();
  }

  Future<void> _setMapProvider(MapProvider provider) {
    _requestedMapProvider = provider;
    _providerSwitchQueue = _providerSwitchQueue
        .then((_) {
          if (_requestedMapProvider != provider) return Future<void>.value();
          return _applyMapProvider(provider);
        })
        .catchError((Object error) {
          if (mounted) {
            setState(() => _message = 'Could not switch maps: $error');
          }
        });
    return _providerSwitchQueue;
  }

  Future<void> _applyMapProvider(MapProvider provider) async {
    if (provider == _mapProvider) return;
    if (provider == MapProvider.mapbox && _mapboxToken.isEmpty) return;
    if (_guidanceRunning || _driveEngine.active || _transitTripRunning) {
      setState(
        () =>
            _message = 'End the current trip before changing the map provider.',
      );
      return;
    }
    final googleCamera = await _browseController?.getCameraPosition();
    if (!mounted) return;
    if (googleCamera != null) {
      _viewport = MapViewportState(
        center: GeoPoint(
          googleCamera.target.latitude,
          googleCamera.target.longitude,
        ),
        zoom: googleCamera.zoom,
        bearing: googleCamera.bearing,
        pitch: googleCamera.tilt,
      );
    } else if (_browseRenderer != null) {
      _viewport = _browseRenderer!.viewport;
    }
    _browseController = null;
    _browseRenderer = null;
    _lastBrowseCamera = null;
    _cameraMarkers = [];
    _carMarker = null;
    _accuracyCircle = null;
    _exploreMarkers = [];
    _exploreMarkerPlaces.clear();
    _exploreResults = const [];
    _guestRecent.clear();
    _showSearchArea = false;
    _areaSearchAnchor = _viewport.center;
    _radarPolygon = null;
    _markerSignature = '';
    final wasPreviewing = _journeyPhase == JourneyPhase.routePreview;
    final selected = _selectedPlace;
    _routePlan = null;
    _selectedRouteId = null;
    _driveEngine.setRoute(null);
    ++_routeRequest;
    final needsNewPlaceContent =
        selected != null &&
        (selected.originMap != provider &&
                selected.place.kind != PlaceKind.coordinate ||
            !ProviderPolicy(provider).canDisplay(selected.place.reference));
    if (needsNewPlaceContent) {
      _selectedPlace = SelectedPlace(
        PlaceSummary(
          name:
              '${selected.place.location.latitude.toStringAsFixed(5)}, '
              '${selected.place.location.longitude.toStringAsFixed(5)}',
          location: selected.place.location,
          kind: PlaceKind.coordinate,
        ),
        selected.source,
        originMap: provider,
      );
      _placeDetails = null;
      _placeDetailsLoading = false;
      _placeDetailsError = null;
    }
    setState(() {
      _mapProvider = provider;
      _journeyPhase = selected == null
          ? JourneyPhase.idle
          : JourneyPhase.placeSelected;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kiwi.map.provider', provider.name);
    if (provider == MapProvider.google) _restoreGoogleRecent(prefs);
    if (wasPreviewing && _selectedPoi != null) {
      unawaited(_loadRoutePreview(_selectedPoi!));
    }
    if (provider == MapProvider.mapbox && needsNewPlaceContent) {
      unawaited(_enrichMapboxSelection(_selectedPlace!.place, selected.source));
    }
  }

  Future<void> _applyMapLayers(GoogleMapViewController controller) async {
    await controller.settings.setTrafficEnabled(_layers.traffic);
    final style = _driveEngine.active && _layers.style == BaseMapStyle.terrain
        ? BaseMapStyle.standard
        : _layers.style;
    await controller.setMapType(
      mapType: switch (style) {
        BaseMapStyle.standard => MapType.normal,
        BaseMapStyle.satellite => MapType.satellite,
        BaseMapStyle.terrain => MapType.terrain,
        BaseMapStyle.hybrid => MapType.hybrid,
      },
    );
  }

  Future<void> _setMapLayers(MapLayerSettings value) async {
    setState(() => _layers = value);
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('kiwi.layers.cameras', value.cameras),
      prefs.setBool('kiwi.layers.speed', value.speed),
      prefs.setBool('kiwi.layers.red_light', value.redLight),
      prefs.setBool('kiwi.layers.lane', value.lane),
      prefs.setBool('kiwi.layers.other', value.other),
      prefs.setBool('kiwi.layers.traffic', value.traffic),
      prefs.setString('kiwi.layers.style', value.style.name),
    ]);
    final controller = _driveEngine.active
        ? _navigationController
        : _browseController;
    if (controller != null) {
      await _applyMapLayers(controller);
      unawaited(_syncCameraMarkers());
    }
  }

  void _showMapLayers() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => MapLayerSheet(
        settings: _layers,
        mapProvider: _mapProvider,
        language: _appLanguage,
        onChanged: (value) => unawaited(_setMapLayers(value)),
      ),
    );
  }

  Future<void> _setVoiceLanguage(String language) async {
    setState(() => _voiceLanguage = language);
    await _driveEngine.setVoiceLanguage(language);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kiwi.voice.language', language);
  }

  Future<void> _setAppLanguage(String language) async {
    final next = language == 'zh' ? 'zh' : 'en';
    setState(() => _appLanguage = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kiwi.app.language', next);
  }

  String _text(String english, String chinese) =>
      _appLanguage == 'zh' ? chinese : english;

  void _showNavigationSettings() => _showProfile();

  void _showDirections() {
    final route = _activeNavigationRoute;
    if (route == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .65,
        child: ListView(
          children: [
            const ListTile(
              title: Text(
                'Directions',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ),
            if (route.steps.isEmpty)
              const ListTile(
                title: Text('Turn list is not available for this route.'),
              ),
            for (final step in route.steps)
              ListTile(
                leading: const Icon(Icons.turn_right_rounded),
                title: Text(step.instruction),
                subtitle: Text('${step.distanceMeters} m'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareTripSnapshot() async {
    final nav = _driveEngine.navInfo;
    final remaining = nav?.distanceToFinalDestinationMeters;
    final arrival = nav?.timeToFinalDestinationSeconds;
    final details =
        'Kiwi Lens trip to $_destinationTitle. '
        'Remaining: ${remaining == null ? 'unknown' : '${(remaining / 1000).toStringAsFixed(1)} km'}. '
        'ETA: ${arrival == null ? 'unknown' : DateTime.now().add(Duration(seconds: arrival)).toLocal().toString().substring(0, 16)}. '
        'This is an ETA snapshot, not live location sharing.';
    if (!mounted) return;
    try {
      await const MethodChannel('kiwi_lens/share')
          .invokeMethod<void>('shareText', {'text': details});
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: details));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ETA snapshot copied to clipboard')),
        );
      }
    }
  }

  void _showAlongRouteSearch() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
        ),
        child: ExploreSearch(
          currentLocation: _gpsLocation,
          recent: _recentDestinations,
          onSelected: (selection) {
            Navigator.of(sheetContext).pop();
            unawaited(_addAlongRouteStop(selection));
          },
        ),
      ),
    );
  }

  Future<void> _addAlongRouteStop(DestinationSuggestion stop) async {
    final route = _activeNavigationRoute;
    final origin = _driveEngine.snappedLocation ?? _gpsLocation;
    if (route == null || route.points.isEmpty || origin == null) return;
    final destination = route.points.last;
    try {
      final plan = await _routeRepository.fetch(
        origin: origin,
        destination: LatLng(
          latitude: destination.latitude,
          longitude: destination.longitude,
        ),
        stops: [stop.location],
      );
      final next = plan.forMode(_selectedMode).firstOrNull;
      if (next == null) throw StateError('No route via this stop');
      final status = await GoogleMapsNavigator.setDestinations(
        Destinations(
          waypoints: [
            NavigationWaypoint.withLatLngTarget(
              title: stop.label,
              target: stop.location,
            ),
            NavigationWaypoint.withLatLngTarget(
              title: _destinationTitle,
              target: LatLng(
                latitude: destination.latitude,
                longitude: destination.longitude,
              ),
            ),
          ],
          displayOptions: NavigationDisplayOptions(
            showDestinationMarkers: true,
          ),
          routingOptions: RoutingOptions(
            travelMode: _nativeTravelMode!,
            alternateRoutesStrategy: NavigationAlternateRoutesStrategy.one,
          ),
        ),
      );
      if (status != NavigationRouteStatus.statusOk) {
        throw StateError(status.name);
      }
      _driveEngine.setRoute(next);
      setState(() => _activeNavigationRoute = next);
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not add stop: $error');
    }
  }

  Future<void> _showSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRoutes = prefs.getStringList('kiwi.saved.routes') ?? [];
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .65,
        child: ListView(
          children: [
            const ListTile(
              title: Text(
                'Saved places & routes',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ),
            for (final place
                in _account.profile?.places ?? <Map<String, dynamic>>[])
              ListTile(
                leading: const Icon(Icons.bookmark_rounded),
                title: Text(place['name']?.toString() ?? 'Saved place'),
                onTap: () {
                  final latitude = place['latitude'],
                      longitude = place['longitude'];
                  if (latitude is! num || longitude is! num) return;
                  final id = place['placeId']?.toString() ?? '';
                  if (_mapProvider == MapProvider.mapbox &&
                      id.isNotEmpty &&
                      !id.startsWith('coords:')) {
                    Navigator.of(sheetContext).pop();
                    setState(
                      () => _message = 'This saved Google place is available on Google Maps.',
                    );
                    return;
                  }
                  Navigator.of(sheetContext).pop();
                  _selectPlace(
                    PlaceSummary(
                      name: place['name']?.toString() ?? 'Saved place',
                      address: place['address']?.toString() ?? '',
                      location: GeoPoint(
                        latitude.toDouble(),
                        longitude.toDouble(),
                      ),
                      reference: id.isNotEmpty && !id.startsWith('coords:')
                          ? ProviderReference('google', id)
                          : null,
                    ),
                    SelectionSource.saved,
                  );
                },
              ),
            for (final record in savedRoutes)
              Builder(
                builder: (context) {
                  try {
                    final data = jsonDecode(record) as Map<String, dynamic>;
                    final place = data['destination'] as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.route_rounded),
                      title: Text(place['name']?.toString() ?? 'Saved route'),
                      onTap: () {
                        if (_mapProvider == MapProvider.mapbox &&
                            data['provider'] != 'mapbox') {
                          Navigator.of(sheetContext).pop();
                          setState(
                            () => _message =
                                'This saved route belongs to Google Maps.',
                          );
                          return;
                        }
                        Navigator.of(sheetContext).pop();
                        _selectPlace(
                          PlaceSummary(
                            name: place['name']?.toString() ?? 'Saved route',
                            location: GeoPoint(
                              (place['latitude'] as num).toDouble(),
                              (place['longitude'] as num).toDouble(),
                            ),
                          ),
                          SelectionSource.saved,
                        );
                      },
                    );
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                },
              ),
            if (savedRoutes.isEmpty &&
                (_account.profile?.places.isEmpty ?? true))
              const ListTile(
                title: Text('No saved places yet'),
                subtitle: Text('Tap the bookmark on a place to keep it here.'),
              ),
          ],
        ),
      ),
    );
  }

  void _showGoSearch() => unawaited(_openSearch());

  Future<void> _openSearch({String query = '', String? saveAs}) async {
    setState(() => _journeyPhase = JourneyPhase.searching);
    final SearchProvider provider = _workerSearch;
    final place = await Navigator.of(context).push<PlaceSummary>(
      PageRouteBuilder<PlaceSummary>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, animation, secondaryAnimation) => FullScreenSearch(
          provider: provider,
          resolve: (candidate) async {
            if (candidate.location != null) {
              return candidate.toPlace(candidate.location!);
            }
            final reference = candidate.reference;
            if (reference == null) {
              throw StateError('Place has no location');
            }
            return _mapboxSearch.resolve(reference, language: _appLanguage);
          },
          language: _appLanguage,
          currentLocation: _gpsLocation == null
              ? null
              : GeoPoint(_gpsLocation!.latitude, _gpsLocation!.longitude),
          recent: _recentDestinations
              .map(
                (item) => PlaceSummary(
                  name: item.name ?? item.label,
                  address: item.address ?? '',
                  location: GeoPoint(
                    item.location.latitude,
                    item.location.longitude,
                  ),
                ),
              )
              .toList(growable: false),
          initialQuery: query,
          onDriveMode: () => unawaited(_startDriveMode()),
        ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    if (place == null) {
      setState(
        () => _journeyPhase = _selectedPlace == null
            ? JourneyPhase.idle
            : JourneyPhase.placeSelected,
      );
      return;
    }
    if (saveAs != null) {
      _quickLocations[saveAs] = place;
      _quickLocationProviders[saveAs] = _mapProvider;
      if (_mapProvider == MapProvider.google) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'kiwi.quick_location.$saveAs',
          jsonEncode({
            'name': place.name,
            'address': place.address,
            'latitude': place.location.latitude,
            'longitude': place.location.longitude,
          }),
        );
      }
    }
    _rememberDestination(
      DestinationSuggestion(
        label: place.name,
        name: place.name,
        address: place.address,
        location: LatLng(
          latitude: place.location.latitude,
          longitude: place.location.longitude,
        ),
      ),
    );
    _selectPlace(place, SelectionSource.search);
    final controller = _browseController;
    if (controller != null) {
      unawaited(
        controller.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(
              latitude: place.location.latitude,
              longitude: place.location.longitude,
            ),
          ),
        ),
      );
    }
    await _browseRenderer?.moveTo(_viewport.copyWith(center: place.location));
  }

  Widget _buildQuickActions() => SizedBox(
    height: 43,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final action in _quickActions)
          Padding(
            padding: const EdgeInsets.only(right: 7),
            child: ActionChip(
              backgroundColor: const Color(0xFFF1F8DF),
              side: const BorderSide(color: Color(0xFFC8F169), width: 1.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              label: Text(action),
              onPressed: () => _onQuickAction(action),
            ),
          ),
        IconButton.filledTonal(
          tooltip: _text('Edit shortcuts', '编辑快捷入口'),
          onPressed: _editQuickActions,
          icon: const Icon(Icons.tune_rounded, size: 19),
        ),
      ],
    ),
  );

  void _onQuickAction(String action) {
    if (action == 'Home' || action == 'Work') {
      final place = _quickLocations[action];
      if (place != null && _quickLocationProviders[action] == _mapProvider) {
        _selectPlace(
          place,
          action == 'Home' ? SelectionSource.home : SelectionSource.work,
        );
        return;
      }
      unawaited(_openSearch(saveAs: action));
      return;
    }
    if (action == 'Frequent') {
      final recent = _recentDestinations;
      if (recent.isNotEmpty) {
        final item = recent.first;
        _selectPlace(
          PlaceSummary(
            name: item.name ?? item.label,
            address: item.address ?? '',
            location: GeoPoint(item.location.latitude, item.location.longitude),
          ),
          SelectionSource.frequent,
        );
        return;
      }
    }
    unawaited(_openSearch(query: action == 'Frequent' ? '' : action));
  }

  void _maybeShowSearchArea() {
    final center = _viewport.center;
    final moved = distanceMeters(
      center.latitude,
      center.longitude,
      _areaSearchAnchor.latitude,
      _areaSearchAnchor.longitude,
    );
    if (moved > 350 && !_showSearchArea && mounted) {
      setState(() => _showSearchArea = true);
    }
  }

  void _editQuickActions() {
    final actions = [..._quickActions];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, updateSheet) => SafeArea(
          child: SizedBox(
            height: 430,
            child: Column(
              children: [
                ListTile(
                  title: Text(_text('Edit shortcuts', '编辑快捷入口')),
                  subtitle: Text(
                    _text(
                      'Drag to reorder. Remove or add shortcuts any time.',
                      '拖动排序，可随时移除或添加。',
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView(
                    onReorderItem: (oldIndex, newIndex) {
                      updateSheet(() {
                        final item = actions.removeAt(oldIndex);
                        actions.insert(newIndex, item);
                      });
                    },
                    children: [
                      for (final action in actions)
                        ListTile(
                          key: ValueKey(action),
                          title: Text(action),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (action == 'Home' || action == 'Work')
                                IconButton(
                                  tooltip: _text('Set location', '设置地点'),
                                  icon: const Icon(
                                    Icons.edit_location_alt_outlined,
                                  ),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    unawaited(_openSearch(saveAs: action));
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () =>
                                    updateSheet(() => actions.remove(action)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final action in [
                      'Home',
                      'Work',
                      'Frequent',
                      'Restaurants',
                      'Shopping',
                      'Gas',
                    ])
                      if (!actions.contains(action))
                        ActionChip(
                          label: Text('+ $action'),
                          onPressed: () =>
                              updateSheet(() => actions.add(action)),
                        ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () async {
                      setState(() => _quickActions = actions);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setStringList('kiwi.quick_actions', actions);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Text(_text('Done', '完成')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _searchThisArea() {
    setState(() {
      _showSearchArea = false;
      _areaSearchAnchor = _viewport.center;
    });
    _showExplore(center: _viewport.center);
  }

  Future<void> _syncExploreMarkers() async {
    final controller = _browseController;
    if (controller == null || _mapProvider != MapProvider.google) return;
    try {
      if (_exploreMarkers.isNotEmpty) {
        await controller.removeMarkers(_exploreMarkers);
      }
      _exploreMarkers = [];
      _exploreMarkerPlaces.clear();
      if (_exploreResults.isEmpty) return;
      final markers = await controller.addMarkers([
        for (final place in _exploreResults)
          MarkerOptions(
            position: LatLng(
              latitude: place.location.latitude,
              longitude: place.location.longitude,
            ),
            zIndex: 30,
            consumeTapEvents: true,
            infoWindow: InfoWindow(title: place.name, snippet: place.address),
          ),
      ]);
      _exploreMarkers = markers.whereType<Marker>().toList(growable: false);
      for (
        var index = 0;
        index < _exploreMarkers.length && index < _exploreResults.length;
        index++
      ) {
        _exploreMarkerPlaces[_exploreMarkers[index].markerId] =
            _exploreResults[index];
      }
    } catch (_) {
      // The map may be recreated while changing providers.
    }
  }

  Future<void> _showExplore({GeoPoint? center}) async {
    final searchCenter =
        center ??
        (_gpsLocation == null
            ? _viewport.center
            : GeoPoint(_gpsLocation!.latitude, _gpsLocation!.longitude));
    final current = LatLng(
      latitude: searchCenter.latitude,
      longitude: searchCenter.longitude,
    );
    final place = await Navigator.of(context).push<ExplorePlace>(
      MaterialPageRoute(
        builder: (_) =>
            ExplorePage(currentLocation: current, language: _appLanguage),
      ),
    );
    if (!mounted || place == null) return;
    _selectPlace(
      PlaceSummary(
        name: place.name,
        address: place.address,
        category: place.primaryType,
        location: GeoPoint(place.latitude, place.longitude),
        reference: ProviderReference('google', place.placeId),
      ),
      SelectionSource.explore,
    );
  }

  Widget _buildBottomBar() {
    Widget item(IconData icon, String label, VoidCallback action) => Expanded(
      child: InkWell(
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 25, color: const Color(0xFF153B32)),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Material(
      color: Colors.white,
      elevation: 16,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            item(Icons.map_rounded, _text('Map', '地图'), _recenter),
            item(
              Icons.explore_rounded,
              _text('Explore', '探索'),
              () => unawaited(_showExplore()),
            ),
            Expanded(
              child: InkWell(
                onTap: _showGoSearch,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 49,
                        height: 39,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC8F169),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.directions_car_filled_rounded,
                              size: 21,
                              color: Color(0xFF0B1717),
                            ),
                            Icon(
                              Icons.pedal_bike_rounded,
                              size: 17,
                              color: Color(0xFF0B1717),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _text('Start', '出发'),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            item(
              Icons.bookmark_rounded,
              _text('Saved', '收藏'),
              () => unawaited(_showSaved()),
            ),
            item(Icons.person_rounded, _text('Me', '我的'), _showProfile),
          ],
        ),
      ),
    );
  }

  Future<void> _onMapViewCreated(GoogleMapViewController controller) async {
    _browseController = controller;
    _cameraMarkers = [];
    _carMarker = null;
    _accuracyCircle = null;
    _markerSignature = '';
    _navigationController = null;
    _radarPolygon = null;
    await _applyMapLayers(controller);
    await controller.settings.setCompassEnabled(true);
    await controller.settings.setRotateGesturesEnabled(true);
    await controller.settings.setTiltGesturesEnabled(true);
    await controller.settings.setScrollGesturesDuringRotateOrZoomEnabled(true);
    if (await Permission.locationWhenInUse.isGranted) {
      await controller.setMyLocationEnabled(!_useCarMarker);
    }
    await controller.setRecenterButtonEnabled(false);
    await _syncCameraMarkers();
    await _syncExploreMarkers();
    _queueMapRefresh();
  }

  Future<void> _onNavigationViewCreated(
    GoogleNavigationViewController controller,
  ) async {
    await controller.setMyLocationEnabled(!_useCarMarker || _guidanceRunning);
    await _applyMapLayers(controller);
    await controller.settings.setCompassEnabled(false);
    await controller.settings.setRotateGesturesEnabled(true);
    await controller.settings.setTiltGesturesEnabled(true);
    await controller.settings.setScrollGesturesDuringRotateOrZoomEnabled(true);
    _navigationController = controller;
    _browseController = null;
    _cameraMarkers = [];
    _carMarker = null;
    _accuracyCircle = null;
    _markerSignature = '';
    _radarPolygon = null;
    await controller.setNavigationHeaderEnabled(false);
    await controller.setNavigationFooterEnabled(false);
    await controller.setRecenterButtonEnabled(false);
    await controller.setReportIncidentButtonEnabled(false);
    // ignore: experimental_member_use
    await controller.setNavigationTripProgressBarEnabled(false);
    await controller.setSpeedometerEnabled(false);
    await controller.setSpeedLimitIconEnabled(false);
    await controller.setNavigationUIEnabled(_guidanceRunning);
    if (_driveEngine.snappedLocation != null) {
      await controller.followMyLocation(
        _northUp ? CameraPerspective.topDownNorthUp : CameraPerspective.tilted,
      );
    }
    await controller.setTrafficIncidentCardsEnabled(true);
    await controller.setTrafficPromptsEnabled(true);
    await controller.setPadding(const EdgeInsets.fromLTRB(16, 125, 16, 215));
    final activeRoute = _activeNavigationRoute;
    if (_selectedMode == KiwiTravelMode.drive &&
        activeRoute != null &&
        activeRoute.points.length >= 2) {
      final trafficOptions = <PolylineOptions>[];
      final intervals = activeRoute.trafficIntervals.isEmpty
          ? <TrafficInterval>[
              TrafficInterval(
                startPolylinePointIndex: 0,
                endPolylinePointIndex: activeRoute.points.length - 1,
                speed: 'unknown',
              ),
            ]
          : activeRoute.trafficIntervals;
      for (final interval in intervals) {
        final start = interval.startPolylinePointIndex
            .clamp(0, activeRoute.points.length - 1)
            .toInt();
        if (start >= activeRoute.points.length - 1) continue;
        final end = interval.endPolylinePointIndex
            .clamp(start + 1, activeRoute.points.length - 1)
            .toInt();
        trafficOptions.add(
          PolylineOptions(
            points: activeRoute.points
                .sublist(start, end + 1)
                .map(
                  (point) => LatLng(
                    latitude: point.latitude,
                    longitude: point.longitude,
                  ),
                )
                .toList(growable: false),
            strokeColor: _trafficColor(interval.speed, true),
            strokeWidth: 8,
            zIndex: 40,
            clickable: false,
          ),
        );
      }
      if (trafficOptions.isNotEmpty) {
        await controller.addPolylines(trafficOptions);
      }
    }
    await _syncCameraMarkers();
    _queueMapRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _driveEngine.active && _mapProvider == MapProvider.google
                ? GoogleMapsNavigationView(
                    key: const ValueKey('navigation-view'),
                    onViewCreated: _onNavigationViewCreated,
                    mapId: _mapId.isEmpty ? null : _mapId,
                    initialCameraPosition:
                        _lastBrowseCamera ??
                        CameraPosition(
                          target: _gpsLocation ?? _auckland,
                          zoom: 16,
                        ),
                    onCameraMoveStarted: (_, isGesture) {
                      if (isGesture) _following = false;
                    },
                    initialNavigationUIEnabledPreference: _guidanceRunning
                        ? NavigationUIEnabledPreference.automatic
                        : NavigationUIEnabledPreference.disabled,
                    initialCompassEnabled: false,
                    initialRotateGesturesEnabled: true,
                    initialTiltGesturesEnabled: true,
                    initialScrollGesturesEnabledDuringRotateOrZoom: true,
                    initialForceNightMode: NavigationForceNightMode.auto,
                    onPoiClicked: _onPoiClicked,
                  )
                : _mapProvider == MapProvider.mapbox
                ? MapboxMapRenderer(
                    key: const ValueKey('mapbox-browse-view'),
                    initialViewport: _viewport,
                    layers: _layers,
                    locationMarker: _locationMarker,
                    locationEnabled: _gpsLocation != null,
                    moving: _travelHeading != null,
                    language: _appLanguage,
                    cameras: _driveEngine.cameras,
                    route:
                        (_mapboxNavigation.route ?? _selectedRoute)?.points
                            .map(
                              (point) =>
                                  GeoPoint(point.latitude, point.longitude),
                            )
                            .toList(growable: false) ??
                        const [],
                    selectedPlace: _selectedPlace?.place,
                    explorePlaces: _exploreResults,
                    onExplorePlace: (place) =>
                        _exploreMarkerFocus.value = place,
                    onReady: (renderer) => _browseRenderer = renderer,
                    onViewportChanged: (viewport) => _viewport = viewport,
                    onUserPan: () {
                      _following = false;
                      _maybeShowSearchArea();
                    },
                    onMapPlace: (place) {
                      _selectPlace(
                        place,
                        place.kind == PlaceKind.coordinate
                            ? SelectionSource.longPress
                            : SelectionSource.map,
                      );
                    },
                    onBlankTap: () {
                      if (_selectedPlace != null || _routePlan != null) {
                        unawaited(_clearRoutePreview());
                      }
                    },
                  )
                : GoogleMapRenderer(
                    key: const ValueKey('browse-map-view'),
                    onControllerCreated: _onMapViewCreated,
                    onReady: (renderer) => _browseRenderer = renderer,
                    mapId: _mapId.isEmpty ? null : _mapId,
                    initialViewport: _lastBrowseCamera == null
                        ? _viewport.copyWith(
                            center: _gpsLocation == null
                                ? _viewport.center
                                : GeoPoint(
                                    _gpsLocation!.latitude,
                                    _gpsLocation!.longitude,
                                  ),
                          )
                        : MapViewportState(
                            center: GeoPoint(
                              _lastBrowseCamera!.target.latitude,
                              _lastBrowseCamera!.target.longitude,
                            ),
                            zoom: _lastBrowseCamera!.zoom,
                            bearing: _lastBrowseCamera!.bearing,
                            pitch: _lastBrowseCamera!.tilt,
                          ),
                    onViewportChanged: (viewport) {
                      _viewport = viewport;
                      _lastBrowseCamera = CameraPosition(
                        target: LatLng(
                          latitude: viewport.center.latitude,
                          longitude: viewport.center.longitude,
                        ),
                        zoom: viewport.zoom,
                        bearing: viewport.bearing,
                        tilt: viewport.pitch,
                      );
                    },
                    onUserPan: () {
                      _following = false;
                      _maybeShowSearchArea();
                    },
                    onMapPlace: (place) => _selectPlace(
                      place,
                      place.kind == PlaceKind.coordinate
                          ? SelectionSource.longPress
                          : SelectionSource.map,
                    ),
                    onExploreMarker: (markerId) {
                      final place = _exploreMarkerPlaces[markerId];
                      if (place != null) {
                        _exploreMarkerFocus.value = place;
                      }
                    },
                    onBlankTap: () {
                      if (_selectedPoi != null || _routePlan != null) {
                        unawaited(_clearRoutePreview());
                      }
                    },
                  ),
          ),
          if (!_driveEngine.active && !_transitTripRunning)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 18,
              right: 16,
              child: PointerInterceptor(
                child: Column(
                  children: [
                    Material(
                      color: Colors.white,
                      elevation: 5,
                      borderRadius: BorderRadius.circular(14),
                      child: IconButton(
                        tooltip: 'Map layers',
                        icon: const Icon(Icons.layers_rounded),
                        onPressed: _showMapLayers,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.white,
                      elevation: 5,
                      borderRadius: BorderRadius.circular(14),
                      child: IconButton(
                        tooltip: 'Rotate map left',
                        icon: const Icon(Icons.rotate_left_rounded),
                        onPressed: () => unawaited(_rotateMap(-45)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.white,
                      elevation: 5,
                      borderRadius: BorderRadius.circular(14),
                      child: IconButton(
                        tooltip: 'Rotate map right',
                        icon: const Icon(Icons.rotate_right_rounded),
                        onPressed: () => unawaited(_rotateMap(45)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.white,
                      elevation: 5,
                      borderRadius: BorderRadius.circular(14),
                      child: IconButton(
                        tooltip: 'Follow my location',
                        icon: const Icon(Icons.navigation_rounded),
                        onPressed: _recenter,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!_driveEngine.active && !_transitTripRunning)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              bottom: MediaQuery.paddingOf(context).bottom + 72,
              left: 16,
              right: 16,
              child: PointerInterceptor(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildQuickActions(),
                    const SizedBox(height: 9),
                    Material(
                      color: Colors.white,
                      elevation: 8,
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _showGoSearch,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 17,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search_rounded,
                                color: Color(0xFF1479FF),
                              ),
                              const SizedBox(width: 11),
                              Text(
                                _text('Where to?', '去哪儿？'),
                                style: const TextStyle(
                                  color: Color(0xFF61758A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_showSearchArea)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: FilledButton.icon(
                          onPressed: _searchThisArea,
                          icon: const Icon(Icons.refresh_rounded, size: 17),
                          label: Text(_text('Search this area', '搜索此区域')),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (_driveEngine.active &&
              _mapProvider == MapProvider.google &&
              _selectedPoi == null &&
              !_transitTripRunning)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _driveEngine,
                builder: (context, _) => _guidanceRunning
                    ? NavigationOverlay(
                        engine: _driveEngine,
                        destinationTitle: _destinationTitle,
                        gpsAccuracy: _gpsAccuracy,
                        voiceEnabled: _voiceEnabled,
                        lanesEnabled: _lanesEnabled,
                        onEnd: () => unawaited(_stopNavigation()),
                        onRecenter: _recenter,
                        onOverview: _showRouteOverview,
                        northUp: _northUp,
                        onCompassToggle: _toggleCompass,
                        onReport: () {
                          final controller = _navigationController;
                          if (controller != null) {
                            // ignore: experimental_member_use
                            unawaited(controller.showReportIncidentsPanel());
                          }
                        },
                        onSearchAlongRoute: _showAlongRouteSearch,
                        onDirections: _showDirections,
                        onShare: _shareTripSnapshot,
                        onSettings: _showNavigationSettings,
                        onLayers: _showMapLayers,
                        onVoiceToggle: _toggleVoice,
                        onLanesToggle: () => _setLanesEnabled(!_lanesEnabled),
                      )
                    : DriveHud(
                        engine: _driveEngine,
                        onStop: () => unawaited(_stopDriveMode()),
                      ),
              ),
            ),
          if (_mapboxNavigation.active)
            Positioned.fill(
              child: MapboxNavigationOverlay(
                engine: _mapboxNavigation,
                drive: _driveEngine,
                destination: _destinationTitle,
                language: _appLanguage,
                onEnd: () => unawaited(_stopNavigation()),
                onRecenter: _recenter,
              ),
            ),
          if (_mapProvider == MapProvider.mapbox &&
              _driveEngine.active &&
              !_guidanceRunning)
            Positioned.fill(
              child: DriveHud(
                engine: _driveEngine,
                onStop: () => unawaited(_stopDriveMode()),
              ),
            ),
          if (_message != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 76, 20, 0),
                  child: PointerInterceptor(
                    child: Material(
                      color: const Color(0xEE0B1717),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Text(
                          _message!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!_driveEngine.active &&
              !_transitTripRunning &&
              _selectedPoi == null)
            Align(
              alignment: Alignment.bottomCenter,
              child: PointerInterceptor(child: _buildBottomBar()),
            ),
          if (_selectedPoi != null &&
              !_driveEngine.active &&
              !_guidanceRunning &&
              !_transitTripRunning &&
              _routePlan == null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: PointerInterceptor(
                  child: _PlaceCard(
                    selectedPlace: _selectedPlace!.place,
                    details: _placeDetails,
                    detailsLoading: _placeDetailsLoading,
                    detailsError: _placeDetailsError,
                    busy: _routePreviewLoading,
                    onClose: () => unawaited(_clearRoutePreview()),
                    onNavigate: () =>
                        unawaited(_loadRoutePreview(_selectedPoi!)),
                    isFavorite: _isFavorite(_selectedPoi!),
                    onFavorite: () => unawaited(_toggleFavorite(_selectedPoi!)),
                    onReview: () => unawaited(_reviewPlace(_selectedPoi!)),
                  ),
                ),
              ),
            ),
          if (_transitTripRunning && _activeTransitRoute != null)
            Positioned.fill(
              child: TransitTripOverlay(
                destinationTitle: _destinationTitle,
                route: _activeTransitRoute!,
                gpsAccuracy: _gpsAccuracy,
                onEnd: () => unawaited(_stopTransitTrip()),
                onRecenter: _recenter,
              ),
            ),
          if (_selectedPoi != null &&
              _routePlan != null &&
              !_driveEngine.active &&
              !_guidanceRunning &&
              !_transitTripRunning)
            Align(
              alignment: Alignment.bottomCenter,
              child: RoutePreviewSheet(
                destinationTitle: _selectedPoi!.name,
                originTitle:
                    _manualOrigin?.label ?? _text('Current location', '当前位置'),
                plan: _routePlan!,
                selectedMode: _selectedMode,
                selectedRouteId: _selectedRouteId,
                busy: _busy,
                stopCount: _routeStops.length,
                cameraCount: _driveEngine.routeCameraCount,
                customOrigin: _manualOrigin != null,
                onModeChanged: _selectMode,
                onRouteSelected: _selectRoute,
                onStart: () => unawaited(_navigateToSelectedPoi()),
                onAddStop: () => unawaited(_addStop()),
                onSave: () => unawaited(_saveCurrentRoute()),
                isFavorite: _isFavorite(_selectedPoi!),
                onFavorite: () => unawaited(_toggleFavorite(_selectedPoi!)),
                onReview: () => unawaited(_reviewPlace(_selectedPoi!)),
                onClose: () => unawaited(_clearRoutePreview()),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.selectedPlace,
    required this.details,
    required this.detailsLoading,
    required this.detailsError,
    required this.busy,
    required this.onClose,
    required this.onNavigate,
    required this.isFavorite,
    required this.onFavorite,
    required this.onReview,
  });

  final PlaceSummary selectedPlace;
  final PlaceDetails? details;
  final bool detailsLoading;
  final String? detailsError;
  final bool busy;
  final VoidCallback onClose;
  final VoidCallback onNavigate;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return PlaceDetailsContent(
      selectedPlace: selectedPlace,
      details: details,
      detailsLoading: detailsLoading,
      detailsError: detailsError,
      routeBusy: busy,
      isFavorite: isFavorite,
      onClose: onClose,
      onNavigate: onNavigate,
      onFavorite: onFavorite,
      onReview: onReview,
    );
  }
}
