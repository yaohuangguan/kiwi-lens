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
import 'data/parking_repository.dart';
import 'data/route_repository.dart';
import 'domain/radar_geometry.dart';
import 'domain/map_layer_settings.dart';
import 'domain/map_provider.dart';
import 'domain/geo_math.dart';
import 'domain/route_option.dart';
import 'domain/road_event.dart';
import 'drive/device_heading.dart';
import 'drive/drive_engine.dart';
import 'providers/google_map_renderer.dart';
import 'providers/mapbox_map_renderer.dart';
import 'providers/mapbox_navigation_engine.dart';
import 'providers/mapbox_routing_provider.dart';
import 'providers/place_search_providers.dart';
import 'providers/provider_contracts.dart';
import 'services/notification_service.dart';
import 'theme/tasman_theme.dart';
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

class KiwiLensApp extends StatefulWidget {
  const KiwiLensApp({super.key});

  @override
  State<KiwiLensApp> createState() => _KiwiLensAppState();
}

class _KiwiLensAppState extends State<KiwiLensApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreAppearance());
  }

  Future<void> _restoreAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('tasman.appearance') ?? 'system';
    final mode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    if (mounted) setState(() => _themeMode = mode);
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tasman.appearance', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tasman',
      debugShowCheckedModeBanner: false,
      theme: TasmanTheme.light,
      darkTheme: TasmanTheme.dark,
      themeMode: _themeMode,
      home: SplashGate(
        child: MapHomePage(
          themeMode: _themeMode,
          onThemeModeChanged: (mode) => unawaited(_setThemeMode(mode)),
        ),
      ),
    );
  }
}

class _OnboardingFeature extends StatelessWidget {
  const _OnboardingFeature({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: TasmanColors.ice,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: TasmanColors.ocean, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: TasmanColors.deepOcean,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: TasmanColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TransientTasmanBanner extends StatefulWidget {
  const _TransientTasmanBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  State<_TransientTasmanBanner> createState() => _TransientTasmanBannerState();
}

class _TransientTasmanBannerState extends State<_TransientTasmanBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 76, 20, 0),
        child: PointerInterceptor(
          child: Material(
            color: TasmanColors.darkOcean.withValues(alpha: .96),
            elevation: 8,
            borderRadius: BorderRadius.circular(15),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 5, 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: TasmanColors.sky,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Dismiss',
                    onPressed: widget.onDismiss,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class MapHomePage extends StatefulWidget {
  const MapHomePage({
    super.key,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

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
  final ParkingRepository _parkingRepository = ParkingRepository();
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
  List<Marker> _roadEventMarkers = [];
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
  bool _notifySafetyCameras = false;
  bool _notifyRoadIncidents = false;
  bool _notifyCommunityReports = false;
  bool _notifySavedRouteDisruptions = false;
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
  List<ParkingPlace> _parkingPlaces = const [];
  ParkingPlace? _selectedParking;
  PlaceSummary? _parkingOriginalPlace;
  bool _parkingLoading = false;
  bool _parkingLegFinished = false;
  int _parkingRequest = 0;

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
  String? _lastNotifiedCameraId;
  final Set<String> _notifiedRoadEventIds = <String>{};

  @override
  void initState() {
    super.initState();
    _mapboxNavigation = MapboxNavigationEngine(_driveEngine);
    unawaited(TasmanNotificationService.instance.initialize());
    initializeMapboxMaps(_mapboxToken);
    _account.addListener(_onAccountChanged);
    _driveEngine.addListener(_onEngineChanged);
    unawaited(_account.restore());
    unawaited(_driveEngine.loadCameras());
    unawaited(_restoreMapSettings().then((_) => _maybeShowCoreOnboarding()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startTracking());
    });
  }

  Future<void> _maybeShowCoreOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('tasman.onboarding.core.v1') == true) return;
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 6),
        contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [TasmanColors.ocean, TasmanColors.teal],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.navigation_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _text('Welcome to Tasman', '欢迎使用 Tasman'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OnboardingFeature(
              icon: Icons.route_rounded,
              title: _text('Navigation first', '专注导航'),
              body: _text(
                'Clear route guidance, traffic-aware routing and a focused Drive Mode.',
                '清晰路线指引、实时交通路线，以及专注驾驶的 Drive Mode。',
              ),
            ),
            _OnboardingFeature(
              icon: Icons.shield_outlined,
              title: _text('Road Intelligence', '道路情报'),
              body: _text(
                'NZTA roadworks, closures, incidents and safety cameras appear when relevant.',
                '根据路线显示 NZTA 道路施工、封路、事故与安全摄像头。',
              ),
            ),
            _OnboardingFeature(
              icon: Icons.add_alert_rounded,
              title: _text('Report the road', '上报道路情况'),
              body: _text(
                'Share crashes, hazards, roadworks, flooding and congestion with other Tasman drivers.',
                '向其他 Tasman 用户分享事故、危险、施工、积水与拥堵。',
              ),
            ),
            _OnboardingFeature(
              icon: Icons.explore_rounded,
              title: _text('Made for New Zealand', '为新西兰道路设计'),
              body: _text(
                'Kiwi location marker, NZ road data and a calm ocean-blue driving interface.',
                'Kiwi 定位标记、新西兰道路数据，以及 Tasman 海洋蓝驾驶界面。',
              ),
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            onPressed: () async {
              await prefs.setBool('tasman.onboarding.core.v1', true);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(_text('Start exploring', '开始探索')),
          ),
        ],
      ),
    );
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
    unawaited(_notifyRoadIntelligence());
    final reportIds = _communityRoadEvents.map((event) => event.id).join(',');
    final signature =
        '${_driveEngine.cameras.length}:${_driveEngine.routeCameras.map((match) => match.camera.id).join(',')}:$reportIds:${_layers.markerSignature}';
    if (signature != _markerSignature) {
      unawaited(_syncCameraMarkers());
      if (_routePlan != null || _mapProvider == MapProvider.mapbox) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    }
  }

  List<RoadEvent> get _communityRoadEvents => _driveEngine.roadEvents
      .where((event) => event.metadata['userReported'] == true)
      .toList(growable: false);

  String _roadEventLabel(RoadEventType type) => switch (type) {
    RoadEventType.incident => _text('Crash / hazard', '事故 / 危险'),
    RoadEventType.roadworks => _text('Roadworks', '道路施工'),
    RoadEventType.roadClosure => _text('Road closed', '道路封闭'),
    RoadEventType.congestion => _text('Heavy traffic', '严重拥堵'),
    RoadEventType.flooding => _text('Flooding', '积水 / 洪水'),
    RoadEventType.slip => _text('Slip / debris', '滑坡 / 道路杂物'),
    _ => _text('Road report', '道路报告'),
  };

  String _relativeTime(DateTime? date) {
    if (date == null) return _text('recently', '刚刚');
    final delta = DateTime.now().difference(date);
    if (delta.inMinutes < 1) return _text('just now', '刚刚');
    if (delta.inMinutes < 60) {
      return _text('${delta.inMinutes} min ago', '${delta.inMinutes} 分钟前');
    }
    if (delta.inHours < 24) {
      return _text('${delta.inHours} hr ago', '${delta.inHours} 小时前');
    }
    return _text('${delta.inDays} d ago', '${delta.inDays} 天前');
  }

  String _remainingTime(DateTime? date) {
    if (date == null) return '';
    final delta = date.difference(DateTime.now());
    if (delta.isNegative) return _text('expired', '已过期');
    if (delta.inMinutes < 60) {
      return _text('${delta.inMinutes} min left', '剩余 ${delta.inMinutes} 分钟');
    }
    return _text('${delta.inHours} hr left', '剩余 ${delta.inHours} 小时');
  }

  Future<void> _notifyRoadIntelligence() async {
    if (!_driveEngine.active) return;
    final camera = _driveEngine.upcomingCamera;
    final cameraDistance = _driveEngine.upcomingCameraDistanceMeters;
    if (_notifySafetyCameras &&
        camera != null &&
        cameraDistance != null &&
        cameraDistance <= 600 &&
        _lastNotifiedCameraId != camera.id) {
      _lastNotifiedCameraId = camera.id;
      await TasmanNotificationService.instance.showRoadAlert(
        id: 'camera:${camera.id}',
        title: _text('Safety camera ahead', '前方安全摄像头'),
        body: _text(
          '${camera.type} · ${cameraDistance.round()} m',
          '${camera.type} · ${cameraDistance.round()} 米',
        ),
      );
    }
    if (camera == null) _lastNotifiedCameraId = null;

    for (final event in _driveEngine.upcomingRoadEvents) {
      final distance = event.distanceAlongRoute ?? event.distanceFromDriver;
      if (distance == null || distance > 1500) continue;
      final community = event.metadata['userReported'] == true;
      final importantOfficial =
          event.severity == RoadEventSeverity.warning ||
          event.severity == RoadEventSeverity.critical;
      final enabled = community
          ? _notifyCommunityReports
          : _notifyRoadIncidents && importantOfficial;
      if (!enabled || !_notifiedRoadEventIds.add(event.id)) continue;
      final reporter = event.metadata['reporterName']?.toString();
      await TasmanNotificationService.instance.showRoadAlert(
        id: event.id,
        title: _roadEventLabel(event.type),
        body: reporter == null
            ? _text('${distance.round()} m ahead', '前方 ${distance.round()} 米')
            : _text(
                '${distance.round()} m ahead · reported by $reporter',
                '前方 ${distance.round()} 米 · $reporter 报告',
              ),
      );
    }
  }

  Future<void> _showRoadEventDetails(RoadEvent event) async {
    final reporter =
        event.metadata['reporterName']?.toString() ??
        _text('Tasman driver', 'Tasman 用户');
    final description = event.metadata['description']?.toString();
    final reportedAt =
        DateTime.tryParse(event.metadata['reportedAt']?.toString() ?? '') ??
        event.source.updatedAt;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: TasmanColors.ice,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.add_alert_rounded,
                    color: TasmanColors.ocean,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _roadEventLabel(event.type),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: TasmanColors.deepOcean,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _text(
                '$reporter reported this ${_relativeTime(reportedAt)}',
                '$reporter · ${_relativeTime(reportedAt)}报告',
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: TasmanColors.deepOcean,
              ),
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(description),
            ],
            const SizedBox(height: 8),
            Text(
              _remainingTime(event.validUntil),
              style: const TextStyle(
                color: TasmanColors.lightTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
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
    _notifySafetyCameras =
        prefs.getBool('tasman.notifications.safety_cameras') ?? false;
    _notifyRoadIncidents =
        prefs.getBool('tasman.notifications.road_incidents') ?? false;
    _notifyCommunityReports =
        prefs.getBool('tasman.notifications.community_reports') ?? false;
    _notifySavedRouteDisruptions =
        prefs.getBool('tasman.notifications.saved_route_disruptions') ?? false;
    _driveEngine.voiceEnabled = _voiceEnabled;
    _layers = MapLayerSettings(
      cameras: prefs.getBool('kiwi.layers.cameras') ?? true,
      spotSpeed:
          prefs.getBool('tasman.layers.spot_speed') ??
          prefs.getBool('kiwi.layers.speed') ??
          true,
      averageSpeed: prefs.getBool('tasman.layers.average_speed') ?? true,
      redLight: prefs.getBool('kiwi.layers.red_light') ?? true,
      dualRedLightSpeed: prefs.getBool('tasman.layers.dual_red_speed') ?? true,
      busLane: prefs.getBool('tasman.layers.bus_lane') ?? true,
      other: prefs.getBool('kiwi.layers.other') ?? true,
      alertSpotSpeed: prefs.getBool('tasman.alerts.spot_speed') ?? true,
      alertAverageSpeed: prefs.getBool('tasman.alerts.average_speed') ?? true,
      alertRedLight: prefs.getBool('tasman.alerts.red_light') ?? true,
      alertDualRedLightSpeed:
          prefs.getBool('tasman.alerts.dual_red_speed') ?? true,
      alertBusLane: prefs.getBool('tasman.alerts.bus_lane') ?? true,
      alertOther: prefs.getBool('tasman.alerts.other_camera') ?? false,
      traffic: prefs.getBool('kiwi.layers.traffic') ?? true,
      style: BaseMapStyle.values.firstWhere(
        (value) => value.name == prefs.getString('kiwi.layers.style'),
        orElse: () => BaseMapStyle.standard,
      ),
    );
    _driveEngine.setCameraAlertFilter(_layers.alerts);
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
    _parkingRepository.dispose();
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
          ? 'Location is disabled for Tasman. Enable it in system settings.'
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
            zoom: _mapboxNavigation.active ? 16 : (_northUp ? 16 : 17),
            bearing: _northUp ? 0 : (_travelHeading ?? _deviceHeading ?? 0),
            pitch: _northUp ? 0 : 45,
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
            CameraPosition(
              target: location,
              bearing: _northUp ? 0 : (_travelHeading ?? _deviceHeading ?? 0),
              tilt: _northUp ? 0 : 45,
              zoom: _northUp ? 16 : 17,
            ),
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

  IconData get _locationControlIcon {
    if (!_following) return Icons.my_location_outlined;
    return _northUp ? Icons.north_rounded : Icons.navigation_rounded;
  }

  String get _locationControlTooltip {
    if (!_following) return _text('Return to my location', '回到我的位置');
    return _northUp
        ? _text('Switch to heading-up', '切换到车头朝向')
        : _text('Switch to north-up', '切换到指北');
  }

  void _cycleLocationCamera() {
    if (!_following) {
      setState(() {
        _following = true;
        _northUp = true;
      });
    } else {
      setState(() => _northUp = !_northUp);
    }
    _recenter();
  }

  Future<void> _showRoadReport() async {
    final location = _gpsLocation;
    if (location == null) {
      setState(
        () => _message = _text(
          'Current location is required to report a road issue.',
          '需要获取当前位置才能上报道路情况。',
        ),
      );
      return;
    }
    final choices = <(String, String, String, IconData)>[
      ('incident', 'Crash / hazard', '事故 / 危险', Icons.car_crash_rounded),
      ('roadworks', 'Roadworks', '道路施工', Icons.construction_rounded),
      ('roadClosure', 'Road closed', '道路封闭', Icons.block_rounded),
      ('congestion', 'Heavy traffic', '严重拥堵', Icons.traffic_rounded),
      ('flooding', 'Flooding', '积水 / 洪水', Icons.water_rounded),
      ('slip', 'Slip / debris', '滑坡 / 道路杂物', Icons.landslide_rounded),
    ];
    final selected = await showModalBottomSheet<(String, String)>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _text('Report road issue', '上报道路情况'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(
                _text(
                  'Reports are shared with Tasman drivers for about 2 hours.',
                  '上报内容将在约 2 小时内共享给 Tasman 驾驶用户。',
                ),
              ),
            ),
            for (final choice in choices)
              ListTile(
                leading: Icon(choice.$4, color: TasmanColors.ocean),
                title: Text(_text(choice.$2, choice.$3)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    Navigator.pop(sheetContext, (choice.$1, choice.$2)),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    try {
      await _account.submitRoadReport(
        type: selected.$1,
        latitude: location.latitude,
        longitude: location.longitude,
        headingDegrees: _travelHeading ?? _deviceHeading,
        description: selected.$2,
      );
      await _driveEngine.loadCameras(force: true);
      _markerSignature = '';
      unawaited(_syncCameraMarkers());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Road report submitted', '道路情况已上报'))),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = _text(
            'Could not submit road report: $error',
            '道路上报失败：$error',
          ),
        );
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
    ++_parkingRequest;
    _driveEngine.setRoute(null);
    final controller = _browseController;
    if (controller != null) {
      try {
        await controller.clearPolylines();
        await controller.setPadding(EdgeInsets.zero);
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
      _parkingPlaces = const [];
      _parkingOriginalPlace = null;
      _selectedParking = null;
      _parkingLoading = false;
      _parkingLegFinished = false;
    });
  }

  Future<void> _loadParking(PlaceSummary destination) async {
    final request = ++_parkingRequest;
    setState(() {
      _parkingPlaces = const [];
      _parkingLoading = true;
    });
    try {
      final places = await _parkingRepository.nearby(
        destination: destination.location,
        allowGoogleFallback: _mapProvider == MapProvider.google,
        language: _appLanguage,
      );
      if (!mounted || request != _parkingRequest) return;
      setState(() => _parkingPlaces = places);
    } catch (_) {
      if (mounted && request == _parkingRequest) {
        setState(() => _parkingPlaces = const []);
      }
    } finally {
      if (mounted && request == _parkingRequest) {
        setState(() => _parkingLoading = false);
      }
    }
  }

  Future<void> _selectParking(ParkingPlace parking) async {
    final original = _parkingOriginalPlace ?? _selectedPlace?.place;
    if (original == null) return;
    ++_parkingRequest;
    setState(() {
      _parkingOriginalPlace = original;
      _selectedParking = parking;
      _parkingLegFinished = false;
      _parkingLoading = false;
      _selectedPlace = SelectedPlace(
        parking.toPlaceSummary(),
        SelectionSource.map,
        originMap: _mapProvider,
      );
      _routeStops.clear();
    });
    final poi = _selectedPoi;
    if (poi != null) await _loadRoutePreview(poi);
  }

  Future<void> _restoreDirectDestination() async {
    final original = _parkingOriginalPlace;
    if (original == null) return;
    setState(() {
      _parkingOriginalPlace = null;
      _selectedParking = null;
      _parkingLegFinished = false;
      _selectedPlace = SelectedPlace(
        original,
        SelectionSource.map,
        originMap: _mapProvider,
      );
    });
    final poi = _selectedPoi;
    if (poi != null) await _loadRoutePreview(poi);
  }

  Future<void> _continueOnFoot() async {
    final original = _parkingOriginalPlace;
    if (original == null) return;
    setState(() {
      _parkingOriginalPlace = null;
      _selectedParking = null;
      _parkingLegFinished = false;
      _parkingPlaces = const [];
      _manualOrigin = null;
      _routeStops.clear();
      _selectedPlace = SelectedPlace(
        original,
        SelectionSource.map,
        originMap: _mapProvider,
      );
    });
    final poi = _selectedPoi;
    if (poi != null) {
      await _loadRoutePreview(poi, preferredMode: KiwiTravelMode.walk);
    }
  }

  Future<void> _loadRoutePreview(
    PointOfInterest poi, {
    KiwiTravelMode preferredMode = KiwiTravelMode.drive,
  }) async {
    final origin = _manualOrigin?.location ?? _gpsLocation;
    if (origin == null) {
      setState(() => _message = 'Waiting for GPS before calculating routes.');
      return;
    }
    final request = ++_routeRequest;
    setState(() {
      _routePreviewLoading = true;
      _routePlan = null;
      _selectedMode = preferredMode;
      _selectedRouteId = null;
      _message = null;
    });
    if (preferredMode == KiwiTravelMode.drive &&
        _selectedParking == null &&
        _selectedPlace != null) {
      unawaited(_loadParking(_selectedPlace!.place));
    }
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
      final firstRoute = plan.forMode(preferredMode).firstOrNull;
      if (!mounted || request != _routeRequest) return;
      setState(() {
        _routePlan = plan;
        _selectedRouteId = firstRoute?.id;
        _journeyPhase = JourneyPhase.routePreview;
      });
      _driveEngine.setRoute(
        preferredMode == KiwiTravelMode.drive ? firstRoute : null,
      );
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
        ? 0xE5484D
        : speed == 'slow'
        ? 0xF59E0B
        : 0x0284C7;
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
          themeMode: widget.themeMode,
          onThemeModeChanged: (mode) => widget.onThemeModeChanged?.call(mode),
          onVoiceChanged: _setVoiceEnabled,
          onLanesChanged: _setLanesEnabled,
          onAppLanguageChanged: (value) => unawaited(_setAppLanguage(value)),
          onLanguageChanged: (value) => unawaited(_setVoiceLanguage(value)),
          onMapLayers: _showMapLayers,
          mapProvider: _mapProvider,
          locationMarker: _locationMarker,
          mapboxAvailable: _mapboxToken.isNotEmpty,
          notifySafetyCameras: _notifySafetyCameras,
          notifyRoadIncidents: _notifyRoadIncidents,
          notifyCommunityReports: _notifyCommunityReports,
          notifySavedRouteDisruptions: _notifySavedRouteDisruptions,
          onNotifySafetyCamerasChanged: (value) => unawaited(
            _setNotificationPreference(
              'tasman.notifications.safety_cameras',
              value,
            ),
          ),
          onNotifyRoadIncidentsChanged: (value) => unawaited(
            _setNotificationPreference(
              'tasman.notifications.road_incidents',
              value,
            ),
          ),
          onNotifyCommunityReportsChanged: (value) => unawaited(
            _setNotificationPreference(
              'tasman.notifications.community_reports',
              value,
            ),
          ),
          onNotifySavedRouteDisruptionsChanged: (value) => unawaited(
            _setNotificationPreference(
              'tasman.notifications.saved_route_disruptions',
              value,
            ),
          ),
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
                'Saved to Tasman only; not published to Google.',
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
    final sheetInset = (MediaQuery.sizeOf(context).height * .44).clamp(
      330.0,
      420.0,
    );
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
          strokeColor: active
              ? TasmanColors.ocean.withValues(alpha: .92)
              : TasmanColors.sky.withValues(alpha: .38),
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
      await controller.setPadding(EdgeInsets.fromLTRB(24, 76, 24, sheetInset));
      final bounds = LatLngBounds.createBoundsFromPoints(
        selected.points
            .map(
              (point) =>
                  LatLng(latitude: point.latitude, longitude: point.longitude),
            )
            .toList(growable: false),
      );
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding: 36),
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
    _driveEngine.setRoute(mode == KiwiTravelMode.drive ? _selectedRoute : null);
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
        'Tasman Navigation',
        'Tasman',
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
    for (var attempt = 0; attempt < 10; attempt++) {
      _navigationSessionInitialized = await GoogleMapsNavigator.isInitialized();
      if (_navigationSessionInitialized) break;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
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
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!await GoogleMapsNavigator.isInitialized()) {
        await GoogleMapsNavigator.initializeNavigationSession(
          taskRemovedBehavior: TaskRemovedBehavior.continueService,
        );
      }
      for (var attempt = 0; attempt < 10; attempt++) {
        _navigationSessionInitialized =
            await GoogleMapsNavigator.isInitialized();
        if (_navigationSessionInitialized) break;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
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
        _parkingLegFinished =
            _selectedParking != null &&
            _parkingOriginalPlace != null &&
            _selectedMode == KiwiTravelMode.drive;
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
    if (_selectedParking != null && _selectedMode == KiwiTravelMode.drive) {
      await _driveEngine.stop();
    }
    await _navigationController?.setNavigationUIEnabled(false);
    await _navigationController?.followMyLocation(CameraPerspective.tilted);
    if (!mounted) return;
    setState(() {
      _guidanceRunning = false;
      _junctionZoomed = false;
      _activeNavigationRoute = null;
      _destinationTitle = 'Destination';
      _journeyPhase = JourneyPhase.idle;
      _parkingLegFinished =
          _selectedParking != null &&
          _parkingOriginalPlace != null &&
          _selectedMode == KiwiTravelMode.drive;
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
      if (mounted) setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      final hasFix = await _driveEngine.waitForRoadSnappedLocation(
        timeout: const Duration(seconds: 6),
      );
      if (!hasFix && mounted) {
        setState(
          () => _message = _text(
            'Drive Mode is running while GPS settles. Keep the phone near a clear view of the sky.',
            '驾驶模式已启动，正在等待 GPS 稳定，请保持手机能够正常接收定位信号。',
          ),
        );
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
      ++_parkingRequest;
      _parkingPlaces = const [];
      _parkingOriginalPlace = null;
      _selectedParking = null;
      _parkingLoading = false;
      _parkingLegFinished = false;
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
    if (controller == null) return;
    _markerSyncing = true;
    final reportIds = _communityRoadEvents.map((event) => event.id).join(',');
    final signature =
        '${_driveEngine.cameras.length}:${_driveEngine.routeCameras.map((match) => match.camera.id).join(',')}:$reportIds:${_layers.markerSignature}';
    try {
      try {
        await MapSymbols.ensureRegistered();
      } catch (_) {
        /* Default pins remain visible. */
      }
      if (_cameraMarkers.isNotEmpty) {
        await controller.removeMarkers(_cameraMarkers);
      }
      if (_roadEventMarkers.isNotEmpty) {
        await controller.removeMarkers(_roadEventMarkers);
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
      final roadEventOptions = [
        for (final event in _communityRoadEvents)
          MarkerOptions(
            position: LatLng(
              latitude: event.location.latitude,
              longitude: event.location.longitude,
            ),
            icon: MapSymbols.roadReport ?? ImageDescriptor.defaultImage,
            zIndex: 35,
            infoWindow: InfoWindow(
              title: _roadEventLabel(event.type),
              snippet: () {
                final reporter =
                    event.metadata['reporterName']?.toString() ??
                    _text('Tasman driver', 'Tasman 用户');
                final time = _relativeTime(
                  DateTime.tryParse(
                        event.metadata['reportedAt']?.toString() ?? '',
                      ) ??
                      event.source.updatedAt,
                );
                final remaining = _remainingTime(event.validUntil);
                return '$reporter · $time · $remaining';
              }(),
            ),
          ),
      ];
      _roadEventMarkers = roadEventOptions.isEmpty
          ? []
          : (await controller.addMarkers(roadEventOptions))
                .whereType<Marker>()
                .toList();
      _markerSignature = signature;
    } catch (_) {
      _markerSignature = signature;
    } finally {
      _markerSyncing = false;
      final latestReportIds = _communityRoadEvents
          .map((event) => event.id)
          .join(',');
      final latest =
          '${_driveEngine.cameras.length}:${_driveEngine.routeCameras.map((match) => match.camera.id).join(',')}:$latestReportIds:${_layers.markerSignature}';
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
    _roadEventMarkers = [];
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
    _driveEngine.setCameraAlertFilter(value.alerts);
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('kiwi.layers.cameras', value.cameras),
      prefs.setBool('tasman.layers.spot_speed', value.spotSpeed),
      prefs.setBool('tasman.layers.average_speed', value.averageSpeed),
      prefs.setBool('kiwi.layers.red_light', value.redLight),
      prefs.setBool('tasman.layers.dual_red_speed', value.dualRedLightSpeed),
      prefs.setBool('tasman.layers.bus_lane', value.busLane),
      prefs.setBool('kiwi.layers.other', value.other),
      prefs.setBool('tasman.alerts.spot_speed', value.alertSpotSpeed),
      prefs.setBool('tasman.alerts.average_speed', value.alertAverageSpeed),
      prefs.setBool('tasman.alerts.red_light', value.alertRedLight),
      prefs.setBool(
        'tasman.alerts.dual_red_speed',
        value.alertDualRedLightSpeed,
      ),
      prefs.setBool('tasman.alerts.bus_lane', value.alertBusLane),
      prefs.setBool('tasman.alerts.other_camera', value.alertOther),
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
      isDismissible: true,
      enableDrag: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => MapLayerSheet(
        settings: _layers,
        mapProvider: _mapProvider,
        language: _appLanguage,
        onChanged: (value) => unawaited(_setMapLayers(value)),
      ),
    );
  }

  Future<void> _setNotificationPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (value) {
      await TasmanNotificationService.instance.requestPermission();
    }
    if (!mounted) return;
    setState(() {
      switch (key) {
        case 'tasman.notifications.safety_cameras':
          _notifySafetyCameras = value;
        case 'tasman.notifications.road_incidents':
          _notifyRoadIncidents = value;
        case 'tasman.notifications.community_reports':
          _notifyCommunityReports = value;
        case 'tasman.notifications.saved_route_disruptions':
          _notifySavedRouteDisruptions = value;
      }
    });
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

  Future<void> _showDirections() async {
    final route = _activeNavigationRoute;
    if (route == null) return;

    final controller = _navigationController;
    final size = MediaQuery.sizeOf(context);
    final sheetHeight = (size.height * .40).clamp(300.0, 390.0);
    final bottomInset = sheetHeight - 14;

    if (controller != null) {
      _following = false;
      await controller.setPadding(EdgeInsets.fromLTRB(24, 82, 24, bottomInset));
      await controller.showRouteOverview();
      await Future<void>.delayed(const Duration(milliseconds: 160));
      await controller.showRouteOverview();
    }

    if (!mounted) return;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final sheetColor = dark ? TasmanColors.darkOcean : scheme.surface;
    final headerColor = dark ? TasmanColors.darkSurface : scheme.surface;
    final badgeColor = dark
        ? TasmanColors.deepTeal.withValues(alpha: .38)
        : scheme.primaryContainer;
    final badgeForeground = dark ? TasmanColors.sky : scheme.onPrimaryContainer;
    final secondaryColor = dark
        ? TasmanColors.darkTextSecondary
        : scheme.onSurfaceVariant;
    final dividerColor = dark ? TasmanColors.darkBorder : theme.dividerColor;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: sheetColor,
      barrierColor: Colors.black.withValues(alpha: dark ? .46 : .28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxHeight: sheetHeight),
      builder: (sheetContext) {
        return Material(
          color: sheetColor,
          elevation: 0,
          child: Column(
            children: [
              ColoredBox(
                color: headerColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
                  child: Column(
                    children: [
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: dividerColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              Icons.route_rounded,
                              color: badgeForeground,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _text('Directions', '路线指引'),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  _text(
                                    '${(route.distanceMeters / 1000).toStringAsFixed(1)} km · ${route.steps.length} steps',
                                    '${(route.distanceMeters / 1000).toStringAsFixed(1)} 公里 · ${route.steps.length} 个步骤',
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: secondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: _text('Close', '关闭'),
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: dividerColor),
              Expanded(
                child: route.steps.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _text(
                              'Turn list is not available for this route.',
                              '这条路线暂时没有逐步指引。',
                            ),
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 3, 12, 18),
                        itemCount: route.steps.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: dividerColor),
                        itemBuilder: (context, index) {
                          final step = route.steps[index];
                          return ListTile(
                            dense: true,
                            minTileHeight: 48,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            leading: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: badgeColor,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: badgeForeground,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            title: Text(
                              step.instruction,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            trailing: Text(
                              step.distanceMeters >= 1000
                                  ? '${(step.distanceMeters / 1000).toStringAsFixed(1)} km'
                                  : '${step.distanceMeters} m',
                              style: TextStyle(
                                color: secondaryColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );

    if (controller != null) {
      await controller.setPadding(EdgeInsets.zero);
      if (mounted) _recenter();
    }
  }

  Future<void> _shareTripSnapshot() async {
    final nav = _driveEngine.navInfo;
    final remaining = nav?.distanceToFinalDestinationMeters;
    final arrival = nav?.timeToFinalDestinationSeconds;
    final details =
        'Tasman trip to $_destinationTitle. '
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

  IconData _quickActionIcon(String action) => switch (action) {
    'Home' => Icons.home_rounded,
    'Work' => Icons.work_rounded,
    'Frequent' => Icons.history_rounded,
    'Restaurants' => Icons.restaurant_rounded,
    'Shopping' => Icons.shopping_bag_rounded,
    'Gas' => Icons.local_gas_station_rounded,
    _ => Icons.place_rounded,
  };

  Widget _buildQuickActions() => SizedBox(
    height: 34,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final action in _quickActions)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              avatar: Icon(
                _quickActionIcon(action),
                size: 15,
                color: TasmanColors.ocean,
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              backgroundColor: Theme.of(context).colorScheme.surface
                  .withValues(alpha: .96),
              side: BorderSide(color: TasmanColors.sky.withValues(alpha: .28)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              label: Text(
                action,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              onPressed: () => _onQuickAction(action),
            ),
          ),
        SizedBox(
          width: 34,
          height: 34,
          child: IconButton.filledTonal(
            padding: EdgeInsets.zero,
            tooltip: _text('Edit shortcuts', '编辑快捷入口'),
            onPressed: _editQuickActions,
            icon: const Icon(Icons.tune_rounded, size: 17),
          ),
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
        borderRadius: BorderRadius.circular(16),
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .25),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22082F49),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Row(
            children: [
              item(Icons.map_outlined, _text('Map', '地图'), _recenter),
              item(
                Icons.explore_outlined,
                _text('Explore', '探索'),
                () => unawaited(_showExplore()),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap: _showGoSearch,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 3,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 55,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [TasmanColors.ocean, TasmanColors.teal],
                            ),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x300077B6),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.navigation_rounded,
                            size: 22,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _text('Start', '出发'),
                          style: TextStyle(
                            color: TasmanColors.ocean,
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
                Icons.bookmark_outline_rounded,
                _text('Saved', '收藏'),
                () => unawaited(_showSaved()),
              ),
              item(
                Icons.person_outline_rounded,
                _text('Me', '我的'),
                _showProfile,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onMapViewCreated(GoogleMapViewController controller) async {
    _browseController = controller;
    _cameraMarkers = [];
    _roadEventMarkers = [];
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
    _roadEventMarkers = [];
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
                    roadEvents: _communityRoadEvents,
                    onRoadEvent: (event) =>
                        unawaited(_showRoadEventDetails(event)),
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
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              top:
                  MediaQuery.paddingOf(context).top +
                  (_showSearchArea ? 190 : 130),
              right: 16,
              child: PointerInterceptor(
                child: Column(
                  children: [
                    Material(
                      color: Theme.of(context).colorScheme.surface,
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
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 5,
                      borderRadius: BorderRadius.circular(14),
                      child: IconButton(
                        tooltip: _text('Report road issue', '上报道路情况'),
                        icon: const Icon(
                          Icons.add_alert_rounded,
                          color: TasmanColors.ocean,
                        ),
                        onPressed: () => unawaited(_showRoadReport()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 5,
                      borderRadius: BorderRadius.circular(14),
                      child: IconButton(
                        tooltip: _locationControlTooltip,
                        icon: Icon(
                          _locationControlIcon,
                          color: _following
                              ? TasmanColors.ocean
                              : TasmanColors.deepOcean,
                        ),
                        onPressed: _cycleLocationCamera,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface
                            .withValues(alpha: .96),
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: .25),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x18082F49),
                            blurRadius: 18,
                            offset: Offset(0, 7),
                          ),
                        ],
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(19),
                        onTap: _showGoSearch,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(9, 8, 12, 8),
                          child: Row(
                            children: [
                              Container(
                                width: 39,
                                height: 39,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      TasmanColors.ocean,
                                      TasmanColors.teal,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.explore_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _text('Where to?', '去哪儿？'),
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      _text(
                                        'Navigate Aotearoa with Tasman',
                                        '用 Tasman 探索新西兰',
                                      ),
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: TasmanColors.ocean,
                                size: 19,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    _buildQuickActions(),
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
                        onReport: () => unawaited(_showRoadReport()),
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
            _TransientTasmanBanner(
              key: ValueKey(_message),
              message: _message!,
              onDismiss: () {
                if (mounted) setState(() => _message = null);
              },
            ),
          if (_parkingLegFinished &&
              _parkingOriginalPlace != null &&
              _selectedParking != null &&
              !_guidanceRunning)
            Align(
              alignment: Alignment.bottomCenter,
              child: ParkingContinuationCard(
                destinationTitle: _parkingOriginalPlace!.name,
                parkingTitle: _selectedParking!.name,
                isChinese: _appLanguage == 'zh',
                onContinue: () => unawaited(_continueOnFoot()),
                onEnd: () => setState(() {
                  _parkingLegFinished = false;
                  _parkingOriginalPlace = null;
                  _selectedParking = null;
                }),
              ),
            ),
          if (!_driveEngine.active &&
              !_transitTripRunning &&
              _selectedPoi == null &&
              !_parkingLegFinished)
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
                parkingPlaces: _parkingPlaces,
                selectedParkingId: _selectedParking?.id,
                finalDestinationTitle: _parkingOriginalPlace?.name,
                parkingLoading: _parkingLoading,
                isChinese: _appLanguage == 'zh',
                onParkingSelected: (parking) =>
                    unawaited(_selectParking(parking)),
                onDirectDestination: _parkingOriginalPlace == null
                    ? null
                    : () => unawaited(_restoreDirectDestination()),
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
