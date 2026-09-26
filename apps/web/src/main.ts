import './style.css';
declare global {
  interface Window { gm_authFailure?: () => void }
}

import { cameraLabel, distanceMeters, formatDistance, matchCamerasToRoute, nearestOnRoute, type Camera, type Coordinate, type Route, type RouteCamera, type RouteStep } from '@kiwi-lens/core';
import './account.css';
import { applyUiLanguage, t } from './i18n';
import { currentAccountEmail, initAccount, isSignedIn, ownReview, recentDestinations, rememberDestination, rememberPreferences, rememberRoute, renderAccount, saveOwnReview, savePlace, savedPlace, type AccountProfile } from './account';
import { lookAheadCenter } from './navigation-view';
import { initAutocomplete, type SuggestedPlace } from './autocomplete';
import { GoogleMapAdapter, type PoiSelection } from './google-map';
import { computeGoogleRoute, computeGoogleRoutes, enrichRouteLanes } from './google-routes';
import { fetchRoutePlan, formatModeDuration, routeFromOption, type RouteOption as PlannerRouteOption, type RoutePlan as PlannerRoutePlan, type TravelMode } from './route-planner';
import type { ParkingPlace } from './parking';

type Language = 'zh' | 'en';
type Place = { id: number; label: string; latitude: number; longitude: number };
type CameraResponse = { cameras: Camera[]; sourceUpdatedAt: string; checkedAt: string | null; syncStatus: string; syncError?: string | null; change?: { added: number; removed: number } };
const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const map = new GoogleMapAdapter();
let cameras: Camera[] = [];
let cameraResponse: CameraResponse | null = null;
let routeCameras: RouteCamera[] = [];
let current: Coordinate | null = null;
let currentPlaceLabel = '';
let placeLookupStarted = false;
let latestHeading: number | null = null;
let deviceHeading: number | null = null;
let compassListening = false;
let lastCompassPaint = 0;
let manualOrigin: Coordinate | null = null;
let destination: Coordinate | null = null;
let destinationName = '';
let route: Route | null = null;
let drivingAlternatives: Route[] = [];
let selectedDrivingRoute = 0;
let routePlan: PlannerRoutePlan | null = null;
let drivingFromPlanner = false;
let trafficLayerEnabled = true;
let selectedTravelMode: TravelMode = 'drive';
const routeStops: { label: string; coordinate: Coordinate }[] = [];
let navigating = false;
let uiMode: 'explore' | 'navigation' = 'explore';
let following = true;
let language: Language = 'en';
let voiceEnabled = true;
let laneGuidanceEnabled = localStorage.getItem('kiwi-lane-guidance') !== 'off';
let searchTarget: 'origin' | 'destination' | 'stop' = 'destination';
let routeAbort: AbortController | null = null;
let lastRerouteAt = 0;
let lastTurnKey = '';
let wakeLock: WakeLockSentinel | null = null;
let toastTimeout = 0;
type GpsStatus = 'idle' | 'locating' | 'active' | 'denied' | 'unavailable';
let gpsStatus: GpsStatus = 'idle';
let gpsAccuracy: number | null = null;
let gpsWatchId: number | null = null;
let gpsRequesting = false;
let selectedPoi: PoiSelection | null = null;
let currentSpeedKph = 0;
let speedLimitKph: number | null = null;
let lastSpeedLimitLookupAt = 0;
let lastSpeedLimitCoordinate: Coordinate | null = null;
let speedLimitLookupPending = false;
const spokenCameras = new Set<string>();

type ParkingDestination = { coordinate: Coordinate; name: string };
let parkingDestination: ParkingDestination | null = null;
let parkingPlaces: ParkingPlace[] = [];
let selectedParking: ParkingPlace | null = null;
let parkingLoading = false;
let parkingError = '';
let parkingSearchSequence = 0;
let parkedAtParking = false;

function setDestinationSelection(coordinate: Coordinate, name: string) {
  ++parkingSearchSequence;
  parkingDestination = null;
  selectedParking = null;
  parkedAtParking = false;
  parkingPlaces = [];
  parkingLoading = false;
  parkingError = '';
  selectedTravelMode = 'drive';
  destination = coordinate;
  destinationName = name;
  map.renderParking([], null, selectParking);
  renderParking();
  void loadParking();
}

async function loadParking() {
  const target = destination;
  if (!target || parkingDestination) return;
  const request = ++parkingSearchSequence;
  parkingLoading = true;
  parkingError = '';
  renderParking();
  try {
    const official = await api<{ places: ParkingPlace[] }>(
      `/api/parking?at=${target[0]},${target[1]}`
    ).catch(() => null);
    const places = official?.places?.length ? official.places : await map.searchParking(target);
    if (request !== parkingSearchSequence || !destination || parkingDestination) return;
    parkingPlaces = places;
    parkingError = '';
  } catch {
    if (request !== parkingSearchSequence) return;
    parkingPlaces = [];
    parkingError = language === 'zh' ? '停车地点暂时无法加载。' : 'Parking places are temporarily unavailable.';
  } finally {
    if (request === parkingSearchSequence) {
      parkingLoading = false;
      renderParking();
    }
  }
}

function selectParking(place: ParkingPlace) {
  if (navigating || !destination) return;
  if (!parkingDestination) parkingDestination = { coordinate: destination, name: destinationName };
  selectedParking = place;
  parkedAtParking = false;
  destination = place.coordinate;
  destinationName = place.name;
  selectedTravelMode = 'drive';
  map.renderParking(parkingPlaces, place.id, selectParking);
  renderParking();
  if (manualOrigin || current) void planRoute();
}

function driveToDestination() {
  if (!parkingDestination) return;
  destination = parkingDestination.coordinate;
  destinationName = parkingDestination.name;
  parkingDestination = null;
  selectedParking = null;
  parkedAtParking = false;
  selectedTravelMode = 'drive';
  map.renderParking(parkingPlaces, null, selectParking);
  renderParking();
  if (manualOrigin || current) void planRoute();
}

function continueOnFoot() {
  if (!parkingDestination || !selectedParking || !parkedAtParking) return;
  destination = parkingDestination.coordinate;
  destinationName = parkingDestination.name;
  parkingDestination = null;
  selectedParking = null;
  parkedAtParking = false;
  parkingPlaces = [];
  selectedTravelMode = 'walk';
  routeStops.splice(0, routeStops.length);
  manualOrigin = null;
  renderStops();
  map.renderParking([], null, selectParking);
  route = null;
  drivingAlternatives = [];
  routePlan = null;
  map.clearRoute();
  ($('driveButton') as HTMLButtonElement).disabled = true;
  $('travelModes').hidden = true;
  $('routeAlternatives').hidden = true;
  renderParking();
  if (current) void planRoute('walk');
  else requestGps();
}

function renderParking() {
  const section = $('parkingSection');
  const hint = $('navParkingHint');
  section.hidden = !destination || selectedTravelMode !== 'drive';
  $('navDestinationLabel').textContent = selectedParking && selectedTravelMode === 'drive'
    ? (language === 'zh' ? '停车点' : 'PARKING STOP')
    : (language === 'zh' ? '目的地' : 'DESTINATION');
  hint.hidden = !selectedParking || !parkingDestination || selectedTravelMode !== 'drive';
  if (section.hidden) {
    map.renderParking([], null, selectParking);
    return;
  }
  const target = parkingDestination || { coordinate: destination!, name: destinationName };
  $('parkingKicker').textContent = language === 'zh' ? '到达前，先看停车' : 'ARRIVE WITH A PLAN';
  $('parkingTitle').textContent = language === 'zh' ? '终点附近停车' : 'Parking near your destination';
  const isAtSource = parkingPlaces[0]?.source === 'at';
  $('parkingSourceNote').textContent = isAtSource
    ? (language === 'zh' ? '来源：AT Open GIS · 总车位并非实时空位' : 'Source: AT Open GIS · total spaces are not live availability')
    : (language === 'zh' ? '来源：Google Places · 不提供实时空位' : 'Source: Google Places · live spaces unavailable');
  const sourceLink = $('parkingSourceLink') as HTMLAnchorElement;
  sourceLink.hidden = !isAtSource;
  sourceLink.textContent = language === 'zh' ? 'AT 原始数据 ↗' : 'AT source ↗';
  $('parkingSummary').textContent = selectedParking
    ? (language === 'zh'
      ? `已选 ${selectedParking.name}，距 ${target.name} 约 ${formatDistance(selectedParking.distanceMeters, language)}（直线距离）。`
      : `Driving to ${selectedParking.name} · ${formatDistance(selectedParking.distanceMeters, language)} from ${target.name} as the crow flies.`)
    : (language === 'zh'
      ? '先选停车点，导航会以它为驾车终点；距离为直线距离，停车后可继续步行。'
      : 'Choose a parking place for the driving leg, then continue on foot. Distances are straight line.');
  if (!hint.hidden) hint.textContent = language === 'zh'
    ? `停车：${selectedParking!.name} · 之后步行到 ${target.name}`
    : `Parking: ${selectedParking!.name} · then walk to ${target.name}`;
  const list = $('parkingList');
  list.replaceChildren();
  if (parkingLoading && !parkingPlaces.length) {
    list.textContent = language === 'zh' ? '正在寻找停车点…' : 'Finding nearby parking…';
  } else if (parkingError && !parkingPlaces.length) {
    list.textContent = parkingError;
  } else if (!parkingPlaces.length) {
    list.textContent = language === 'zh' ? '附近暂无已收录停车点。' : 'No listed parking places nearby.';
  } else {
    for (const place of parkingPlaces) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'parking-option' + (place.id === selectedParking?.id ? ' selected' : '');
      button.setAttribute('aria-pressed', String(place.id === selectedParking?.id));
      const icon = document.createElement('span');
      icon.className = 'parking-option-icon';
      icon.textContent = 'P';
      const copy = document.createElement('span');
      copy.className = 'parking-option-copy';
      const name = document.createElement('strong');
      name.textContent = place.name;
      const address = document.createElement('small');
      address.textContent = place.address || (language === 'zh' ? '停车地点' : 'Parking place');
      copy.append(name, address);
      if (place.source === 'at') {
        const details = document.createElement('small');
        details.className = 'parking-option-detail';
        details.textContent = [
          place.totalSpaces !== null ? (language === 'zh' ? `总车位 ${place.totalSpaces}` : `${place.totalSpaces} total spaces`) : '',
          place.mobilitySpaces !== null ? (language === 'zh' ? `无障碍 ${place.mobilitySpaces}` : `${place.mobilitySpaces} accessible`) : '',
          place.clearanceMeters !== null ? (language === 'zh' ? `限高 ${place.clearanceMeters}m` : `${place.clearanceMeters}m clearance`) : ''
        ].filter(Boolean).join(' · ') || 'AT Open GIS';
        copy.append(details);
      }
      const distance = document.createElement('span');
      distance.className = 'parking-option-distance';
      distance.textContent = formatDistance(place.distanceMeters, language);
      button.append(icon, copy, distance);
      button.onclick = () => selectParking(place);
      list.append(button);
    }
  }
  const actions = $('parkingActions');
  actions.replaceChildren();
  actions.hidden = !selectedParking;
  if (selectedParking) {
    const direct = document.createElement('button');
    direct.type = 'button';
    direct.textContent = language === 'zh' ? '改为直接到目的地' : 'Drive to destination instead';
    direct.onclick = driveToDestination;
    actions.append(direct);
    const detailsUrl = selectedParking.source === 'at'
      ? 'https://at.govt.nz/driving-and-parking/find-parking'
      : selectedParking.googleMapsURI;
    if (detailsUrl) {
      const details = document.createElement('a');
      details.href = detailsUrl;
      details.target = '_blank';
      details.rel = 'noopener noreferrer';
      details.textContent = selectedParking.source === 'at'
        ? (language === 'zh' ? 'AT 费用与规则 ↗' : 'AT rates & rules ↗')
        : (language === 'zh' ? '查看地点 ↗' : 'Place details ↗');
      actions.append(details);
    }
    if (parkedAtParking) {
      const walk = document.createElement('button');
      walk.type = 'button';
      walk.className = 'primary';
      walk.textContent = language === 'zh' ? '继续步行到目的地 →' : 'Continue on foot →';
      walk.onclick = continueOnFoot;
      actions.prepend(walk);
    }
  }
  map.renderParking(parkingPlaces, selectedParking?.id || null, selectParking);
}


function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char] || char);
}

function toast(message: string) {
  const element = $('toast');
  element.textContent = message;
  element.hidden = false;
  window.clearTimeout(toastTimeout);
  toastTimeout = window.setTimeout(() => { element.hidden = true; }, 4500);
}

const API_BASE_URL = '';

async function api<T>(path: string, signal?: AbortSignal): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, { signal });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error || `HTTP ${response.status}`);
  }
  return response.json() as Promise<T>;
}

function renderTripFlags() {
  $('sheetVoice').textContent = language === 'zh'
    ? `语音 ${voiceEnabled ? '✓' : '关闭'}`
    : `Voice ${voiceEnabled ? '✓' : 'off'}`;
  $('sheetLane').textContent = language === 'zh'
    ? `车道 ${laneGuidanceEnabled ? '✓' : '关闭'}`
    : `Lanes ${laneGuidanceEnabled ? '✓' : 'off'}`;
  $('sheetAccount').textContent = isSignedIn()
    ? (language === 'zh' ? '账号已同步' : 'Account synced')
    : (language === 'zh' ? '访客模式' : 'Guest mode');
  const voiceChip = $('navVoiceChip');
  const lanesChip = $('navLanesChip');
  voiceChip.textContent = language === 'zh' ? `语音 ${voiceEnabled ? '✓' : '关闭'}` : `Voice ${voiceEnabled ? '✓' : 'off'}`;
  lanesChip.textContent = language === 'zh' ? `车道 ${laneGuidanceEnabled ? '✓' : '关闭'}` : `Lanes ${laneGuidanceEnabled ? '✓' : 'off'}`;
  voiceChip.setAttribute('aria-pressed', String(voiceEnabled));
  lanesChip.setAttribute('aria-pressed', String(laneGuidanceEnabled));
}

function setUiMode(next: 'explore' | 'navigation') {
  uiMode = next;
  document.body.dataset.mode = next;
  $('navBanner').hidden = next !== 'navigation';
  $('navSheet').hidden = next !== 'navigation';
  $('bottomPanel').hidden = next === 'navigation';
  $('searchPanel').hidden = next === 'navigation';
  if (next === 'navigation') {
    hidePoiCard();
    $('navSecondary').hidden = true;
    $('navSheetHandle').setAttribute('aria-expanded', 'false');
    document.body.classList.remove('nav-sheet-expanded');
    $('navSheetHandle').setAttribute('aria-label', language === 'zh' ? '展开行程详情' : 'Show trip details');
    requestAnimationFrame(updateNavigationOverlayLayout);
  }
}

function updateNavigationOverlayLayout() {
  if (uiMode !== 'navigation') return;
  document.body.style.setProperty('--nav-sheet-clearance', `${Math.ceil($('navSheet').getBoundingClientRect().height) + 12}px`);
  document.body.style.setProperty('--nav-banner-clearance', `${Math.ceil($('navBanner').getBoundingClientRect().bottom) + 18}px`);
}

function renderSpeedHud() {
  const hud = $('speedHud');
  const speeding = speedLimitKph !== null && currentSpeedKph > speedLimitKph;
  hud.classList.toggle('speeding', speeding);
  $('speedValue').textContent = String(Math.round(currentSpeedKph));
  $('speedLimitValue').textContent = speedLimitKph === null
    ? (language === 'zh' ? '限速 —' : 'LIMIT —')
    : (language === 'zh' ? `限速 ${speedLimitKph}` : `LIMIT ${speedLimitKph}`);
  $('sheetSpeedLimit').textContent = speedLimitKph === null ? '—' : `${speedLimitKph} km/h`;
  $('navSpeedLimit').textContent = speedLimitKph === null ? '—' : `${speedLimitKph} km/h`;
}

async function refreshSpeedLimit(coordinate: Coordinate) {
  if (speedLimitLookupPending) return;
  const moved = lastSpeedLimitCoordinate ? distanceMeters(lastSpeedLimitCoordinate, coordinate) : Infinity;
  if (Date.now() - lastSpeedLimitLookupAt < 15000 && moved < 75) return;
  speedLimitLookupPending = true;
  lastSpeedLimitLookupAt = Date.now();
  lastSpeedLimitCoordinate = coordinate;
  try {
    const result = await api<{ speedLimitKph: number | null }>(
      `/api/speed-limit?at=${coordinate[0]},${coordinate[1]}`
    );
    speedLimitKph = Number.isFinite(result.speedLimitKph) ? result.speedLimitKph : null;
    renderSpeedHud();
  } catch {
    // Keep the last known legal limit if the network lookup temporarily fails.
  } finally {
    speedLimitLookupPending = false;
  }
}

function renderCameras() {
  const onRoute = new Set(routeCameras.map((item) => item.camera.id));
  map.renderCameras(cameras, onRoute, language);
  $('cameraRouteCount').textContent = route ? String(routeCameras.length) : '—';
  $('navCameraCount').textContent = route ? String(routeCameras.length) : '—';
}

async function loadCameras() {
  try {
    const data = await api<CameraResponse>('/api/cameras');
    if (!Array.isArray(data.cameras) || data.cameras.length < 50) throw new Error('Camera data failed validation');
    cameraResponse = data;
    cameras = data.cameras;
    localStorage.setItem('kiwi-cameras', JSON.stringify(data));
  } catch {
    try {
      const cached = JSON.parse(localStorage.getItem('kiwi-cameras') || 'null') as CameraResponse | null;
      if (cached?.cameras?.length) { cameraResponse = { ...cached, syncStatus: 'offline' }; cameras = cached.cameras; }
    } catch { /* ignore damaged local cache */ }
  }
  if (cameraResponse) {
    $('dataStatus').textContent = `${cameras.length} ${t(language, 'cameraCount')} · ${cameraResponse.sourceUpdatedAt}${cameraResponse.syncStatus === 'live' ? '' : ` · ${t(language, 'cached')}`}`;
    $('sourceDate').textContent = cameraResponse.sourceUpdatedAt;
    $('checkedAt').textContent = cameraResponse.checkedAt ? new Date(cameraResponse.checkedAt).toLocaleString(language === 'zh' ? 'zh-NZ' : 'en-NZ') : t(language, 'neverChecked');
    $('syncStatus').textContent = t(language, cameraResponse.syncStatus === 'live' ? 'synced' : cameraResponse.syncStatus === 'stale' ? 'stale' : cameraResponse.syncStatus === 'offline' ? 'offline' : 'seed');
    if (route) routeCameras = matchCamerasToRoute(cameras, route);
    renderCameras();
  } else $('dataStatus').textContent = t(language, 'camerasUnavailable');
}

function onDeviceOrientation(event: DeviceOrientationEvent) {
  const iosHeading = (event as DeviceOrientationEvent & { webkitCompassHeading?: number }).webkitCompassHeading;
  const measured = Number.isFinite(iosHeading)
    ? iosHeading!
    : event.absolute && event.alpha !== null ? 360 - event.alpha : null;
  if (measured === null || !Number.isFinite(measured)) return;
  const next = (measured + 360) % 360;
  if (deviceHeading !== null && Math.abs(((next - deviceHeading + 540) % 360) - 180) < 2 && Date.now() - lastCompassPaint < 200) return;
  deviceHeading = next;
  lastCompassPaint = Date.now();
  if (!current) return;
  map.setRadarHeading(deviceHeading);
  if (following) map.setFollowHeading(deviceHeading);
  map.setPosition(current, deviceHeading);
}

function listenToCompass() {
  if (compassListening) return;
  compassListening = true;
  window.addEventListener('deviceorientation', onDeviceOrientation);
  window.addEventListener('deviceorientationabsolute', onDeviceOrientation as EventListener);
}

function requestCompassFromGesture() {
  if (typeof DeviceOrientationEvent === 'undefined') return;
  const orientation = DeviceOrientationEvent as typeof DeviceOrientationEvent & { requestPermission?: (absolute?: boolean) => Promise<'granted' | 'denied'> };
  if (!orientation.requestPermission) { listenToCompass(); return; }
  if (compassListening) return;
  void orientation.requestPermission(true).then((result) => {
    if (result === 'granted') listenToCompass();
  }).catch(() => { /* GPS course remains the fallback. */ });
}

function updatePosition(latitude: number, longitude: number, heading: number | null, accuracy: number, speedMetersPerSecond?: number | null) {
  if (!(latitude > -48 && latitude < -34 && longitude > 166 && longitude < 179)) return;
  current = [longitude, latitude];
  latestHeading = heading;
  if (!placeLookupStarted) {
    placeLookupStarted = true;
    void api<{ label: string }>(`/api/reverse?at=${longitude},${latitude}`).then(({ label }) => {
      currentPlaceLabel = label;
      ($('originInput') as HTMLInputElement).placeholder = `${t(language, 'currentPlace')}: ${label}`;
      $('gpsBadge').title = label;
      toast(`${t(language, 'currentPlace')}: ${label}`);
    }).catch(() => { /* GPS coordinates remain available if reverse lookup fails */ });
  }
  gpsStatus = 'active';
  gpsAccuracy = accuracy;
  renderGpsStatus();
  currentSpeedKph = Number.isFinite(speedMetersPerSecond) && (speedMetersPerSecond || 0) > 0
    ? (speedMetersPerSecond || 0) * 3.6
    : 0;
  renderSpeedHud();
  void refreshSpeedLimit(current);
  const mapHeading = deviceHeading ?? heading;
  map.setRadarHeading(mapHeading);
  map.setPosition(current, mapHeading);
  if (following) {
    const center = navigating && route ? lookAheadCenter(current, heading, route) : current;
    if (navigating && route) map.focusNavigation(center);
    else map.setView(center, 15);
    map.setFollowHeading(mapHeading);
  }
  if (destination && !route && !manualOrigin) void planRoute();
  if (navigating && route) updateGuidance();
}

function renderGpsStatus() {
  const badge = $('gpsBadge');
  const text = $('gpsBadgeText');
  badge.classList.toggle('error', gpsStatus === 'denied' || gpsStatus === 'unavailable');
  if (gpsStatus === 'active' && gpsAccuracy !== null) text.textContent = `GPS ${Math.round(gpsAccuracy)} m`;
  else if (gpsStatus === 'locating') text.textContent = t(language, 'locating');
  else if (gpsStatus === 'denied') text.textContent = t(language, 'permissionDenied');
  else if (gpsStatus === 'unavailable') text.textContent = t(language, 'gpsTemporary');
  else text.textContent = t(language, 'enableLocation');
  $('sheetGps').textContent = gpsStatus === 'active' && gpsAccuracy !== null
    ? `±${Math.round(gpsAccuracy)} m`
    : '—';
  $('navGpsChip').textContent = gpsStatus === 'active' && gpsAccuracy !== null
    ? `GPS ±${Math.round(gpsAccuracy)} m` : 'GPS —';
}

function handleGpsError(error: GeolocationPositionError) {
  if (error.code === error.PERMISSION_DENIED && gpsWatchId !== null) {
    navigator.geolocation.clearWatch(gpsWatchId);
    gpsWatchId = null;
  }
  gpsStatus = error.code === error.PERMISSION_DENIED ? 'denied' : 'unavailable';
  gpsAccuracy = null;
  renderGpsStatus();
  if (error.code === error.PERMISSION_DENIED) toast(t(language, 'permissionHelp'));
}

function startGpsWatch() {
  if (!navigator.geolocation || gpsWatchId !== null) return;
  gpsStatus = 'locating';
  renderGpsStatus();
  gpsWatchId = navigator.geolocation.watchPosition(
    ({ coords }) => updatePosition(coords.latitude, coords.longitude, Number.isFinite(coords.heading) ? coords.heading : null, coords.accuracy, coords.speed),
    handleGpsError,
    { enableHighAccuracy: true, maximumAge: 1000, timeout: 18000 }
  );
}

function requestGps() {
  if (!navigator.geolocation) {
    gpsStatus = 'unavailable';
    renderGpsStatus();
    return;
  }
  if (gpsRequesting || gpsStatus === 'active') return;
  gpsRequesting = true;
  gpsStatus = 'locating';
  renderGpsStatus();
  navigator.geolocation.getCurrentPosition(
    ({ coords }) => {
      gpsRequesting = false;
      updatePosition(coords.latitude, coords.longitude, Number.isFinite(coords.heading) ? coords.heading : null, coords.accuracy, coords.speed);
      startGpsWatch();
    },
    (error) => {
      gpsRequesting = false;
      handleGpsError(error);
    },
    { enableHighAccuracy: true, maximumAge: 0, timeout: 18000 }
  );
}

async function initGps() {
  if (!navigator.geolocation) {
    gpsStatus = 'unavailable';
    renderGpsStatus();
    return;
  }
  const standalone = window.matchMedia('(display-mode: standalone)').matches || Boolean((navigator as Navigator & { standalone?: boolean }).standalone);
  if ('permissions' in navigator) {
    try {
      const permission = await navigator.permissions.query({ name: 'geolocation' as PermissionName });
      if (permission.state === 'granted') startGpsWatch();
      else {
        gpsStatus = permission.state === 'denied' ? 'denied' : 'idle';
        renderGpsStatus();
        if (permission.state === 'prompt' && !standalone) requestGps();
      }
      permission.onchange = () => {
        if (permission.state === 'granted') startGpsWatch();
        else {
          if (gpsWatchId !== null) {
            navigator.geolocation.clearWatch(gpsWatchId);
            gpsWatchId = null;
          }
          gpsStatus = permission.state === 'denied' ? 'denied' : 'idle';
          gpsAccuracy = null;
          renderGpsStatus();
        }
      };
      return;
    } catch { /* older Safari may not expose geolocation through Permissions API */ }
  }
  if (standalone) {
    gpsStatus = 'idle';
    renderGpsStatus();
  } else requestGps();
}

function renderStops() {
  const editor = $('stopEditor');
  const list = $('stopList');
  list.replaceChildren();
  routeStops.forEach((stop, index) => {
    const chip = document.createElement('div');
    chip.className = 'stop-chip';
    const label = document.createElement('span');
    label.textContent = `${index + 1}. ${stop.label}`;
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.textContent = '×';
    remove.onclick = () => {
      routeStops.splice(index, 1);
      renderStops();
      if (destination && (manualOrigin || current)) void planRoute();
    };
    chip.append(label, remove);
    list.append(chip);
  });
  editor.hidden = routeStops.length === 0 && document.activeElement !== $('stopInput');
}

function selectedPlannerOption(): PlannerRouteOption | null {
  if (!routePlan) return null;
  const options = routePlan.options.filter((option) => option.mode === selectedTravelMode);
  if (selectedTravelMode === 'drive') return options[selectedDrivingRoute] || options[0] || null;
  return options[0] || null;
}

function trafficVisuals() {
  const plannerDriving = routePlan?.options.filter((option) => option.mode === 'drive') || [];
  return drivingAlternatives.map((fallback, index) => ({
    route: fallback,
    trafficIntervals: drivingFromPlanner ? plannerDriving[index]?.trafficIntervals || [] : []
  }));
}

function renderRouteInfo(option: PlannerRouteOption | null) {
  const root = $('routeInfoCards');
  const navCard = $('navTrafficCard');
  root.replaceChildren();
  root.hidden = true;
  navCard.hidden = true;
  navCard.replaceChildren();
  if (!option) return;
  if (option.mode === 'drive' && !option.trafficIntervals.length) {
    const card = document.createElement('div');
    card.className = 'route-info-card';
    card.textContent = language === 'zh'
      ? '实时交通区间暂不可用；路线颜色不代表当前路况。'
      : 'Live traffic segments are unavailable; route color does not indicate current traffic.';
    root.append(card);
    root.hidden = false;
  }

  if (option.mode === 'drive' && (option.traffic.slow > 0 || option.traffic.trafficJam > 0 || option.warnings.length)) {
    const card = document.createElement('div');
    card.className = 'route-info-card warning';
    const jam = option.traffic.trafficJam;
    const slow = option.traffic.slow;
    const message = jam > 0
      ? `${jam} heavy-traffic section${jam === 1 ? '' : 's'} ahead`
      : `${slow} slow section${slow === 1 ? '' : 's'} ahead`;
    card.innerHTML = `<strong>⚠ Traffic advisory</strong><span>${escapeHtml(message)}${option.warnings[0] ? ` · ${escapeHtml(option.warnings[0])}` : ''}</span>`;
    root.append(card);
    root.hidden = false;
    navCard.textContent = `⚠ ${message}${option.warnings[0] ? ` · ${option.warnings[0]}` : ''}`;
    navCard.hidden = false;
  }

  if (option.mode === 'transit' && option.transit.length) {
    for (const leg of option.transit) {
      const card = document.createElement('div');
      card.className = 'route-info-card transit';
      const title = [leg.lineName, leg.headsign].filter(Boolean).join(' → ') || leg.vehicleName || leg.vehicleType || 'Transit';
      const details = [leg.departureStop, leg.arrivalStop].filter(Boolean).join(' → ');
      card.innerHTML = `<strong>🚆 ${escapeHtml(title)}</strong><span>${escapeHtml(details)}${leg.stopCount ? ` · ${leg.stopCount} stops` : ''}</span>`;
      root.append(card);
    }
    root.hidden = false;
  }
}

function applyDrivingRoute(index: number) {
  const next = drivingAlternatives[index];
  if (!next || !destination) return;
  selectedDrivingRoute = index;
  route = next;
  routeCameras = matchCamerasToRoute(cameras, route);
  renderCameras();
  map.renderRoute(route, destination, navigating);
  map.setTrafficEnabled(trafficLayerEnabled);
  map.renderTrafficRoutes(trafficVisuals(), selectedDrivingRoute, (chosen) => {
    if (chosen === selectedDrivingRoute || navigating) return;
    applyDrivingRoute(chosen);
    renderRoutePlanner();
  });
  $('tripDistance').textContent = formatDistance(route.distance, language);
  $('tripArrival').textContent = new Date(Date.now() + route.duration * 1000).toLocaleTimeString(
    language === 'zh' ? 'zh-NZ' : 'en-NZ',
    { hour: '2-digit', minute: '2-digit' }
  );
  $('navDistance').textContent = $('tripDistance').textContent;
  $('navArrival').textContent = $('tripArrival').textContent;
  $('navCameraCount').textContent = String(routeCameras.length);
  $('cameraRouteCount').textContent = String(routeCameras.length);
  $('navRouteSteps').textContent = String(route.steps.length);
  $('sheetRouteSteps').textContent = String(route.steps.length);
  ($('driveButton') as HTMLButtonElement).disabled = false;
}

function renderRoutePlanner() {
  const modes = $('travelModes');
  const alternatives = $('routeAlternatives');
  const actions = $('planningActions');
  modes.hidden = !routePlan && drivingAlternatives.length === 0;
  actions.hidden = modes.hidden;
  $('trafficLegend').hidden = modes.hidden || selectedTravelMode !== 'drive' || !routePlan?.trafficAvailable;
  if (modes.hidden) {
    alternatives.hidden = true;
    $('routeInfoCards').hidden = true;
    return;
  }

  const modeIds: Record<TravelMode, string> = {
    drive: 'modeDriveTime',
    transit: 'modeTransitTime',
    walk: 'modeWalkTime',
    bicycle: 'modeBicycleTime'
  };
  for (const mode of ['drive', 'transit', 'walk', 'bicycle'] as TravelMode[]) {
    const option = routePlan?.options.find((item) => item.mode === mode);
    $(modeIds[mode]).textContent = mode === 'drive' && drivingAlternatives[0]
      ? formatModeDuration(drivingAlternatives[0].duration)
      : formatModeDuration(option?.durationSeconds);
    const button = modes.querySelector<HTMLButtonElement>(`button[data-mode="${mode}"]`);
    if (button) {
      const available = mode === 'drive' ? drivingAlternatives.length > 0 : Boolean(option);
      button.disabled = !available;
      button.classList.toggle('selected', selectedTravelMode === mode);
    }
  }

  alternatives.replaceChildren();
  if (selectedTravelMode === 'drive') {
    drivingAlternatives.forEach((item, index) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'route-option-card' + (selectedDrivingRoute === index ? ' selected' : '');
      button.innerHTML = `<strong>${escapeHtml(formatModeDuration(item.duration))}</strong><span>${escapeHtml(formatDistance(item.distance, language))}${index === 0 ? ' · recommended' : ''}</span>`;
      button.onclick = () => {
        applyDrivingRoute(index);
        renderRoutePlanner();
      };
      alternatives.append(button);
    });
    alternatives.hidden = drivingAlternatives.length < 2;
    renderRouteInfo(selectedPlannerOption());
    ($('driveButton') as HTMLButtonElement).disabled = drivingAlternatives.length === 0;
    $('driveLabel').textContent = language === 'zh' ? '开始导航' : 'Start';
    return;
  }

  const option = selectedPlannerOption();
  if (option) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'route-option-card selected';
    button.innerHTML = `<strong>${escapeHtml(formatModeDuration(option.durationSeconds))}</strong><span>${escapeHtml(formatDistance(option.distanceMeters, language))}</span>`;
    alternatives.append(button);
    alternatives.hidden = false;
    if (destination) {
      const preview = routeFromOption(option);
      route = preview;
      routeCameras = [];
      map.clearTrafficRoutes();
      map.setTrafficEnabled(false);
      if (preview.coordinates.length >= 2) map.renderRoute(preview, destination, navigating);
    }
    $('tripDistance').textContent = formatDistance(option.distanceMeters, language);
    $('tripArrival').textContent = new Date(Date.now() + option.durationSeconds * 1000).toLocaleTimeString(
      language === 'zh' ? 'zh-NZ' : 'en-NZ',
      { hour: '2-digit', minute: '2-digit' }
    );
    $('cameraRouteCount').textContent = '—';
    $('navCameraCount').textContent = '—';
    ($('driveButton') as HTMLButtonElement).disabled = route?.coordinates.length ? false : true;
    $('driveLabel').textContent = selectedTravelMode === 'transit'
      ? (language === 'zh' ? '开始行程' : 'Start trip')
      : (language === 'zh' ? '开始导航' : 'Start');
  } else {
    alternatives.hidden = true;
    ($('driveButton') as HTMLButtonElement).disabled = true;
  }
  renderRouteInfo(option);
}

async function search(target: 'origin' | 'destination' | 'stop') {
  searchTarget = target;
  const input = target === 'origin'
    ? $('originInput') as HTMLInputElement
    : target === 'stop'
      ? $('stopInput') as HTMLInputElement
      : $('destinationInput') as HTMLInputElement;
  const query = input.value.trim();
  if (query.length < 3) { toast(t(language, 'minQuery')); return; }
  const results = $('searchResults');
  results.hidden = false;
  results.innerHTML = `<div class="search-message">${t(language, 'searching')}</div>`;
  try {
    const places = await api<Place[]>(`/api/search?q=${encodeURIComponent(query)}`);
    results.replaceChildren();
    if (!places.length) { results.innerHTML = `<div class="search-message">${t(language, 'noResults')}</div>`; return; }
    for (const place of places) {
      const button = document.createElement('button');
      button.className = 'result-item';
      button.type = 'button';
      const pin = document.createElement('span');
      pin.className = 'result-pin';
      pin.textContent = '⌖';
      const label = document.createElement('span');
      label.textContent = place.label;
      button.append(pin, label);
      button.onclick = () => {
        results.hidden = true;
        const coordinate: Coordinate = [place.longitude, place.latitude];
        if (target === 'origin') {
          manualOrigin = coordinate;
          ($('originInput') as HTMLInputElement).value = place.label.split(',').slice(0, 2).join(',');
        } else if (target === 'stop') {
          routeStops.push({ label: place.label.split(',').slice(0, 2).join(','), coordinate });
          ($('stopInput') as HTMLInputElement).value = '';
          renderStops();
        } else {
          setDestinationSelection(coordinate, place.label.split(',').slice(0, 2).join(','));
          ($('destinationInput') as HTMLInputElement).value = destinationName;
          $('clearDestinationButton').hidden = false;
          void rememberDestination({ label: place.label, latitude: place.latitude, longitude: place.longitude });
        }
        if (destination && (manualOrigin || current)) void planRoute();
        else if (destination) toast(t(language, 'chooseOrigin'));
      };
      results.append(button);
    }
  } catch (error) {
    results.innerHTML = `<div class="search-message">${t(language, 'searchFailed')}: ${escapeHtml(String((error as Error).message))}</div>`;
  }
}

async function planRoute(modeOverride?: TravelMode) {
  const from = manualOrigin || current;
  if (!from || !destination) return;
  routeAbort?.abort();
  routeAbort = new AbortController();
  const signal = routeAbort.signal;
  $('tripEyebrow').textContent = 'CALCULATING ROUTE';
  $('tripTitle').textContent = t(language, 'routeCalculating');
  const requestedMode = modeOverride || selectedTravelMode;
  try {
    const stopCoordinates = routeStops.map((stop) => stop.coordinate);
    const stopQuery = stopCoordinates.length
      ? `&stops=${encodeURIComponent(stopCoordinates.map((stop) => stop.join(',')).join(';'))}`
      : '';
    const [planner, laneRoute] = await Promise.all([
      fetchRoutePlan(API_BASE_URL, from, destination, stopCoordinates, signal).catch(() => null),
      api<Route>(`/api/route?from=${from.join(',')}&to=${destination.join(',')}${stopQuery}`, signal).catch(() => undefined)
    ]);
    routePlan = planner;
    const plannedDriving = planner?.provider === 'google'
      ? planner.options.filter((option) => option.mode === 'drive')
      : [];
    drivingFromPlanner = Boolean(plannedDriving?.length && plannedDriving.every((option) => routeFromOption(option).coordinates.length >= 2));
    if (drivingFromPlanner) {
      drivingAlternatives = plannedDriving!.map((option) => enrichRouteLanes(routeFromOption(option), laneRoute));
    } else if (stopCoordinates.length) {
      if (!laneRoute) throw new Error('Route geometry is empty');
      drivingAlternatives = [laneRoute];
    } else {
      drivingAlternatives = (await computeGoogleRoutes(from, destination, language))
        .map((item) => enrichRouteLanes(item, laneRoute));
    }
    if (signal.aborted) return;
    if (!drivingAlternatives.length) throw new Error('Route geometry is empty');
    selectedDrivingRoute = 0;
    applyDrivingRoute(0);
    selectedTravelMode = requestedMode !== 'drive' && planner?.options.some((option) => option.mode === requestedMode)
      ? requestedMode : 'drive';
    $('tripEyebrow').textContent = navigating ? 'DRIVING MODE' : 'ROUTE READY';
    $('tripTitle').textContent = destinationName || t(language, 'destinationFallback');
    $('navDestinationTitle').textContent = destinationName || t(language, 'destinationFallback');
    $('sheetNextCamera').textContent = routeCameras.length
      ? formatDistance(Math.max(0, routeCameras[0]!.alongMeters), language)
      : '—';
    $('navNextCamera').textContent = $('sheetNextCamera').textContent;
    renderRoutePlanner();
    renderParking();
    if (navigating && selectedTravelMode !== 'drive') document.body.dataset.travelMode = selectedTravelMode;
    if (navigating) updateGuidance();
  } catch (error) {
    if ((error as Error).name === 'AbortError' || signal.aborted) return;
    $('tripEyebrow').textContent = 'ROUTE ERROR';
    $('tripTitle').textContent = t(language, 'routeError');
    toast(`${t(language, 'routeFailed')}: ${String((error as Error).message)}`);
  }
}

function clearDestination() {
  ++parkingSearchSequence;
  parkingDestination = null;
  selectedParking = null;
  parkedAtParking = false;
  parkingPlaces = [];
  parkingLoading = false;
  parkingError = '';
  map.renderParking([], null, selectParking);
  $('parkingSection').hidden = true;
  $('navParkingHint').hidden = true;
  routeAbort?.abort();
  routeAbort = null;
  destination = null;
  destinationName = '';
  route = null;
  drivingAlternatives = [];
  selectedDrivingRoute = 0;
  routePlan = null;
  drivingFromPlanner = false;
  selectedTravelMode = 'drive';
  routeStops.splice(0, routeStops.length);
  routeCameras = [];
  lastTurnKey = '';
  spokenCameras.clear();

  ($('destinationInput') as HTMLInputElement).value = '';
  $('searchResults').hidden = true;
  $('stopEditor').hidden = true;
  $('travelModes').hidden = true;
  $('routeAlternatives').hidden = true;
  $('routeInfoCards').hidden = true;
  $('trafficLegend').hidden = true;
  $('planningActions').hidden = true;
  $('navTrafficCard').hidden = true;
  renderStops();
  $('clearDestinationButton').hidden = true;
  ($('driveButton') as HTMLButtonElement).disabled = true;

  $('tripEyebrow').textContent = 'READY TO GO';
  $('tripTitle').textContent = t(language, 'initialTitle');
  $('tripDistance').textContent = '—';
  $('tripArrival').textContent = '—';
  $('cameraRouteCount').textContent = '—';
  $('sheetNextCamera').textContent = '—';
  $('sheetRouteSteps').textContent = '—';
  $('navDestinationTitle').textContent = '—';
  $('navDistance').textContent = '—';
  $('navArrival').textContent = '—';
  $('navCameraCount').textContent = '—';
  $('navNextCamera').textContent = '—';
  $('navRouteSteps').textContent = '—';
  $('cameraAlert').hidden = true;

  map.clearRoute();
  renderCameras();
  if (current) map.setView(current, 15);
}

function saveCurrentRoute() {
  if (!destination || !destinationName) return;
  const saved = JSON.parse(sessionStorage.getItem('kiwi-saved-routes') || '[]') as unknown[];
  const record = {
    savedAt: new Date().toISOString(),
    destinationName,
    destination,
    mode: selectedTravelMode,
    stops: routeStops.map((stop) => ({ label: stop.label, coordinate: stop.coordinate })),
    distance: selectedTravelMode === 'drive' ? route?.distance ?? null : selectedPlannerOption()?.distanceMeters ?? null,
    duration: selectedTravelMode === 'drive' ? route?.duration ?? null : selectedPlannerOption()?.durationSeconds ?? null
  };
  const next = [record, ...saved.filter((item) => {
    if (!item || typeof item !== 'object') return true;
    return (item as { destinationName?: string }).destinationName !== destinationName;
  })].slice(0, 20);
  sessionStorage.setItem('kiwi-saved-routes', JSON.stringify(next));
  if (isSignedIn()) {
    void rememberRoute({
      destinationName, latitude: destination[1], longitude: destination[0], mode: selectedTravelMode,
      distanceMeters: record.distance, durationSeconds: record.duration
    }).then(() => toast(language === 'zh' ? '路线已保存到账户' : 'Route saved to your account'))
      .catch((error) => toast(String(error)));
  } else toast(language === 'zh' ? '路线仅保留到本次会话' : 'Route saved for this session only');
}

function speak(message: string) {
  if (!voiceEnabled || !('speechSynthesis' in window)) return;
  speechSynthesis.resume();
  const utterance = new SpeechSynthesisUtterance(message);
  utterance.lang = language === 'zh' ? 'zh-CN' : 'en-NZ';
  utterance.rate = language === 'zh' ? .95 : .9;
  utterance.pitch = 1;
  utterance.volume = 1;
  const voices = speechSynthesis.getVoices();
  const preferred = voices.find((voice) =>
    language === 'zh'
      ? voice.lang.toLowerCase().startsWith('zh')
      : voice.lang.toLowerCase().startsWith('en-nz')
  ) || voices.find((voice) => language === 'en' && voice.lang.toLowerCase().startsWith('en'));
  if (preferred) utterance.voice = preferred;
  speechSynthesis.cancel();
  utterance.onerror = () => toast(language === 'zh'
    ? '语音播放失败，请检查静音开关、音量和浏览器语音权限。'
    : 'Voice playback failed. Check silent mode, volume and browser speech support.');
  speechSynthesis.resume();
  speechSynthesis.speak(utterance);
}

function turnText(step: RouteStep) {
  if (step.instruction?.trim()) return step.instruction;
  const modifier = step.modifier || '';
  const road = step.name || (language === 'zh' ? '道路' : 'the road');
  if (step.maneuver === 'arrive') return language === 'zh' ? '到达目的地' : 'Arrive at destination';
  if (step.maneuver === 'roundabout' || step.maneuver === 'rotary') return language === 'zh' ? `进入环岛，驶向 ${road}` : `Enter roundabout toward ${road}`;
  if (modifier.includes('left')) return language === 'zh' ? `左转进入 ${road}` : `Turn left onto ${road}`;
  if (modifier.includes('right')) return language === 'zh' ? `右转进入 ${road}` : `Turn right onto ${road}`;
  if (step.maneuver === 'depart') return language === 'zh' ? `出发，沿 ${road} 行驶` : `Start on ${road}`;
  return language === 'zh' ? `继续沿 ${road} 行驶` : `Continue on ${road}`;
}

function turnArrow(step: RouteStep) {
  const modifier = step.modifier || '';
  if (modifier.includes('left')) return '↰';
  if (modifier.includes('right')) return '↱';
  if (step.maneuver === 'arrive') return '◆';
  if (step.maneuver === 'roundabout') return '↻';
  return '↑';
}

function laneSymbol(indications: string[]) {
  const symbols = indications.map((indication) => {
    if (indication.includes('uturn')) return '↶';
    if (indication.includes('sharp left')) return '↙';
    if (indication.includes('slight left')) return '↖';
    if (indication.includes('left')) return '←';
    if (indication.includes('sharp right')) return '↘';
    if (indication.includes('slight right')) return '↗';
    if (indication.includes('right')) return '→';
    if (indication.includes('straight')) return '↑';
    return '·';
  });
  return [...new Set(symbols)].join('');
}

function renderLaneGuidance(step?: RouteStep) {
  const root = $('laneGuidance');
  const lanes = laneGuidanceEnabled ? step?.lanes : undefined;
  if (!lanes?.length || !lanes.some((lane) => lane.valid)) {
    root.hidden = true;
    root.replaceChildren();
    return;
  }
  root.replaceChildren(...lanes.map((lane) => {
    const item = document.createElement('span');
    item.className = 'lane' + (lane.valid ? ' recommended' : '') + (lane.indications.length > 1 ? ' multi' : '');
    item.textContent = laneSymbol(lane.indications);
    item.setAttribute('aria-label', (lane.valid ? 'Recommended' : 'Lane') + ': ' + (lane.indications.join(', ') || 'unknown'));
    return item;
  }));
  root.hidden = false;
}

function nextStep(progress: number) {
  if (!route) return null;
  const steps = route.steps.map((step) => ({ step, along: nearestOnRoute(step.location, route!.coordinates).alongMeters }));
  return steps.find((item) => item.along > progress + 20 && item.step.maneuver !== 'depart') || steps.at(-1) || null;
}

function updateGuidance() {
  if (!current || !route || !navigating) return;
  const position = nearestOnRoute(current, route.coordinates);
  if (position.offsetMeters > 100 && Date.now() - lastRerouteAt > 20000 && !manualOrigin) {
    lastRerouteAt = Date.now();
    void planRoute();
    return;
  }
  const progress = position.alongMeters;
  const remaining = Math.max(0, route.distance - progress);
  const remainingSeconds = route.duration * remaining / Math.max(route.distance, 1);
  const maneuver = nextStep(progress);
  $('turnArrow').textContent = maneuver ? turnArrow(maneuver.step) : '◆';
  $('turnDistance').textContent = maneuver ? formatDistance(Math.max(0, maneuver.along - progress), language) : '—';
  $('turnInstruction').textContent = maneuver ? turnText(maneuver.step) : t(language, 'arrived');
  renderLaneGuidance(maneuver?.step);
  $('turnEta').textContent = new Date(Date.now() + remainingSeconds * 1000).toLocaleTimeString(language === 'zh' ? 'zh-NZ' : 'en-NZ', { hour: '2-digit', minute: '2-digit' });
  $('turnRemaining').textContent = formatDistance(remaining, language);
  $('tripDistance').textContent = formatDistance(remaining, language);
  $('tripArrival').textContent = $('turnEta').textContent;
  $('navDistance').textContent = $('turnRemaining').textContent;
  $('navArrival').textContent = $('turnEta').textContent;
  if (maneuver) {
    const toTurn = maneuver.along - progress;
    if (following) {
      const zoom = toTurn < 45 ? 19.2 : toTurn < 140 ? 18.4 : 17.2;
      const lookAhead = toTurn < 45 ? 35 : toTurn < 140 ? 60 : 150;
      map.focusNavigation(lookAheadCenter(current, latestHeading, route, lookAhead), zoom);
    }
    const key = `${maneuver.step.location.join(',')}:${toTurn <= 100 ? '100' : '500'}`;
    if (toTurn > 0 && toTurn <= 500 && key !== lastTurnKey) {
      lastTurnKey = key;
      speak(language === 'zh' ? `${formatDistance(toTurn, 'zh')}后，${turnText(maneuver.step)}` : `In ${formatDistance(toTurn, 'en')}, ${turnText(maneuver.step)}`);
    }
  }
  const upcoming = routeCameras.filter((item) => item.confidence === 'high' && item.alongMeters >= progress - 15).sort((a, b) => a.alongMeters - b.alongMeters)[0];
  $('sheetNextCamera').textContent = upcoming
    ? formatDistance(Math.max(0, upcoming.alongMeters - progress), language)
    : '—';
  $('navNextCamera').textContent = $('sheetNextCamera').textContent;
  if (upcoming && upcoming.alongMeters - progress <= 1200) {
    const ahead = Math.max(0, upcoming.alongMeters - progress);
    $('cameraAlert').hidden = false;
    $('alertType').textContent = cameraLabel(upcoming.camera.type, language);
    $('alertRoad').textContent = upcoming.camera.location;
    $('alertDistance').textContent = formatDistance(ahead, language);
    for (const threshold of [800, 300]) {
      const key = `${upcoming.camera.id}:${threshold}`;
      if (ahead <= threshold && ahead > 0 && !spokenCameras.has(key)) {
        spokenCameras.add(key);
        const label = cameraLabel(upcoming.camera.type, language);
        speak(language === 'zh' ? `前方 ${threshold} 米${label}，${upcoming.camera.location}` : `${label} in ${threshold} metres, ${upcoming.camera.location}`);
      }
    }
  } else $('cameraAlert').hidden = true;
  requestAnimationFrame(updateNavigationOverlayLayout);
  if (remaining < 25) stopNavigation(true);
}

async function startNavigation() {
  if (!current) { requestGps(); toast(t(language, 'noGps')); return; }
  if (!route) { toast(t(language, 'routeError')); return; }
  navigating = true;
  following = true;
  requestCompassFromGesture();
  document.body.dataset.travelMode = selectedTravelMode;
  $('followButton').classList.add('active');
  $('tripEyebrow').textContent = selectedTravelMode === 'drive' ? 'DRIVING MODE' : 'GUIDANCE MODE';
  $('driveLabel').textContent = t(language, 'stop');
  $('driveIcon').textContent = '■';
  $('drivingStatus').textContent = t(language, 'drivingStarted');
  setUiMode('navigation');
  $('navDestinationTitle').textContent = destinationName || t(language, 'destinationFallback');
  const lookAhead = lookAheadCenter(current, latestHeading, route);
  map.focusNavigation(lookAhead);
  lastTurnKey = '';
  if (manualOrigin && current) { manualOrigin = null; void planRoute(); }
  speak(
    selectedTravelMode === 'transit'
      ? (language === 'zh' ? '行程开始，请按照换乘信息出行。' : 'Trip started. Follow the transit itinerary.')
      : (language === 'zh' ? '导航开始，请注意安全。' : 'Navigation started. Travel safely.')
  );
  try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch { /* browser may deny wake lock */ }
  updateGuidance();
}

function stopNavigation(arrived = false) {
  if (!navigating) return;
  if (isSignedIn() && destination && route) {
    void rememberRoute({
      destinationName: destinationName || 'Destination', latitude: destination[1], longitude: destination[0],
      mode: selectedTravelMode, distanceMeters: route.distance, durationSeconds: route.duration
    }).catch(() => { /* Ending navigation must work even if account sync fails. */ });
  }
  navigating = false;
  delete document.body.dataset.travelMode;
  renderLaneGuidance();
  $('cameraAlert').hidden = true;
  setUiMode('explore');
  if (route) map.fitRoute(route);
  if (arrived && selectedParking && parkingDestination && selectedTravelMode === 'drive') {
    parkedAtParking = true;
    renderParking();
    $('bottomPanel').classList.remove('sheet-collapsed');
    requestAnimationFrame(() => $('parkingSection').scrollIntoView({ block: 'nearest', behavior: 'smooth' }));
  }
  $('tripEyebrow').textContent = arrived ? (parkedAtParking ? 'PARKING REACHED' : 'ARRIVED') : 'ROUTE READY';
  $('driveLabel').textContent = t(language, 'start');
  $('driveIcon').textContent = '➤';
  $('drivingStatus').textContent = t(language, 'drivingStopped');
  void wakeLock?.release();
  wakeLock = null;
  if (arrived) speak(parkedAtParking
    ? (language === 'zh' ? '已到达停车点。停车后请继续步行到目的地。' : 'You have reached the parking place. Continue on foot to your destination.')
    : (language === 'zh' ? '已到达目的地。' : 'You have arrived.'));
}

function showOverlay(id: string) { $(id).hidden = false; }
function hideOverlay(id: string) { $(id).hidden = true; }

function hidePoiCard() {
  selectedPoi = null;
  $('poiCard').hidden = true;
  document.body.classList.remove('poi-open');
}

function renderPoiAccountState(place: PoiSelection) {
  const stored = savedPlace(place.placeId);
  const signedIn = isSignedIn();
  const favorite = $('poiFavorite') as HTMLButtonElement;
  const note = $('poiNote') as HTMLTextAreaElement;
  const saveNote = $('poiSaveNote') as HTMLButtonElement;
  favorite.textContent = stored?.isFavorite ? '♥' : '♡';
  favorite.classList.toggle('active', stored?.isFavorite === true);
  favorite.disabled = false;
  note.disabled = !signedIn;
  saveNote.disabled = !signedIn;
  note.value = stored?.note || '';
  const review = ownReview(place.placeId);
  const rating = $('poiOwnRating') as HTMLSelectElement;
  const comment = $('poiOwnComment') as HTMLTextAreaElement;
  const saveReview = $('poiSaveReview') as HTMLButtonElement;
  rating.value = String(review?.rating || 5);
  rating.disabled = !signedIn;
  comment.value = review?.comment || '';
  comment.disabled = !signedIn;
  saveReview.disabled = !signedIn;
  $('poiOwnReviewHint').textContent = signedIn
    ? (language === 'zh' ? '仅保存在 Tasman 账户，不会发布到 Google' : 'Private to Tasman; not posted to Google')
    : (language === 'zh' ? '登录后撰写私人评价' : 'Sign in to write a private review');
  $('poiAccountHint').textContent = signedIn
    ? (language === 'zh' ? `同步到 ${currentAccountEmail()}` : `Synced to ${currentAccountEmail()}`)
    : (language === 'zh' ? '登录后同步收藏和备注' : 'Sign in to sync favorites and notes');
}

function showPoiCard(place: PoiSelection) {
  if (uiMode === 'navigation') return;
  selectedPoi = place;
  $('poiTitle').textContent = place.name;
  $('poiType').textContent = place.primaryType || 'GOOGLE PLACE';
  $('poiAddress').textContent = place.address || `${place.coordinate[1].toFixed(5)}, ${place.coordinate[0].toFixed(5)}`;

  const rating = $('poiRating');
  if (place.rating !== null) {
    rating.replaceChildren();
    const stars = document.createElement('span');
    stars.className = 'stars';
    stars.textContent = '★'.repeat(Math.max(1, Math.min(5, Math.round(place.rating))));
    const text = document.createElement('span');
    text.textContent = `${place.rating.toFixed(1)} · ${place.userRatingCount ?? 0} ${language === 'zh' ? '条评分' : 'ratings'}`;
    rating.append(stars, text);
    rating.hidden = false;
  } else rating.hidden = true;

  const summary = $('poiSummary');
  summary.textContent = place.editorialSummary;
  summary.hidden = !place.editorialSummary;

  const photos = $('poiPhotos');
  photos.replaceChildren();
  for (const photo of place.photos) {
    const figure = document.createElement('figure');
    figure.className = 'poi-photo';
    const image = document.createElement('img');
    image.src = photo.url;
    image.alt = photo.attribution ? `${place.name} · ${photo.attribution}` : place.name;
    image.loading = 'lazy';
    figure.append(image);
    if (photo.attribution) {
      const caption = document.createElement('figcaption');
      caption.textContent = `© ${photo.attribution}`;
      figure.append(caption);
    }
    photos.append(figure);
  }
  photos.hidden = place.photos.length === 0;

  const meta = $('poiMeta');
  meta.replaceChildren();
  const addMeta = (value: string) => {
    if (!value) return;
    const chip = document.createElement('span');
    chip.textContent = value;
    meta.append(chip);
  };
  addMeta(place.businessStatus === 'OPERATIONAL' ? (language === 'zh' ? '营业中' : 'Operational') : (place.businessStatus || ''));
  addMeta(place.priceLevel?.replaceAll('_', ' ') || '');
  addMeta(place.phone ? `☎ ${place.phone}` : '');

  const hours = $('poiHours');
  hours.replaceChildren();
  for (const line of place.openingHours) {
    const row = document.createElement('div');
    row.textContent = line;
    hours.append(row);
  }
  hours.hidden = place.openingHours.length === 0;

  const website = $('poiWebsite') as HTMLAnchorElement;
  website.hidden = !place.websiteURI;
  website.href = place.websiteURI || '#';
  const mapsLink = $('poiGoogleMaps') as HTMLAnchorElement;
  mapsLink.hidden = !place.googleMapsURI;
  mapsLink.href = place.googleMapsURI || '#';

  const reviewsRoot = $('poiReviews');
  reviewsRoot.replaceChildren();
  for (const review of place.reviews) {
    const root = document.createElement('article');
    root.className = 'poi-review';
    const head = document.createElement('div');
    head.className = 'poi-review-head';
    if (review.authorPhoto) {
      const avatar = document.createElement('img');
      avatar.src = review.authorPhoto;
      avatar.alt = review.author;
      avatar.loading = 'lazy';
      head.append(avatar);
    }
    const author = document.createElement('strong');
    author.textContent = review.author;
    const score = document.createElement('span');
    score.textContent = `${review.rating ?? '—'} ★ · ${review.relativeTime}`;
    head.append(author, score);
    const copy = document.createElement('p');
    copy.textContent = review.text;
    root.append(head, copy);
    if (review.googleMapsURI) {
      const link = document.createElement('a');
      link.className = 'source-link';
      link.href = review.googleMapsURI;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      link.textContent = language === 'zh' ? '在 Google Maps 查看 ↗' : 'View on Google Maps ↗';
      root.append(link);
    }
    reviewsRoot.append(root);
  }
  $('poiReviewCount').textContent = place.userRatingCount ? String(place.userRatingCount) : '';
  $('poiReviewsSection').hidden = place.reviews.length === 0;

  renderPoiAccountState(place);
  $('poiCard').hidden = false;
  document.body.classList.add('poi-open');
  $('searchResults').hidden = true;
}

async function saveSelectedPlace(nextFavorite?: boolean) {
  if (!selectedPoi) return;
  if (!isSignedIn()) {
    toast(language === 'zh' ? '请先在设置中登录，再同步收藏和备注。' : 'Sign in in Settings to sync favorites and notes.');
    return;
  }
  const stored = savedPlace(selectedPoi.placeId);
  const note = ($('poiNote') as HTMLTextAreaElement).value.trim();
  const isFavorite = nextFavorite ?? stored?.isFavorite ?? false;
  try {
    await savePlace({
      placeId: selectedPoi.placeId,
      name: selectedPoi.name,
      address: selectedPoi.address,
      latitude: selectedPoi.coordinate[1],
      longitude: selectedPoi.coordinate[0],
      isFavorite,
      note
    });
    renderPoiAccountState(selectedPoi);
    renderTripFlags();
    toast(language === 'zh' ? '已同步到账号' : 'Saved to your account');
  } catch (error) {
    toast(String((error as Error).message));
  }
}

function navigateToSelectedPoi() {
  if (!selectedPoi) return;
  setDestinationSelection(selectedPoi.coordinate, selectedPoi.name);
  ($('destinationInput') as HTMLInputElement).value = destinationName;
  $('clearDestinationButton').hidden = false;
  void rememberDestination({
    label: selectedPoi.address ? `${selectedPoi.name}, ${selectedPoi.address}` : selectedPoi.name,
    latitude: selectedPoi.coordinate[1],
    longitude: selectedPoi.coordinate[0]
  });
  hidePoiCard();
  if (manualOrigin || current) void planRoute();
  else {
    requestGps();
    toast(t(language, 'chooseOrigin'));
  }
}

function initBottomSheet() {
  const panel = $('bottomPanel');
  const handle = panel.querySelector<HTMLElement>('.panel-handle');
  if (!handle) return;

  if (window.matchMedia('(max-width: 759px)').matches) {
    panel.classList.add('sheet-collapsed');
  }

  let startY = 0;
  let latestY = 0;

  const finish = () => {
    panel.classList.remove('sheet-dragging');
    const delta = latestY - startY;
    if (Math.abs(delta) < 18) {
      panel.classList.toggle('sheet-collapsed');
    } else if (delta < 0) {
      panel.classList.remove('sheet-collapsed');
    } else {
      panel.classList.add('sheet-collapsed');
    }
    panel.style.transform = '';
  };

  handle.addEventListener('pointerdown', (event) => {
    startY = event.clientY;
    latestY = event.clientY;
    panel.classList.add('sheet-dragging');
    handle.setPointerCapture(event.pointerId);
  });
  handle.addEventListener('pointermove', (event) => {
    if (!panel.classList.contains('sheet-dragging')) return;
    latestY = event.clientY;
    const delta = latestY - startY;
    const base = panel.classList.contains('sheet-collapsed')
      ? Math.max(0, panel.offsetHeight - 108)
      : 0;
    panel.style.transform = `translateY(${Math.max(0, base + delta)}px)`;
  });
  handle.addEventListener('pointerup', finish);
  handle.addEventListener('pointercancel', finish);
}

async function saveSelectedReview() {
  if (!selectedPoi || !isSignedIn()) {
    toast(language === 'zh' ? '请先登录再评价地点。' : 'Sign in to review a place.');
    return;
  }
  try {
    await saveOwnReview({
      placeId: selectedPoi.placeId,
      placeName: selectedPoi.name,
      rating: Number(($('poiOwnRating') as HTMLSelectElement).value),
      comment: ($('poiOwnComment') as HTMLTextAreaElement).value.trim()
    });
    renderPoiAccountState(selectedPoi);
    toast(language === 'zh' ? '私人评价已保存' : 'Private review saved');
  } catch (error) { toast(String((error as Error).message)); }
}

$('originInput').addEventListener('focus', () => { searchTarget = 'origin'; });
$('destinationInput').addEventListener('focus', () => { searchTarget = 'destination'; });
$('stopInput').addEventListener('focus', () => { searchTarget = 'stop'; $('stopEditor').hidden = false; });
for (const [id, target] of [['originInput', 'origin'], ['destinationInput', 'destination'], ['stopInput', 'stop']] as const) {
  $(id).addEventListener('keydown', (event) => { if ((event as KeyboardEvent).key === 'Enter') { (event.target as HTMLInputElement).blur(); void search(target); } });
}
$('searchButton').onclick = () => void search('destination');
$('stopSearchButton').onclick = () => void search('stop');
initAutocomplete({
  origin: $('originInput') as HTMLInputElement,
  destination: $('destinationInput') as HTMLInputElement,
  results: $('searchResults'),
  language: () => language,
  recent: recentDestinations,
  select: (target, place: SuggestedPlace) => {
    const coordinate: Coordinate = [place.longitude, place.latitude];
    if (target === 'origin') {
      manualOrigin = coordinate;
      ($('originInput') as HTMLInputElement).value = place.label.split(',').slice(0, 2).join(',');
    } else {
      setDestinationSelection(coordinate, place.label.split(',').slice(0, 2).join(','));
      ($('destinationInput') as HTMLInputElement).value = destinationName;
      $('clearDestinationButton').hidden = false;
      void rememberDestination({ label: place.label, latitude: place.latitude, longitude: place.longitude });
    }
    if (destination && (manualOrigin || current)) void planRoute();
    else if (destination) toast(t(language, 'chooseOrigin'));
  }
});
$('useGpsButton').onclick = () => {
  manualOrigin = null;
  ($('originInput') as HTMLInputElement).value = '';
  if (!current) { requestGps(); return; }
  if (destination) void planRoute();
};
$('clearDestinationButton').onclick = clearDestination;
$('addStopButton').onclick = () => {
  $('stopEditor').hidden = false;
  ($('stopInput') as HTMLInputElement).focus();
};
$('saveRouteButton').onclick = saveCurrentRoute;
$('travelModes').addEventListener('click', (event) => {
  const button = (event.target as HTMLElement).closest<HTMLButtonElement>('button[data-mode]');
  if (!button || button.disabled) return;
  selectedTravelMode = button.dataset.mode as TravelMode;
  if (selectedTravelMode !== 'drive' && parkingDestination) {
    destination = parkingDestination.coordinate;
    destinationName = parkingDestination.name;
    parkingDestination = null;
    selectedParking = null;
    parkedAtParking = false;
    map.renderParking(parkingPlaces, null, selectParking);
    renderParking();
    void planRoute(selectedTravelMode);
    return;
  }
  if (selectedTravelMode === 'drive') {
    applyDrivingRoute(selectedDrivingRoute);
  } else {
    routeCameras = [];
    map.clearTrafficRoutes();
  }
  renderRoutePlanner();
  renderParking();
});
$('driveButton').onclick = () => {
  if (navigating) stopNavigation();
  else void startNavigation();
};
$('navEndButton').onclick = () => stopNavigation();
$('navDataButton').onclick = () => showOverlay('dataOverlay');
$('poiClose').onclick = hidePoiCard;
$('poiNavigate').onclick = navigateToSelectedPoi;
$('poiFavorite').onclick = () => {
  if (!selectedPoi) return;
  void saveSelectedPlace(!(savedPlace(selectedPoi.placeId)?.isFavorite ?? false));
};
$('poiSaveNote').onclick = () => void saveSelectedPlace();
$('poiSaveReview').onclick = () => void saveSelectedReview();
$('followButton').onclick = () => { requestCompassFromGesture(); following = !following; $('followButton').classList.toggle('active', following); if (following && current) { map.setFollowHeading(deviceHeading ?? latestHeading); const center = navigating && route ? lookAheadCenter(current, latestHeading, route) : current; if (navigating) map.focusNavigation(center); else map.panTo(center); } };
$('recenterButton').onclick = () => {
  requestCompassFromGesture();
  if (!current) { requestGps(); return; }
  following = true;
  $('followButton').classList.add('active');
  const center = navigating && route ? lookAheadCenter(current, latestHeading, route) : current;
  if (navigating) map.focusNavigation(center);
  else map.setView(center, 16);
  map.setFollowHeading(deviceHeading ?? latestHeading);
};
$('navVoiceChip').onclick = () => {
  voiceEnabled = !voiceEnabled;
  ($('voiceToggle') as HTMLInputElement).checked = voiceEnabled;
  renderTripFlags();
  void rememberPreferences(language, voiceEnabled);
};
$('navLanesChip').onclick = () => {
  laneGuidanceEnabled = !laneGuidanceEnabled;
  ($('laneToggle') as HTMLInputElement).checked = laneGuidanceEnabled;
  localStorage.setItem('kiwi-lane-guidance', laneGuidanceEnabled ? 'on' : 'off');
  renderTripFlags();
  updateGuidance();
};
$('navGpsChip').onclick = () => { if (current) ($('recenterButton') as HTMLButtonElement).click(); else requestGps(); };
$('trafficToggle').onclick = () => {
  trafficLayerEnabled = !trafficLayerEnabled;
  map.setTrafficEnabled(trafficLayerEnabled && selectedTravelMode === 'drive');
  $('trafficToggle').classList.toggle('active', trafficLayerEnabled);
  $('trafficToggle').setAttribute('aria-pressed', String(trafficLayerEnabled));
};
for (const [id, degrees] of [['rotateLeft', -45], ['rotateRight', 45]] as const) {
  $(id).onclick = () => {
    if (!map.rotateBy(degrees)) {
      toast(language === 'zh' ? '旋转需要支持 WebGL 的矢量地图。' : 'Rotation needs a WebGL-capable vector map.');
      return;
    }
    following = false;
    $('followButton').classList.remove('active');
  };
}
$('navOverviewChip').onclick = () => {
  if (!route) return;
  following = false;
  $('followButton').classList.remove('active');
  map.fitRoute(route);
};
$('navSheetHandle').onclick = () => {
  const expanded = $('navSecondary').hidden;
  $('navSecondary').hidden = !expanded;
  document.body.classList.toggle('nav-sheet-expanded', expanded);
  $('navSheetHandle').setAttribute('aria-expanded', String(expanded));
  $('navSheetHandle').setAttribute('aria-label', language === 'zh' ? (expanded ? '收起行程详情' : '展开行程详情') : (expanded ? 'Hide trip details' : 'Show trip details'));
  requestAnimationFrame(updateNavigationOverlayLayout);
  if (current && route && navigating && following) requestAnimationFrame(() => map.focusNavigation(lookAheadCenter(current!, latestHeading, route!)));
};
$('settingsButton').onclick = () => showOverlay('settingsOverlay');
$('profileButton').onclick = () => { window.location.href = '/dashboard'; };
$('closeSettings').onclick = () => hideOverlay('settingsOverlay');
$('dataButton').onclick = () => showOverlay('dataOverlay');
$('closeData').onclick = () => hideOverlay('dataOverlay');
for (const id of ['settingsOverlay', 'dataOverlay']) $(id).addEventListener('click', (event) => { if (event.target === $(id)) hideOverlay(id); });
function applyLanguage() {
  applyUiLanguage(language);
  $('profileButton').setAttribute('aria-label', language === 'zh' ? '账户总览' : 'Account dashboard');
  $('profileButton').title = language === 'zh' ? '账户总览' : 'Account dashboard';
  $('poiOwnReviewTitle').textContent = language === 'zh' ? '我的评价' : 'My review';
  $('poiOwnRatingLabel').textContent = language === 'zh' ? '我的评分' : 'My rating';
  $('poiOwnComment').setAttribute('placeholder', language === 'zh' ? '写下自己的私人评价' : 'Write a review for your own records');
  $('poiSaveReview').textContent = language === 'zh' ? '保存我的评价' : 'Save my review';
  $('zhButton').classList.toggle('selected', language === 'zh');
  $('enButton').classList.toggle('selected', language === 'en');
  ($('originInput') as HTMLInputElement).placeholder = currentPlaceLabel ? `${t(language, 'currentPlace')}: ${currentPlaceLabel}` : t(language, 'origin');
  $('driveLabel').textContent = t(language, navigating ? 'stop' : 'start');
  $('drivingStatus').textContent = t(language, navigating ? 'drivingStarted' : 'drivingStopped');
  $('navEndLabel').textContent = t(language, 'stop');
  $('navDestinationLabel').textContent = selectedParking && selectedTravelMode === 'drive'
    ? (language === 'zh' ? '停车点' : 'PARKING STOP')
    : (language === 'zh' ? '目的地' : 'DESTINATION');
  $('navCamerasLabel').textContent = t(language, 'camerasAlong');
  $('navDistanceLabel').textContent = t(language, 'distance');
  $('navArrivalLabel').textContent = t(language, 'arrival');
  $('navSpeedLimitLabel').textContent = language === 'zh' ? '当前限速' : 'Speed limit';
  $('navNextCameraLabel').textContent = language === 'zh' ? '下一摄像头' : 'Next camera';
  $('navRouteStepsLabel').textContent = language === 'zh' ? '路线步骤' : 'Route steps';
  $('navDataButton').textContent = t(language, 'dataDetails');
  $('navBanner').setAttribute('aria-label', language === 'zh' ? '下一步转弯' : 'Next maneuver');
  $('navSheet').setAttribute('aria-label', language === 'zh' ? '导航行程' : 'Navigation trip');
  $('navSheetHandle').setAttribute('aria-label', language === 'zh'
    ? ($('navSecondary').hidden ? '展开行程详情' : '收起行程详情')
    : ($('navSecondary').hidden ? 'Show trip details' : 'Hide trip details'));
  if (route) $('navDestinationTitle').textContent = destinationName || t(language, 'destinationFallback');
  if (!route && !navigating) $('tripTitle').textContent = t(language, 'initialTitle');
  if (cameraResponse) {
    $('dataStatus').textContent = `${cameras.length} ${t(language, 'cameraCount')} · ${cameraResponse.sourceUpdatedAt}${cameraResponse.syncStatus === 'live' ? '' : ` · ${t(language, 'cached')}`}`;
    $('checkedAt').textContent = cameraResponse.checkedAt ? new Date(cameraResponse.checkedAt).toLocaleString(language === 'zh' ? 'zh-NZ' : 'en-NZ') : t(language, 'neverChecked');
    $('syncStatus').textContent = t(language, cameraResponse.syncStatus === 'live' ? 'synced' : cameraResponse.syncStatus === 'stale' ? 'stale' : cameraResponse.syncStatus === 'offline' ? 'offline' : 'seed');
  } else $('dataStatus').textContent = t(language, 'camerasLoading');
  renderCameras();
  renderAccount();
  renderGpsStatus();
  renderSpeedHud();
  renderTripFlags();
  renderParking();
  if (selectedPoi) showPoiCard(selectedPoi);
  if (navigating) updateGuidance();
}
$('zhButton').onclick = () => { language = 'zh'; applyLanguage(); void rememberPreferences(language, voiceEnabled); };
$('enButton').onclick = () => { language = 'en'; applyLanguage(); void rememberPreferences(language, voiceEnabled); };
($('voiceToggle') as HTMLInputElement).checked = voiceEnabled;
$('voiceToggle').addEventListener('change', () => {
  voiceEnabled = ($('voiceToggle') as HTMLInputElement).checked;
  renderTripFlags();
  void rememberPreferences(language, voiceEnabled);
  if (voiceEnabled) speak(language === 'zh' ? '语音提示已开启。' : 'Voice guidance is on.');
});
$('voiceTestButton').onclick = () => speak(language === 'zh' ? '语音测试。前方请注意路况。' : 'Voice test. Watch the road ahead.');
($('laneToggle') as HTMLInputElement).checked = laneGuidanceEnabled;
$('laneToggle').addEventListener('change', () => {
  laneGuidanceEnabled = ($('laneToggle') as HTMLInputElement).checked;
  localStorage.setItem('kiwi-lane-guidance', laneGuidanceEnabled ? 'on' : 'off');
  renderTripFlags();
  if (navigating) updateGuidance(); else renderLaneGuidance();
});
document.addEventListener('visibilitychange', () => { if (!document.hidden && navigating && !wakeLock && 'wakeLock' in navigator) void navigator.wakeLock.request('screen').then((lock) => { wakeLock = lock; }).catch(() => {}); });
$('gpsBadge').onclick = () => { requestCompassFromGesture(); requestGps(); };
window.addEventListener('resize', () => {
  if (!route) return;
  requestAnimationFrame(updateNavigationOverlayLayout);
  if (navigating && current && following) map.focusNavigation(lookAheadCenter(current, latestHeading, route));
  else if (uiMode === 'explore') map.fitRoute(route);
});
setUiMode('explore');
initBottomSheet();
renderSpeedHud();
renderTripFlags();
window.gm_authFailure = () => {
  toast(language === 'zh'
    ? `Google 地图授权失败。请检查网页 API Key 是否允许 ${window.location.origin}/*，以及账单和 API 权限。`
    : `Google Maps authorization failed. Allow ${window.location.origin}/* for the web API key and check billing/API restrictions.`);
};

window.addEventListener('kiwi-account-change', () => {
  renderTripFlags();
  if (selectedPoi) renderPoiAccountState(selectedPoi);
});

async function initializeMap() {
  const config = await api<{
    googleMapsApiKey: string;
    googleMapId: string | null;
  }>('/api/config');

  await map.init({
    apiKey: config.googleMapsApiKey,
    mapId: config.googleMapId || undefined,
    language,
    onDragStart: () => {
      following = false;
      $('followButton').classList.remove('active');
    },
    onMapClick: () => {
      $('searchResults').hidden = true;
      hidePoiCard();
    },
    onPoiSelected: showPoiCard
  });
  map.setTrafficEnabled(trafficLayerEnabled);
  renderParking();
  if (destination && !parkingDestination && !parkingPlaces.length) void loadParking();
}

void initializeMap().catch((error) => {
  toast(`Google Maps: ${String((error as Error).message)}`);
});

void initGps();
void loadCameras();
if (typeof DeviceOrientationEvent !== 'undefined' && !('requestPermission' in DeviceOrientationEvent)) listenToCompass();
window.setInterval(() => void loadCameras(), 15 * 60_000);
localStorage.removeItem('kiwi-language');
localStorage.removeItem('kiwi-voice');
const accountRoot = document.createElement('div');
accountRoot.className = 'account-section';
document.querySelector('#settingsOverlay .modal')?.append(accountRoot);
applyLanguage();
void initAccount(accountRoot, () => language, () => voiceEnabled, (saved: AccountProfile) => {
  language = saved.language;
  voiceEnabled = saved.voiceEnabled;
  ($('voiceToggle') as HTMLInputElement).checked = voiceEnabled;
  applyLanguage();
  renderTripFlags();
  if (selectedPoi) renderPoiAccountState(selectedPoi);
});
