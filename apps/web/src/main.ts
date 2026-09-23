import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import './style.css';
import { cameraLabel, distanceMeters, formatDistance, matchCamerasToRoute, nearestOnRoute, type Camera, type Coordinate, type Route, type RouteCamera, type RouteStep } from '@kiwi-lens/core';
import './account.css';
import { applyUiLanguage, t } from './i18n';
import { initAccount, recentDestinations, rememberDestination, rememberPreferences, renderAccount, type AccountProfile } from './account';
import { lookAheadCenter } from './navigation-view';
import { initAutocomplete, type SuggestedPlace } from './autocomplete';

type Language = 'zh' | 'en';
type Place = { id: number; label: string; latitude: number; longitude: number };
type CameraResponse = { cameras: Camera[]; sourceUpdatedAt: string; checkedAt: string | null; syncStatus: string; syncError?: string | null; change?: { added: number; removed: number } };
const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const map = L.map('map', { zoomControl: false, preferCanvas: true }).setView([-36.8485, 174.7633], 12);
L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '&copy; OpenStreetMap contributors' }).addTo(map);
const cameraLayer = L.layerGroup().addTo(map);
let positionMarker: L.Marker | null = null;
let destinationMarker: L.Marker | null = null;
let routeOutline: L.Polyline | null = null;
let routeLine: L.Polyline | null = null;
let cameras: Camera[] = [];
let cameraResponse: CameraResponse | null = null;
let routeCameras: RouteCamera[] = [];
let current: Coordinate | null = null;
let currentPlaceLabel = '';
let placeLookupStarted = false;
let latestHeading: number | null = null;
let manualOrigin: Coordinate | null = null;
let destination: Coordinate | null = null;
let destinationName = '';
let route: Route | null = null;
let navigating = false;
let following = true;
let language: Language = 'en';
let voiceEnabled = true;
let laneGuidanceEnabled = localStorage.getItem('kiwi-lane-guidance') !== 'off';
let searchTarget: 'origin' | 'destination' = 'destination';
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
const spokenCameras = new Set<string>();

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

const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL || '').replace(/\/$/, '');

async function api<T>(path: string, signal?: AbortSignal): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, { signal });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error || `HTTP ${response.status}`);
  }
  return response.json() as Promise<T>;
}

function cameraIcon(camera: Camera, onRoute = false) {
  const red = camera.type.toLowerCase().includes('red light');
  return L.divIcon({
    className: '', html: `<span class="camera-pin ${red ? 'red' : ''} ${onRoute ? 'route' : ''}">◉</span>`,
    iconSize: onRoute ? [38, 38] : [30, 30], iconAnchor: onRoute ? [19, 19] : [15, 15]
  });
}

function renderCameras() {
  cameraLayer.clearLayers();
  const onRoute = new Set(routeCameras.map((item) => item.camera.id));
  for (const camera of cameras) {
    const marker = L.marker([camera.latitude, camera.longitude], { icon: cameraIcon(camera, onRoute.has(camera.id)), zIndexOffset: onRoute.has(camera.id) ? 400 : 0 });
    const type = cameraLabel(camera.type, language);
    marker.bindPopup(`<span class="popup-tag ${camera.type.toLowerCase().includes('red light') ? 'red' : ''}">${escapeHtml(type)}</span><div class="popup-title">${escapeHtml(camera.location)}</div><div class="popup-line">${escapeHtml(camera.suburb)} · ${escapeHtml(camera.region)}</div><div class="popup-line">${camera.latitude.toFixed(6)}, ${camera.longitude.toFixed(6)}</div><div class="popup-source">NZTA · ${escapeHtml(camera.updatedAt)}</div>`);
    cameraLayer.addLayer(marker);
  }
  $('cameraRouteCount').textContent = route ? String(routeCameras.length) : '—';
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

function positionIcon(heading: number | null) {
  return L.divIcon({ className: '', html: `<span class="position-pin">${heading === null ? '' : `<span class="position-heading" style="transform:rotate(${heading}deg)"></span>`}</span>`, iconSize: [23, 23], iconAnchor: [11, 11] });
}

function updatePosition(latitude: number, longitude: number, heading: number | null, accuracy: number) {
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
  if (!positionMarker) {
    positionMarker = L.marker([latitude, longitude], { icon: positionIcon(heading), zIndexOffset: 600 }).addTo(map);
    if (following) { const center = navigating && route ? lookAheadCenter(current, heading, route) : current; map.setView([center[1], center[0]], navigating ? 17 : 15); }
  } else {
    positionMarker.setLatLng([latitude, longitude]).setIcon(positionIcon(heading));
    if (following && navigating && route) { const center = lookAheadCenter(current, heading, route); map.panTo([center[1], center[0]], { animate: true, duration: .5 }); }
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
    ({ coords }) => updatePosition(coords.latitude, coords.longitude, Number.isFinite(coords.heading) ? coords.heading : null, coords.accuracy),
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
      updatePosition(coords.latitude, coords.longitude, Number.isFinite(coords.heading) ? coords.heading : null, coords.accuracy);
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

async function search(target: 'origin' | 'destination') {
  searchTarget = target;
  const input = target === 'origin' ? $('originInput') as HTMLInputElement : $('destinationInput') as HTMLInputElement;
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
        } else {
          destination = coordinate;
          destinationName = place.label.split(',').slice(0, 2).join(',');
          ($('destinationInput') as HTMLInputElement).value = destinationName;
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

async function planRoute() {
  const from = manualOrigin || current;
  if (!from || !destination) return;
  routeAbort?.abort();
  routeAbort = new AbortController();
  $('tripEyebrow').textContent = 'CALCULATING ROUTE';
  $('tripTitle').textContent = t(language, 'routeCalculating');
  try {
    const next = await api<Route>(`/api/route?from=${from.join(',')}&to=${destination.join(',')}`, routeAbort.signal);
    if (next.coordinates.length < 2) throw new Error('Route geometry is empty');
    route = next;
    routeCameras = matchCamerasToRoute(cameras, route);
    renderCameras();
    const latlngs = route.coordinates.map(([lon, lat]) => [lat, lon] as L.LatLngTuple);
    routeOutline?.remove(); routeLine?.remove(); destinationMarker?.remove();
    routeOutline = L.polyline(latlngs, { color: '#fff', weight: 12, opacity: .95 }).addTo(map);
    routeLine = L.polyline(latlngs, { color: '#3d8b68', weight: 7, opacity: 1 }).addTo(map);
    destinationMarker = L.marker([destination[1], destination[0]], { icon: L.divIcon({ className: '', html: '<span class="camera-pin route" style="background:#193729">◆</span>', iconSize: [38, 38], iconAnchor: [19, 19] }) }).addTo(map);
    if (!navigating) map.fitBounds(routeLine.getBounds(), { paddingTopLeft: [25, 190], paddingBottomRight: [30, 220], maxZoom: 15 });
    $('tripEyebrow').textContent = navigating ? 'DRIVING MODE' : 'ROUTE READY';
    $('tripTitle').textContent = destinationName || t(language, 'destinationFallback');
    $('tripDistance').textContent = formatDistance(route.distance, language);
    $('cameraRouteCount').textContent = String(routeCameras.length);
    $('tripArrival').textContent = new Date(Date.now() + route.duration * 1000).toLocaleTimeString(language === 'zh' ? 'zh-NZ' : 'en-NZ', { hour: '2-digit', minute: '2-digit' });
    ($('driveButton') as HTMLButtonElement).disabled = false;
    if (navigating) updateGuidance();
  } catch (error) {
    if ((error as Error).name === 'AbortError') return;
    $('tripEyebrow').textContent = 'ROUTE ERROR';
    $('tripTitle').textContent = t(language, 'routeError');
    toast(`${t(language, 'routeFailed')}: ${String((error as Error).message)}`);
  }
}

function speak(message: string) {
  if (!voiceEnabled || !('speechSynthesis' in window)) return;
  const utterance = new SpeechSynthesisUtterance(message);
  utterance.lang = language === 'zh' ? 'zh-CN' : 'en-NZ';
  utterance.rate = language === 'zh' ? 1.02 : .95;
  utterance.volume = 1;
  speechSynthesis.cancel();
  speechSynthesis.speak(utterance);
}

function turnText(step: RouteStep) {
  const modifier = (step as RouteStep & { modifier?: string }).modifier || '';
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
  $('turnPanel').hidden = false;
  $('turnArrow').textContent = maneuver ? turnArrow(maneuver.step) : '◆';
  $('turnDistance').textContent = maneuver ? formatDistance(Math.max(0, maneuver.along - progress), language) : '—';
  $('turnInstruction').textContent = maneuver ? turnText(maneuver.step) : t(language, 'arrived');
  renderLaneGuidance(maneuver?.step);
  $('turnEta').textContent = new Date(Date.now() + remainingSeconds * 1000).toLocaleTimeString(language === 'zh' ? 'zh-NZ' : 'en-NZ', { hour: '2-digit', minute: '2-digit' });
  $('turnRemaining').textContent = formatDistance(remaining, language);
  $('tripDistance').textContent = formatDistance(remaining, language);
  $('tripArrival').textContent = $('turnEta').textContent;
  if (maneuver) {
    const toTurn = maneuver.along - progress;
    const key = `${maneuver.step.location.join(',')}:${toTurn <= 100 ? '100' : '500'}`;
    if (toTurn > 0 && toTurn <= 500 && key !== lastTurnKey) {
      lastTurnKey = key;
      speak(language === 'zh' ? `${formatDistance(toTurn, 'zh')}后，${turnText(maneuver.step)}` : `In ${formatDistance(toTurn, 'en')}, ${turnText(maneuver.step)}`);
    }
  }
  const upcoming = routeCameras.filter((item) => item.confidence === 'high' && item.alongMeters >= progress - 15).sort((a, b) => a.alongMeters - b.alongMeters)[0];
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
  if (remaining < 25) stopNavigation(true);
}

async function startNavigation() {
  if (!current) { requestGps(); toast(t(language, 'noGps')); return; }
  if (!route) { toast(t(language, 'routeError')); return; }
  navigating = true;
  following = true;
  $('followButton').classList.add('active');
  $('bottomPanel').classList.add('driving');
  $('tripEyebrow').textContent = 'DRIVING MODE';
  $('driveLabel').textContent = t(language, 'stop');
  $('driveIcon').textContent = '■';
  $('drivingStatus').textContent = t(language, 'drivingStarted');
  $('searchPanel').hidden = true;
  const lookAhead = lookAheadCenter(current, latestHeading, route);
  map.setView([lookAhead[1], lookAhead[0]], 17, { animate: true });
  lastTurnKey = '';
  if (manualOrigin && current) { manualOrigin = null; void planRoute(); }
  try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch { /* browser may deny wake lock */ }
  speak(language === 'zh' ? '导航开始，请注意安全。' : 'Navigation started. Drive safely.');
  updateGuidance();
}

function stopNavigation(arrived = false) {
  navigating = false;
  $('turnPanel').hidden = true;
  renderLaneGuidance();
  $('cameraAlert').hidden = true;
  $('searchPanel').hidden = false;
  $('bottomPanel').classList.remove('driving');
  $('tripEyebrow').textContent = arrived ? 'ARRIVED' : 'ROUTE READY';
  $('driveLabel').textContent = t(language, 'start');
  $('driveIcon').textContent = '➤';
  $('drivingStatus').textContent = t(language, 'drivingStopped');
  void wakeLock?.release();
  wakeLock = null;
  if (arrived) speak(language === 'zh' ? '已到达目的地。' : 'You have arrived.');
}

function showOverlay(id: string) { $(id).hidden = false; }
function hideOverlay(id: string) { $(id).hidden = true; }

$('originInput').addEventListener('focus', () => { searchTarget = 'origin'; });
$('destinationInput').addEventListener('focus', () => { searchTarget = 'destination'; });
for (const [id, target] of [['originInput', 'origin'], ['destinationInput', 'destination']] as const) {
  $(id).addEventListener('keydown', (event) => { if ((event as KeyboardEvent).key === 'Enter') { (event.target as HTMLInputElement).blur(); void search(target); } });
}
$('searchButton').onclick = () => void search('destination');
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
      destination = coordinate;
      destinationName = place.label.split(',').slice(0, 2).join(',');
      ($('destinationInput') as HTMLInputElement).value = destinationName;
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
$('driveButton').onclick = () => navigating ? stopNavigation() : void startNavigation();
$('followButton').onclick = () => { following = !following; $('followButton').classList.toggle('active', following); if (following && current) { const center = navigating && route ? lookAheadCenter(current, latestHeading, route) : current; map.panTo([center[1], center[0]]); } };
$('recenterButton').onclick = () => {
  if (!current) { requestGps(); return; }
  following = true;
  $('followButton').classList.add('active');
  const center = navigating && route ? lookAheadCenter(current, latestHeading, route) : current;
  map.setView([center[1], center[0]], navigating ? 17 : 16);
};
map.on('dragstart', () => { following = false; $('followButton').classList.remove('active'); });
map.on('click', () => { $('searchResults').hidden = true; });
$('settingsButton').onclick = () => showOverlay('settingsOverlay');
$('closeSettings').onclick = () => hideOverlay('settingsOverlay');
$('dataButton').onclick = () => showOverlay('dataOverlay');
$('closeData').onclick = () => hideOverlay('dataOverlay');
for (const id of ['settingsOverlay', 'dataOverlay']) $(id).addEventListener('click', (event) => { if (event.target === $(id)) hideOverlay(id); });
function applyLanguage() {
  applyUiLanguage(language);
  $('zhButton').classList.toggle('selected', language === 'zh');
  $('enButton').classList.toggle('selected', language === 'en');
  ($('originInput') as HTMLInputElement).placeholder = currentPlaceLabel ? `${t(language, 'currentPlace')}: ${currentPlaceLabel}` : t(language, 'origin');
  $('driveLabel').textContent = t(language, navigating ? 'stop' : 'start');
  $('drivingStatus').textContent = t(language, navigating ? 'drivingStarted' : 'drivingStopped');
  if (!route && !navigating) $('tripTitle').textContent = t(language, 'initialTitle');
  if (cameraResponse) {
    $('dataStatus').textContent = `${cameras.length} ${t(language, 'cameraCount')} · ${cameraResponse.sourceUpdatedAt}${cameraResponse.syncStatus === 'live' ? '' : ` · ${t(language, 'cached')}`}`;
    $('checkedAt').textContent = cameraResponse.checkedAt ? new Date(cameraResponse.checkedAt).toLocaleString(language === 'zh' ? 'zh-NZ' : 'en-NZ') : t(language, 'neverChecked');
    $('syncStatus').textContent = t(language, cameraResponse.syncStatus === 'live' ? 'synced' : cameraResponse.syncStatus === 'stale' ? 'stale' : cameraResponse.syncStatus === 'offline' ? 'offline' : 'seed');
  } else $('dataStatus').textContent = t(language, 'camerasLoading');
  renderCameras();
  renderAccount();
  renderGpsStatus();
  if (navigating) updateGuidance();
}
$('zhButton').onclick = () => { language = 'zh'; applyLanguage(); void rememberPreferences(language, voiceEnabled); };
$('enButton').onclick = () => { language = 'en'; applyLanguage(); void rememberPreferences(language, voiceEnabled); };
($('voiceToggle') as HTMLInputElement).checked = voiceEnabled;
$('voiceToggle').addEventListener('change', () => { voiceEnabled = ($('voiceToggle') as HTMLInputElement).checked; void rememberPreferences(language, voiceEnabled); });
($('laneToggle') as HTMLInputElement).checked = laneGuidanceEnabled;
$('laneToggle').addEventListener('change', () => {
  laneGuidanceEnabled = ($('laneToggle') as HTMLInputElement).checked;
  localStorage.setItem('kiwi-lane-guidance', laneGuidanceEnabled ? 'on' : 'off');
  if (navigating) updateGuidance(); else renderLaneGuidance();
});
document.addEventListener('visibilitychange', () => { if (!document.hidden && navigating && !wakeLock && 'wakeLock' in navigator) void navigator.wakeLock.request('screen').then((lock) => { wakeLock = lock; }).catch(() => {}); });
$('gpsBadge').onclick = () => requestGps();
void initGps();
void loadCameras();
window.setInterval(() => void loadCameras(), 15 * 60_000);
localStorage.removeItem('kiwi-language');
localStorage.removeItem('kiwi-voice');
const accountRoot = document.createElement('div');
accountRoot.className = 'account-section';
document.querySelector('#settingsOverlay .modal')?.append(accountRoot);
applyLanguage();
void initAccount(accountRoot, () => language, () => voiceEnabled, (saved: AccountProfile) => {
  language = saved.language; voiceEnabled = saved.voiceEnabled; ($('voiceToggle') as HTMLInputElement).checked = voiceEnabled; applyLanguage();
});
