import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { fetchNztaCameras, SOURCE_URL } from './sync.mjs';

const PORT = Number(process.env.PORT || 8787);
const seedPath = fileURLToPath(new URL('../data/cameras.json', import.meta.url));
const seed = JSON.parse(await readFile(seedPath, 'utf8'));
let cameraState = { ...seed, checkedAt: null, syncStatus: 'seed', syncError: null };
const cache = new Map();
let lastSearchAt = 0;

function json(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
}

function validateCoordinatePair(value) {
  const match = /^(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$/.exec(value || '');
  if (!match) return null;
  const longitude = Number(match[1]);
  const latitude = Number(match[2]);
  return longitude > 166 && longitude < 179 && latitude > -48 && latitude < -34 ? [longitude, latitude] : null;
}

async function cachedFetch(key, url, ttlMs, headers = {}) {
  const current = cache.get(key);
  if (current && Date.now() - current.at < ttlMs) return current.value;
  const response = await fetch(url, { headers, signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error(`Map service HTTP ${response.status}`);
  const value = await response.json();
  cache.set(key, { at: Date.now(), value });
  if (cache.size > 300) cache.delete(cache.keys().next().value);
  return value;
}

async function syncCameras() {
  try {
    const fresh = await fetchNztaCameras();
    const oldIds = new Set(cameraState.cameras.map((camera) => camera.id));
    const newIds = new Set(fresh.cameras.map((camera) => camera.id));
    const added = fresh.cameras.filter((camera) => !oldIds.has(camera.id)).length;
    const removed = cameraState.cameras.filter((camera) => !newIds.has(camera.id)).length;
    cameraState = { ...fresh, checkedAt: new Date().toISOString(), syncStatus: 'live', syncError: null, change: { added, removed } };
    console.info(`NZTA sync: ${fresh.cameras.length} cameras, +${added}/-${removed}, source ${fresh.sourceUpdatedAt}`);
  } catch (error) {
    cameraState = { ...cameraState, checkedAt: new Date().toISOString(), syncStatus: 'stale', syncError: String(error.message || error) };
    console.warn(`NZTA sync failed; retaining last validated data: ${cameraState.syncError}`);
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
  try {
    if (url.pathname === '/api/health') return json(res, 200, { ok: true, cameraCount: cameraState.cameras.length, syncStatus: cameraState.syncStatus });
    if (url.pathname === '/api/cameras') return json(res, 200, { ...cameraState, source: SOURCE_URL });
    if (url.pathname === '/api/search') {
      const query = (url.searchParams.get('q') || '').trim();
      if (query.length < 3 || query.length > 120) return json(res, 400, { error: 'Search query must be 3–120 characters' });
      const key = `search:${query.toLowerCase()}`;
      if (!cache.has(key) || Date.now() - cache.get(key).at >= 10 * 60_000) {
        const wait = Math.max(0, 1050 - (Date.now() - lastSearchAt));
        if (wait) await new Promise((resolve) => setTimeout(resolve, wait));
        lastSearchAt = Date.now();
      }
      const searchUrl = `https://nominatim.openstreetmap.org/search?format=jsonv2&addressdetails=1&limit=6&countrycodes=nz&q=${encodeURIComponent(query)}`;
      const result = await cachedFetch(key, searchUrl, 10 * 60_000, { 'user-agent': 'KiwiLens/0.1 (https://github.com/yaohuangguan/kiwi-lens)', accept: 'application/json' });
      return json(res, 200, result.map((item) => ({ id: item.place_id, label: item.display_name, latitude: Number(item.lat), longitude: Number(item.lon) })));
    }
    if (url.pathname === '/api/route') {
      const from = validateCoordinatePair(url.searchParams.get('from'));
      const to = validateCoordinatePair(url.searchParams.get('to'));
      if (!from || !to) return json(res, 400, { error: 'Valid NZ coordinates required' });
      const key = `route:${from.join(',')}:${to.join(',')}`;
      const osrmUrl = `https://router.project-osrm.org/route/v1/driving/${from.join(',')};${to.join(',')}?overview=full&geometries=geojson&steps=true`;
      const result = await cachedFetch(key, osrmUrl, 5 * 60_000);
      if (result.code !== 'Ok' || !result.routes?.length) return json(res, 422, { error: 'No driving route found' });
      const selected = result.routes[0];
      const steps = selected.legs.flatMap((leg) => leg.steps.map((step) => ({
        distance: step.distance, duration: step.duration, name: step.name || '',
        maneuver: step.maneuver?.type || 'continue', modifier: step.maneuver?.modifier || '',
        instruction: [step.maneuver?.type, step.maneuver?.modifier, step.name].filter(Boolean).join(' '),
        location: step.maneuver.location
      })));
      return json(res, 200, { coordinates: selected.geometry.coordinates, distance: selected.distance, duration: selected.duration, steps });
    }
    return json(res, 404, { error: 'Not found' });
  } catch (error) {
    console.error(error);
    return json(res, 502, { error: String(error.message || error) });
  }
});

server.listen(PORT, () => console.info(`Kiwi Lens API listening on http://localhost:${PORT}`));
syncCameras();
setInterval(syncCameras, 6 * 60 * 60_000).unref();
