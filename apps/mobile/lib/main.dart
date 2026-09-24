import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/route_repository.dart';
import 'domain/coordinate_formatter.dart';
import 'domain/radar_geometry.dart';
import 'domain/route_option.dart';
import 'drive/device_heading.dart';
import 'drive/drive_engine.dart';
import 'widgets/drive_hud.dart';
import 'widgets/explore_search.dart';
import 'widgets/navigation_overlay.dart';
import 'widgets/route_preview_sheet.dart';

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
      home: const MapHomePage(),
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
  static const _auckland = LatLng(latitude: -36.8485, longitude: 174.7633);

  final DriveEngine _driveEngine = DriveEngine();
  final RouteRepository _routeRepository = RouteRepository();
  GoogleMapViewController? _browseController;
  GoogleNavigationViewController? _navigationController;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<double>? _headingSubscription;
  Timer? _mapRefreshTimer;
  LatLng? _gpsLocation;
  double? _gpsAccuracy;
  double? _deviceHeading;
  double? _travelHeading;
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
  final List<DestinationSuggestion> _routeStops = <DestinationSuggestion>[];

  PointOfInterest? _selectedPoi;
  bool _navigationSessionInitialized = false;
  bool _guidanceRunning = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startTracking());
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _headingSubscription?.cancel();
    _mapRefreshTimer?.cancel();
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
    if (_positionSubscription != null || !await _ensureLocationPermission()) return;
    _headingSubscription = DeviceHeading.readings.listen((heading) {
      _deviceHeading = heading;
      _queueMapRefresh();
    }, onError: (_) { /* iOS simulator and non-iOS use GPS course. */ });
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen(_onPosition, onError: (Object error) {
      if (mounted) setState(() => _message = 'Location unavailable: $error');
    });
    try {
      _onPosition(await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      ));
    } catch (_) { /* The location stream will retry. */ }
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    _gpsLocation = LatLng(latitude: position.latitude, longitude: position.longitude);
    _gpsAccuracy = position.accuracy.isFinite ? position.accuracy : null;
    if (position.speed >= 1.5 && position.heading.isFinite && position.heading >= 0) {
      _travelHeading = position.heading % 360;
    } else {
      _travelHeading = null;
    }
    setState(() {});
    _queueMapRefresh();
  }

  void _queueMapRefresh() {
    _mapRefreshTimer?.cancel();
    _mapRefreshTimer = Timer(const Duration(milliseconds: 180), () => unawaited(_refreshMap()));
  }

  Future<void> _refreshMap() async {
    if (_mapRefreshing) { _refreshAgain = true; return; }
    final controller = _guidanceRunning ? _navigationController : _browseController;
    final location = _gpsLocation;
    final heading = _deviceHeading ?? _travelHeading;
    if (controller == null || location == null) return;
    _mapRefreshing = true;
    try {
      if (heading != null) {
        final options = PolygonOptions(
          points: radarSector(location, heading),
          fillColor: const Color(0x33AAF05F),
          strokeColor: const Color(0x9986CB48),
          strokeWidth: 1.5,
          geodesic: true,
          zIndex: 5,
        );
        if (_radarPolygon == null) {
          final polygon = (await controller.addPolygons([options])).first;
          if (controller == (_guidanceRunning ? _navigationController : _browseController)) {
            _radarPolygon = polygon;
          }
        } else {
          final polygon = (await controller.updatePolygons([
            _radarPolygon!.copyWith(options: options),
          ])).first;
          if (controller == (_guidanceRunning ? _navigationController : _browseController)) {
            _radarPolygon = polygon;
          }
        }
      } else if (_radarPolygon != null) {
        await controller.removePolygons([_radarPolygon!]);
        _radarPolygon = null;
      }
      if (_following) {
        final turnDistance = _driveEngine.navInfo?.distanceToCurrentStepMeters?.toDouble();
        final nearJunction = _guidanceRunning && turnDistance != null && turnDistance < 140;
        final veryNearJunction = _guidanceRunning && turnDistance != null && turnDistance < 45;
        final lookAhead = veryNearJunction ? 38.0 : nearJunction ? 65.0 : 105.0;
        final cameraTarget = _guidanceRunning && heading != null
            ? pointAtDistance(location, heading, lookAhead)
            : location;
        await controller.moveCamera(CameraUpdate.newCameraPosition(
          CameraPosition(
            target: cameraTarget,
            bearing: heading ?? 0,
            tilt: veryNearJunction ? 55 : nearJunction ? 50 : _guidanceRunning ? 42 : 0,
            zoom: veryNearJunction ? 19.2 : nearJunction ? 18.4 : _guidanceRunning ? 17.2 : 16,
          ),
        ));
      }
    } catch (_) { /* View may have been replaced during a mode change. */ }
    finally {
      _mapRefreshing = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        _queueMapRefresh();
      }
    }
  }

  void _recenter() {
    _following = true;
    _queueMapRefresh();
  }

  void _showRouteOverview() {
    _following = false;
    final controller = _navigationController;
    if (controller != null) unawaited(controller.showRouteOverview());
  }

  Future<void> _clearRoutePreview() async {
    final controller = _browseController;
    if (controller != null) {
      try { await controller.clearPolylines(); } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _routePlan = null;
      _selectedRouteId = null;
      _selectedMode = KiwiTravelMode.drive;
      _routePreviewLoading = false;
      _selectedPoi = null;
      _routeStops.clear();
    });
  }

  Future<void> _loadRoutePreview(PointOfInterest poi) async {
    final origin = _gpsLocation;
    if (origin == null) {
      setState(() => _message = 'Waiting for GPS before calculating routes.');
      return;
    }
    setState(() {
      _routePreviewLoading = true;
      _routePlan = null;
      _selectedMode = KiwiTravelMode.drive;
      _selectedRouteId = null;
      _message = null;
    });
    try {
      final plan = await _routeRepository.fetch(
        origin: origin,
        destination: poi.latLng,
        stops: _routeStops.map((stop) => stop.location).toList(growable: false),
      );
      final firstDrive = plan.forMode(KiwiTravelMode.drive).firstOrNull;
      if (!mounted) return;
      setState(() {
        _routePlan = plan;
        _selectedRouteId = firstDrive?.id;
      });
      await _renderRoutePreview();
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not preview routes: $error');
    } finally {
      if (mounted) setState(() => _routePreviewLoading = false);
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
      options.add(PolylineOptions(
        points: route.points,
        strokeColor: active ? const Color(0xFF3036D9) : const Color(0xFF8A94A0),
        strokeWidth: active ? 8 : 5,
        zIndex: active ? 20 : 10,
        clickable: false,
      ));
    }
    if (options.isNotEmpty) await controller.addPolylines(options);
    if (selected != null && selected.points.length >= 2) {
      final bounds = LatLngBounds.createBoundsFromPoints(selected.points);
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
    unawaited(_renderRoutePreview());
  }

  void _selectRoute(RouteOption route) {
    setState(() => _selectedRouteId = route.id);
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
      'durationSeconds': selected.durationSeconds,
      'distanceMeters': selected.distanceMeters,
      'stops': _routeStops.map((stop) => {
        'label': stop.label,
        'latitude': stop.location.latitude,
        'longitude': stop.location.longitude,
      }).toList(),
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Route saved on this device')),
      );
    }
  }

  void _toggleVoice() {
    setState(() => _voiceEnabled = !_voiceEnabled);
    _driveEngine.voiceEnabled = _voiceEnabled;
    unawaited(GoogleMapsNavigator.setAudioGuidance(
      NavigationAudioGuidanceSettings(
        guidanceType: _voiceEnabled
            ? NavigationAudioGuidanceType.alertsAndGuidance
            : NavigationAudioGuidanceType.silent,
        isBluetoothAudioEnabled: true,
        isVibrationEnabled: true,
      ),
    ));
  }

  Future<bool> _ensureNavigationSession() async {
    if (_navigationSessionInitialized) {
      if (!_driveEngine.active) await _driveEngine.start();
      return true;
    }
    if (!await _ensureLocationPermission()) return false;

    if (!await GoogleMapsNavigator.areTermsAccepted()) {
      final accepted = await GoogleMapsNavigator.showTermsAndConditionsDialog(
        'Kiwi Lens Navigation',
        'Kiwi Lens',
      );
      if (!accepted) return false;
    }

    await GoogleMapsNavigator.initializeNavigationSession(
      taskRemovedBehavior: TaskRemovedBehavior.continueService,
    );
    await GoogleMapsNavigator.setAudioGuidance(
      NavigationAudioGuidanceSettings(
        guidanceType: NavigationAudioGuidanceType.alertsAndGuidance,
        isBluetoothAudioEnabled: true,
        isVibrationEnabled: true,
      ),
    );
    _navigationSessionInitialized = true;
    await _driveEngine.start();
    return true;
  }

  Future<void> _navigateToSelectedPoi() async {
    final poi = _selectedPoi;
    if (poi == null || _busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      if (!await _ensureNavigationSession()) return;

      final selectedRoute = _selectedRoute;
      final routeToken = selectedRoute?.routeToken;
      final status = await GoogleMapsNavigator.setDestinations(
        Destinations(
          waypoints: <NavigationWaypoint>[
            for (final stop in _routeStops)
              NavigationWaypoint.withLatLngTarget(
                title: stop.label,
                target: stop.location,
              ),
            if (poi.placeID.isNotEmpty)
              NavigationWaypoint.withPlaceID(title: poi.name, placeID: poi.placeID)
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
          routeTokenOptions: routeToken != null && routeToken.isNotEmpty
              ? RouteTokenOptions(
                  routeToken: routeToken,
                  travelMode: NavigationTravelMode.driving,
                )
              : null,
          routingOptions: routeToken == null || routeToken.isEmpty
              ? RoutingOptions(
                  travelMode: NavigationTravelMode.driving,
                  alternateRoutesStrategy: NavigationAlternateRoutesStrategy.one,
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

      await GoogleMapsNavigator.startGuidance();
      if (!mounted) return;
      setState(() {
        _guidanceRunning = true;
        _destinationTitle = poi.name;
        _routePlan = null;
        _selectedRouteId = null;
        _selectedPoi = null;
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
    await GoogleMapsNavigator.stopGuidance();
    await GoogleMapsNavigator.clearDestinations();
    if (!mounted) return;
    setState(() {
      _guidanceRunning = false;
      _destinationTitle = 'Destination';
    });
  }

  Future<void> _startDriveMode() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await _ensureNavigationSession()) return;
      if (mounted) {
        setState(() {});
      }
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

  void _onPoiClicked(PointOfInterest poi) {
    setState(() {
      _selectedPoi = poi;
      _routePlan = null;
      _selectedRouteId = null;
      _message = null;
    });
    unawaited(_loadRoutePreview(poi));
  }

  void _onSearchSelected(DestinationSuggestion suggestion) {
    _onPoiClicked(PointOfInterest(
      placeID: '',
      name: suggestion.label,
      latLng: suggestion.location,
    ));
    final controller = _browseController;
    if (controller != null) {
      unawaited(controller.animateCamera(CameraUpdate.newLatLng(suggestion.location)));
    }
  }

  Future<void> _onMapViewCreated(GoogleMapViewController controller) async {
    _browseController = controller;
    _navigationController = null;
    _radarPolygon = null;
    await controller.settings.setTrafficEnabled(true);
    await controller.settings.setRotateGesturesEnabled(true);
    await controller.settings.setTiltGesturesEnabled(true);
    await controller.settings.setScrollGesturesDuringRotateOrZoomEnabled(true);
    if (await Permission.locationWhenInUse.isGranted) {
      await controller.setMyLocationEnabled(true);
    }
    await controller.setRecenterButtonEnabled(false);
    _queueMapRefresh();
  }

  Future<void> _onNavigationViewCreated(
    GoogleNavigationViewController controller,
  ) async {
    await controller.setMyLocationEnabled(true);
    await controller.settings.setTrafficEnabled(true);
    await controller.settings.setRotateGesturesEnabled(true);
    await controller.settings.setTiltGesturesEnabled(true);
    await controller.settings.setScrollGesturesDuringRotateOrZoomEnabled(true);
    _navigationController = controller;
    _browseController = null;
    _radarPolygon = null;
    await controller.setNavigationHeaderEnabled(false);
    await controller.setNavigationFooterEnabled(false);
    await controller.setRecenterButtonEnabled(false);
    await controller.setTrafficIncidentCardsEnabled(true);
    await controller.setTrafficPromptsEnabled(true);
    await controller.setPadding(const EdgeInsets.fromLTRB(16, 125, 16, 215));
    _queueMapRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _guidanceRunning
                ? GoogleMapsNavigationView(
                    key: const ValueKey('navigation-view'),
                    onViewCreated: _onNavigationViewCreated,
                    mapId: _mapId.isEmpty ? null : _mapId,
                    onCameraMoveStarted: (_, isGesture) { if (isGesture) _following = false; },
                    initialNavigationUIEnabledPreference:
                        NavigationUIEnabledPreference.automatic,
                    initialRotateGesturesEnabled: true,
                    initialTiltGesturesEnabled: true,
                    initialScrollGesturesEnabledDuringRotateOrZoom: true,
                    initialForceNightMode: NavigationForceNightMode.auto,
                    onPoiClicked: _onPoiClicked,
                  )
                : GoogleMapsMapView(
                    key: const ValueKey('browse-map-view'),
                    onViewCreated: _onMapViewCreated,
                    mapId: _mapId.isEmpty ? null : _mapId,
                    onCameraMoveStarted: (_, isGesture) { if (isGesture) _following = false; },
                    initialCameraPosition: const CameraPosition(
                      target: _auckland,
                      zoom: 14,
                    ),
                    initialRotateGesturesEnabled: true,
                    initialTiltGesturesEnabled: true,
                    initialScrollGesturesEnabledDuringRotateOrZoom: true,
                    initialMapColorScheme: MapColorScheme.followSystem,
                    onPoiClicked: _onPoiClicked,
                    onMapClicked: (_) {
                      if (_selectedPoi != null || _routePlan != null) {
                        unawaited(_clearRoutePreview());
                      }
                    },
                  ),
          ),
          if (!_guidanceRunning)
            SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: PointerInterceptor(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xEE0B1717),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 20,
                            color: Color(0x26000000),
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BrandMark(),
                          SizedBox(width: 9),
                          Text(
                            'KIWI',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Text(
                            'LENS',
                            style: TextStyle(
                              color: Color(0xFFC8F169),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (_guidanceRunning)
                      FilledButton.icon(
                        onPressed: _stopNavigation,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xEE0B1717),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('End'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (!_guidanceRunning)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 75,
              left: 16,
              right: 16,
              child: PointerInterceptor(
                child: ExploreSearch(
                  currentLocation: _gpsLocation,
                  onSelected: _onSearchSelected,
                ),
              ),
            ),
          if (_driveEngine.active && _selectedPoi == null)
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
                        onVoiceToggle: _toggleVoice,
                        onLanesToggle: () => setState(() => _lanesEnabled = !_lanesEnabled),
                      )
                    : DriveHud(
                        engine: _driveEngine,
                        onStop: () => unawaited(_stopDriveMode()),
                      ),
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
          if (!_driveEngine.active && _selectedPoi == null && !_guidanceRunning)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 16, 16, 22),
                child: PointerInterceptor(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _startDriveMode,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0B1717),
                      foregroundColor: const Color(0xFFC8F169),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                    ),
                    icon: const Icon(Icons.directions_car_filled_rounded),
                    label: Text(_busy ? 'Starting…' : 'Drive'),
                  ),
                ),
              ),
            ),
          if (_selectedPoi != null && !_guidanceRunning && _routePlan == null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: PointerInterceptor(
                  child: _PlaceCard(
                    poi: _selectedPoi!,
                    busy: _routePreviewLoading,
                    onClose: () => unawaited(_clearRoutePreview()),
                    onNavigate: () => unawaited(_loadRoutePreview(_selectedPoi!)),
                  ),
                ),
              ),
            ),
          if (_selectedPoi != null && _routePlan != null && !_guidanceRunning)
            Align(
              alignment: Alignment.bottomCenter,
              child: RoutePreviewSheet(
                destinationTitle: _selectedPoi!.name,
                plan: _routePlan!,
                selectedMode: _selectedMode,
                selectedRouteId: _selectedRouteId,
                busy: _busy,
                stopCount: _routeStops.length,
                onModeChanged: _selectMode,
                onRouteSelected: _selectRoute,
                onStart: () => unawaited(_navigateToSelectedPoi()),
                onAddStop: () => unawaited(_addStop()),
                onSave: () => unawaited(_saveCurrentRoute()),
                onClose: () => unawaited(_clearRoutePreview()),
              ),
            ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFC8F169), width: 2),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(
        Icons.navigation_rounded,
        color: Color(0xFFC8F169),
        size: 18,
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.poi,
    required this.busy,
    required this.onClose,
    required this.onNavigate,
  });

  final PointOfInterest poi;
  final bool busy;
  final VoidCallback onClose;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 18,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5E8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.place_rounded, color: Color(0xFF3D6C55)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    poi.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatCoordinate(poi.latLng.latitude, poi.latLng.longitude),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: busy ? null : onNavigate,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF18372D),
                foregroundColor: const Color(0xFFC8F169),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.navigation_rounded, size: 19),
              label: Text(busy ? 'Routing' : 'Navigate'),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close',
            ),
          ],
        ),
      ),
    );
  }
}
