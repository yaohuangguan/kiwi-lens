import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import './style.css';
import { cameraLabel, distanceMeters, formatDistance, matchCamerasToRoute, nearestOnRoute, type Camera, type Coordinate, type Route, type RouteCamera, type RouteStep } from '@kiwi-lens/core';

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
let manualOrigin: Coordinate | null = null;
let destination: Coordinate | null = null;
let destinationName = '';
let route: Route | null = null;
let navigating = false;
let following = true;
let language: Language = localStorage.getItem('kiwi-language') === 'en' ? 'en' : 'zh';
let voiceEnabled = localStorage.getItem('kiwi-voice') !== 'off';
let searchTarget: 'origin' | 'destination' = 'destination';
let routeAbort: AbortController | null = null;
let lastRerouteAt = 0;
let lastTurnKey = '';
let wakeLock: WakeLockSentinel | null = null;
let toastTimeout = 0;
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
    $('dataStatus').textContent = `${cameras.length} 个 NZTA 固定摄像头 · ${cameraResponse.sourceUpdatedAt}${cameraResponse.syncStatus === 'live' ? '' : ' · 缓存'}`;
    $('sourceDate').textContent = cameraResponse.sourceUpdatedAt;
    $('checkedAt').textContent = cameraResponse.checkedAt ? new Date(cameraResponse.checkedAt).toLocaleString('zh-NZ') : '尚未检查';
    $('syncStatus').textContent = cameraResponse.syncStatus === 'live' ? '已同步' : cameraResponse.syncStatus === 'stale' ? '官方连接失败，使用缓存' : cameraResponse.syncStatus === 'offline' ? '离线缓存' : '初始 CSV';
    if (route) routeCameras = matchCamerasToRoute(cameras, route);
    renderCameras();
  } else $('dataStatus').textContent = '摄像头数据暂不可用';
}

function positionIcon(heading: number | null) {
  return L.divIcon({ className: '', html: `<span class="position-pin">${heading === null ? '' : `<span class="position-heading" style="transform:rotate(${heading}deg)"></span>`}</span>`, iconSize: [23, 23], iconAnchor: [11, 11] });
}

function updatePosition(latitude: number, longitude: number, heading: number | null, accuracy: number) {
  if (!(latitude > -48 && latitude < -34 && longitude > 166 && longitude < 179)) return;
  current = [longitude, latitude];
  $('gpsBadge').classList.remove('error');
  $('gpsBadge').innerHTML = `<i></i>GPS ${Math.round(accuracy)} m`;
  if (!positionMarker) {
    positionMarker = L.marker([latitude, longitude], { icon: positionIcon(heading), zIndexOffset: 600 }).addTo(map);
    if (following && !route) map.setView([latitude, longitude], 15);
  } else {
    positionMarker.setLatLng([latitude, longitude]).setIcon(positionIcon(heading));
    if (following && navigating) map.panTo([latitude, longitude], { animate: true, duration: .5 });
  }
  if (destination && !route && !manualOrigin) void planRoute();
  if (navigating && route) updateGuidance();
}

function startGps() {
  if (!navigator.geolocation) {
    $('gpsBadge').classList.add('error');
    $('gpsBadge').innerHTML = '<i></i>GPS 不可用';
    return;
  }
  navigator.geolocation.watchPosition(
    ({ coords }) => updatePosition(coords.latitude, coords.longitude, Number.isFinite(coords.heading) ? coords.heading : null, coords.accuracy),
    (error) => {
      $('gpsBadge').classList.add('error');
      $('gpsBadge').innerHTML = `<i></i>${error.code === 1 ? '定位未授权' : '定位暂不可用'}`;
      if (error.code === 1) toast('请允许定位，或在起点栏手动搜索地址。');
    },
    { enableHighAccuracy: true, maximumAge: 1000, timeout: 18000 }
  );
}

async function search(target: 'origin' | 'destination') {
  searchTarget = target;
  const input = target === 'origin' ? $('originInput') as HTMLInputElement : $('destinationInput') as HTMLInputElement;
  const query = input.value.trim();
  if (query.length < 3) { toast('请输入至少 3 个字符。'); return; }
  const results = $('searchResults');
  results.hidden = false;
  results.innerHTML = '<div class="search-message">搜索中…</div>';
  try {
    const places = await api<Place[]>(`/api/search?q=${encodeURIComponent(query)}`);
    results.replaceChildren();
    if (!places.length) { results.innerHTML = '<div class="search-message">未找到新西兰地址，请换个关键词。</div>'; return; }
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
        }
        if (destination && (manualOrigin || current)) void planRoute();
        else if (destination) toast('请选择起点，或允许 GPS 定位。');
      };
      results.append(button);
    }
  } catch (error) {
    results.innerHTML = `<div class="search-message">搜索失败：${escapeHtml(String((error as Error).message))}</div>`;
  }
}

async function planRoute() {
  const from = manualOrigin || current;
  if (!from || !destination) return;
  routeAbort?.abort();
  routeAbort = new AbortController();
  $('tripEyebrow').textContent = 'CALCULATING ROUTE';
  $('tripTitle').textContent = '正在计算路线…';
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
    $('tripTitle').textContent = destinationName || '目的地';
    $('tripDistance').textContent = formatDistance(route.distance);
    $('cameraRouteCount').textContent = String(routeCameras.length);
    $('tripArrival').textContent = new Date(Date.now() + route.duration * 1000).toLocaleTimeString('zh-NZ', { hour: '2-digit', minute: '2-digit' });
    ($('driveButton') as HTMLButtonElement).disabled = false;
    if (navigating) updateGuidance();
  } catch (error) {
    if ((error as Error).name === 'AbortError') return;
    $('tripEyebrow').textContent = 'ROUTE ERROR';
    $('tripTitle').textContent = '路线暂不可用';
    toast(`路线计算失败：${String((error as Error).message)}`);
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
  const modifier = (step as RouteStep & { modifier?: string }).modifier || '';
  if (modifier.includes('left')) return '↰';
  if (modifier.includes('right')) return '↱';
  if (step.maneuver === 'arrive') return '◆';
  if (step.maneuver === 'roundabout') return '↻';
  return '↑';
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
  $('turnInstruction').textContent = maneuver ? turnText(maneuver.step) : '到达目的地';
  $('turnEta').textContent = new Date(Date.now() + remainingSeconds * 1000).toLocaleTimeString('zh-NZ', { hour: '2-digit', minute: '2-digit' });
  $('turnRemaining').textContent = formatDistance(remaining, language);
  $('tripDistance').textContent = formatDistance(remaining, language);
  $('tripArrival').textContent = $('turnEta').textContent;
  if (maneuver) {
    const toTurn = maneuver.along - progress;
    const key = `${maneuver.step.location.join(',')}:${toTurn <= 100 ? '100' : '500'}`;
    if (toTurn > 0 && toTurn <= 500 && key !== lastTurnKey) {
      lastTurnKey = key;
      speak(language === 'zh' ? `${formatDistance(toTurn)}后，${turnText(maneuver.step)}` : `In ${formatDistance(toTurn, 'en')}, ${turnText(maneuver.step)}`);
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
  if (!route) return;
  navigating = true;
  following = true;
  $('followButton').classList.add('active');
  $('bottomPanel').classList.add('driving');
  $('tripEyebrow').textContent = 'DRIVING MODE';
  $('driveLabel').textContent = '结束导航';
  $('driveIcon').textContent = '■';
  $('drivingStatus').textContent = '已启动';
  $('searchPanel').hidden = true;
  lastTurnKey = '';
  if (manualOrigin && current) { manualOrigin = null; void planRoute(); }
  try { if ('wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen'); } catch { /* browser may deny wake lock */ }
  speak(language === 'zh' ? '导航开始，请注意安全。' : 'Navigation started. Drive safely.');
  updateGuidance();
}

function stopNavigation(arrived = false) {
  navigating = false;
  $('turnPanel').hidden = true;
  $('cameraAlert').hidden = true;
  $('searchPanel').hidden = false;
  $('bottomPanel').classList.remove('driving');
  $('tripEyebrow').textContent = arrived ? 'ARRIVED' : 'ROUTE READY';
  $('driveLabel').textContent = '开始导航';
  $('driveIcon').textContent = '➤';
  $('drivingStatus').textContent = '未启动';
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
$('useGpsButton').onclick = () => { manualOrigin = null; ($('originInput') as HTMLInputElement).value = ''; if (destination && current) void planRoute(); else toast('等待 GPS 定位。'); };
$('driveButton').onclick = () => navigating ? stopNavigation() : void startNavigation();
$('followButton').onclick = () => { following = !following; $('followButton').classList.toggle('active', following); if (following && current) map.panTo([current[1], current[0]]); };
$('recenterButton').onclick = () => { if (current) { following = true; $('followButton').classList.add('active'); map.setView([current[1], current[0]], 16); } else toast('等待 GPS 定位。'); };
map.on('dragstart', () => { following = false; $('followButton').classList.remove('active'); });
map.on('click', () => { $('searchResults').hidden = true; });
$('settingsButton').onclick = () => showOverlay('settingsOverlay');
$('closeSettings').onclick = () => hideOverlay('settingsOverlay');
$('dataButton').onclick = () => showOverlay('dataOverlay');
$('closeData').onclick = () => hideOverlay('dataOverlay');
for (const id of ['settingsOverlay', 'dataOverlay']) $(id).addEventListener('click', (event) => { if (event.target === $(id)) hideOverlay(id); });
function applyLanguage() { $('zhButton').classList.toggle('selected', language === 'zh'); $('enButton').classList.toggle('selected', language === 'en'); renderCameras(); if (navigating) updateGuidance(); }
$('zhButton').onclick = () => { language = 'zh'; localStorage.setItem('kiwi-language', language); applyLanguage(); };
$('enButton').onclick = () => { language = 'en'; localStorage.setItem('kiwi-language', language); applyLanguage(); };
($('voiceToggle') as HTMLInputElement).checked = voiceEnabled;
$('voiceToggle').addEventListener('change', () => { voiceEnabled = ($('voiceToggle') as HTMLInputElement).checked; localStorage.setItem('kiwi-voice', voiceEnabled ? 'on' : 'off'); });
document.addEventListener('visibilitychange', () => { if (!document.hidden && navigating && !wakeLock && 'wakeLock' in navigator) void navigator.wakeLock.request('screen').then((lock) => { wakeLock = lock; }).catch(() => {}); });
startGps();
void loadCameras();
window.setInterval(() => void loadCameras(), 15 * 60_000);
