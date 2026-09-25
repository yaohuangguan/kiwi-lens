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
import 'data/place_details_repository.dart';
import 'data/route_repository.dart';
import 'domain/radar_geometry.dart';
import 'domain/map_layer_settings.dart';
import 'domain/route_option.dart';
import 'drive/device_heading.dart';
import 'drive/drive_engine.dart';
import 'widgets/map_symbols.dart';
import 'widgets/drive_hud.dart';
import 'widgets/explore_search.dart';
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
  static const _auckland = LatLng(latitude: -36.8485, longitude: 174.7633);

  final DriveEngine _driveEngine = DriveEngine();
  final AccountRepository _account = AccountRepository();
  final PlaceDetailsRepository _placeDetailsRepository =
      PlaceDetailsRepository();
  final RouteRepository _routeRepository = RouteRepository();
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
  bool _transitTripRunning = false;
  RouteOption? _activeTransitRoute;
  RouteOption? _activeNavigationRoute;
  final List<DestinationSuggestion> _routeStops = <DestinationSuggestion>[];

  PointOfInterest? _selectedPoi;
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
      if (_routePlan != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    }
  }

  Future<void> _restoreMapSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _useCarMarker = prefs.getBool('kiwi.map.car_marker') ?? false;
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
    if (profile == null) return _guestRecent;
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
      _selectedPoi = null;
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
      _driveEngine.setRoute(firstDrive);
      await _renderRoutePreview();
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not preview routes: $error');
      }
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
          useCarMarker: _useCarMarker,
          appLanguage: _appLanguage,
          voiceLanguage: _voiceLanguage,
          onVoiceChanged: _setVoiceEnabled,
          onLanesChanged: _setLanesEnabled,
          onCarMarkerChanged: (value) => unawaited(_setCarMarker(value)),
          onAppLanguageChanged: (value) => unawaited(_setAppLanguage(value)),
          onLanguageChanged: (value) => unawaited(_setVoiceLanguage(value)),
          onMapLayers: _showMapLayers,
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(PointOfInterest poi) async {
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
          points: route.points,
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
              points: segment,
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
    if (_account.profile != null) {
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
    _navigationSessionInitialized = true;
    await _driveEngine.start();
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
      _selectedPoi = null;
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
      final details = await _placeDetailsRepository.fetch(poi.placeID);
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
    setState(() {
      _selectedPoi = poi;
      _routePlan = null;
      _selectedRouteId = null;
      _message = null;
    });
    unawaited(_loadPlaceDetails(poi));
  }

  void _onSearchSelected(DestinationSuggestion suggestion) {
    _guestRecent.removeWhere((item) => item.label == suggestion.label);
    _guestRecent.insert(0, suggestion);
    if (_guestRecent.length > 12) _guestRecent.removeLast();
    if (_account.profile != null) {
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
    _onPoiClicked(
      PointOfInterest(
        placeID: '',
        name: suggestion.name ?? suggestion.label,
        latLng: suggestion.location,
      ),
    );
    final controller = _browseController;
    if (controller != null) {
      unawaited(
        controller.animateCamera(CameraUpdate.newLatLng(suggestion.location)),
      );
    }
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
      final options = MarkerOptions(
        position: location,
        icon: MapSymbols.car ?? ImageDescriptor.defaultImage,
        zIndex: 80,
        flat: true,
        rotation: _deviceHeading ?? _travelHeading ?? 0,
        anchor: const MarkerAnchor(u: 0.5, v: 0.5),
      );
      if (_carMarker == null) {
        _carMarker = (await controller.addMarkers([options])).first;
      } else {
        _carMarker = (await controller.updateMarkers([
          _carMarker!.copyWith(options: options),
        ])).first;
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
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('kiwi.map.car_marker', value);
    _queueMapRefresh();
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
        destination: destination,
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
              target: destination,
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
                  Navigator.of(sheetContext).pop();
                  _onSearchSelected(
                    DestinationSuggestion(
                      label: place['name']?.toString() ?? 'Saved place',
                      location: LatLng(
                        latitude: latitude.toDouble(),
                        longitude: longitude.toDouble(),
                      ),
                    ),
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
                        Navigator.of(sheetContext).pop();
                        _onSearchSelected(
                          DestinationSuggestion(
                            label: place['name']?.toString() ?? 'Saved route',
                            location: LatLng(
                              latitude: (place['latitude'] as num).toDouble(),
                              longitude: (place['longitude'] as num).toDouble(),
                            ),
                          ),
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

  void _showGoSearch() {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Start a trip',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            ExploreSearch(
              currentLocation: _gpsLocation,
              origin: _manualOrigin,
              recent: _recentDestinations,
              language: _appLanguage,
              onOriginSelected: (value) =>
                  setState(() => _manualOrigin = value),
              onSelected: (selection) {
                Navigator.of(sheetContext).pop();
                _onSearchSelected(selection);
                final poi = _selectedPoi;
                if (poi != null) unawaited(_loadRoutePreview(poi));
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              tileColor: const Color(0xFFF0F6E8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              leading: const Icon(Icons.directions_car_filled_rounded),
              title: const Text('Drive mode'),
              subtitle: const Text('Camera alerts without a destination'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _busy
                  ? null
                  : () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_startDriveMode());
                    },
            ),
          ],
        ),
      ),
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
              Icons.bookmark_rounded,
              _text('Saved', '收藏'),
              () => unawaited(_showSaved()),
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
            item(Icons.layers_rounded, _text('Layers', '图层'), _showMapLayers),
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
            points: activeRoute.points.sublist(start, end + 1),
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
            child: _driveEngine.active
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
                : GoogleMapsMapView(
                    key: const ValueKey('browse-map-view'),
                    onViewCreated: _onMapViewCreated,
                    mapId: _mapId.isEmpty ? null : _mapId,
                    onCameraMoveStarted: (_, isGesture) {
                      if (isGesture) _following = false;
                    },
                    onCameraMove: (position) => _lastBrowseCamera = position,
                    initialCameraPosition:
                        _lastBrowseCamera ??
                        CameraPosition(
                          target: _gpsLocation ?? _auckland,
                          zoom: 14,
                        ),
                    initialCompassEnabled: true,
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
          if (!_driveEngine.active && !_transitTripRunning)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 188,
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
              top: MediaQuery.paddingOf(context).top + 8,
              left: 16,
              right: 16,
              child: PointerInterceptor(
                child: ExploreSearch(
                  currentLocation: _gpsLocation,
                  origin: _manualOrigin,
                  recent: _recentDestinations,
                  language: _appLanguage,
                  onOriginSelected: (origin) {
                    setState(() => _manualOrigin = origin);
                    if (_selectedPoi != null) {
                      unawaited(_loadRoutePreview(_selectedPoi!));
                    }
                  },
                  onSelected: _onSearchSelected,
                ),
              ),
            ),
          if (_driveEngine.active &&
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
                    poi: _selectedPoi!,
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
    required this.poi,
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

  final PointOfInterest poi;
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
      poi: poi,
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
