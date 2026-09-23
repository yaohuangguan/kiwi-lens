import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'domain/coordinate_formatter.dart';
import 'domain/radar_geometry.dart';
import 'drive/device_heading.dart';
import 'drive/drive_engine.dart';
import 'widgets/drive_hud.dart';
import 'widgets/explore_search.dart';
import 'widgets/navigation_overlay.dart';

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
        final cameraTarget = _guidanceRunning && heading != null
            ? pointAtDistance(location, heading, 105)
            : location;
        await controller.moveCamera(CameraUpdate.newCameraPosition(
          CameraPosition(
            target: cameraTarget,
            bearing: heading ?? 0,
            tilt: _guidanceRunning ? 40 : 0,
            zoom: _guidanceRunning ? 17 : 16,
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

      final status = await GoogleMapsNavigator.setDestinations(
        Destinations(
          waypoints: <NavigationWaypoint>[
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
          routingOptions: RoutingOptions(
            travelMode: NavigationTravelMode.driving,
            alternateRoutesStrategy: NavigationAlternateRoutesStrategy.one,
          ),
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
        _selectedPoi = null;
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
      _message = null;
    });
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
    _navigationController = controller;
    _browseController = null;
    _radarPolygon = null;
    await controller.setNavigationHeaderEnabled(false);
    await controller.setNavigationFooterEnabled(false);
    await controller.setRecenterButtonEnabled(false);
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
                    initialMapColorScheme: MapColorScheme.followSystem,
                    onPoiClicked: _onPoiClicked,
                    onMapClicked: (_) {
                      if (_selectedPoi != null) {
                        setState(() => _selectedPoi = null);
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
          if (_selectedPoi != null && !_guidanceRunning)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: PointerInterceptor(
                  child: _PlaceCard(
                    poi: _selectedPoi!,
                    busy: _busy,
                    onClose: () => setState(() => _selectedPoi = null),
                    onNavigate: _navigateToSelectedPoi,
                  ),
                ),
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
