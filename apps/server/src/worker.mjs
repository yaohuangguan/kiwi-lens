import seed from '../data/cameras.json' with { type: 'json' };
import { fetchNztaCameras, SOURCE_URL } from './sync.mjs';
import { handleAccount } from './auth.mjs';
import { handlePlaces } from './places.mjs';
import { routeOptions } from './routes.mjs';
import { loadRoadEventState } from './road_events.mjs';

const CAMERA_KEY = 'cameras/current';
let lastSearchAt = 0;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*'
    }
  });
}

function seedState() {
  return { ...seed, checkedAt: null, syncStatus: 'seed', syncError: null, change: { added: 0, removed: 0 } };
}

export async function readCameraState(env) {
  const stored = await env.CAMERA_DATA.get(CAMERA_KEY, 'json');
  return stored?.cameras?.length >= 50 ? stored : seedState();
}

export async function syncCameras(env, fetcher = fetch) {
  const previous = await readCameraState(env);
  try {
    const fresh = await fetchNztaCameras(fetcher);
    if (fresh.sourceUpdatedAt < previous.sourceUpdatedAt) throw new Error('NZTA page is older than the stored camera snapshot');
    const oldIds = new Set(previous.cameras.map((camera) => camera.id));
    const newIds = new Set(fresh.cameras.map((camera) => camera.id));
    const next = {
      ...fresh,
      checkedAt: new Date().toISOString(),
      syncStatus: 'live',
      syncError: null,
      change: {
        added: fresh.cameras.filter((camera) => !oldIds.has(camera.id)).length,
        removed: previous.cameras.filter((camera) => !newIds.has(camera.id)).length
      }
    };
    await env.CAMERA_DATA.put(CAMERA_KEY, JSON.stringify(next));
    console.info(`NZTA sync: ${next.cameras.length} cameras, +${next.change.added}/-${next.change.removed}`);
    return next;
  } catch (error) {
    const retained = {
      ...previous,
      checkedAt: new Date().toISOString(),
      syncStatus: 'stale',
      syncError: String(error.message || error)
    };
    await env.CAMERA_DATA.put(CAMERA_KEY, JSON.stringify(retained));
    console.warn(`NZTA sync failed; retained ${retained.cameras.length} validated cameras: ${retained.syncError}`);
    return retained;
  }
}

function validateCoordinatePair(value) {
  const match = /^(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$/.exec(value || '');
  if (!match) return null;
  const longitude = Number(match[1]);
  const latitude = Number(match[2]);
  return longitude > 166 && longitude < 179 && latitude > -48 && latitude < -34 ? [longitude, latitude] : null;
}

async function upstreamJson(url, headers = {}) {
  const response = await fetch(url, { headers, signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error(`Map service HTTP ${response.status}`);
  return response.json();
}

async function handleApi(request, env, ctx) {
  const url = new URL(request.url);
  if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
  if (url.pathname === '/api/config') {
    if (!env.GOOGLE_MAPS_BROWSER_API_KEY) {
      return json({ error: 'Google Maps browser key is not configured' }, 503);
    }
    return json({
      googleMapsApiKey: env.GOOGLE_MAPS_BROWSER_API_KEY,
      googleMapId: env.GOOGLE_MAP_ID || null
    });
  }
  if (url.pathname === '/api/health') {
    const state = await readCameraState(env);
    return json({ ok: true, cameraCount: state.cameras.length, syncStatus: state.syncStatus });
  }
  if (url.pathname === '/api/cameras') {
    const state = await readCameraState(env);
    if (state.syncStatus === 'seed') ctx.waitUntil(syncCameras(env));
    return json({ ...state, source: SOURCE_URL });
  }
  if (url.pathname === '/api/road-events') {
    return json(await loadRoadEventState(env));
  }
  if (url.pathname === '/api/speed-limit') {
    const at = validateCoordinatePair(url.searchParams.get('at'));
    if (!at) return json({ error: 'Valid NZ coordinate required' }, 400);

    const [longitude, latitude] = at;
    const params = new URLSearchParams({
      f: 'json',
      geometry: `${longitude},${latitude}`,
      geometryType: 'esriGeometryPoint',
      inSR: '4326',
      spatialRel: 'esriSpatialRelIntersects',
      outFields: 'speedLimitZoneValue,speedLimitZoneMaxValue,speedLimitZoneName,whenEffective,whenIneffective',
      returnGeometry: 'false'
    });
    const nslrUrl =
      'https://services.arcgis.com/CXBb7LAjgIIdcsPt/arcgis/rest/services/' +
      'SpeedLimitZoneFull__View/FeatureServer/0/query?' +
      params.toString();
    const result = await upstreamJson(nslrUrl, {
      accept: 'application/json',
      'user-agent': 'KiwiLens/0.1 (https://github.com/yaohuangguan/kiwi-lens)'
    });
    const now = Date.now();
    const current = (result.features || [])
      .map((feature) => feature.attributes || {})
      .filter((attributes) => {
        const starts = attributes.whenEffective == null || Number(attributes.whenEffective) <= now;
        const active = attributes.whenIneffective == null || Number(attributes.whenIneffective) > now;
        return starts && active;
      })
      .sort((a, b) => Number(b.whenEffective || 0) - Number(a.whenEffective || 0))[0];

    if (!current) {
      return json({
        speedLimitKph: null,
        source: 'NZTA National Speed Limit Register',
        sourceUrl: 'https://www.nzta.govt.nz/partners/speed-management/national-speed-limit-register'
      });
    }

    const parsed = Number.parseInt(String(current.speedLimitZoneValue || current.speedLimitZoneMaxValue || ''), 10);
    return json({
      speedLimitKph: Number.isFinite(parsed) ? parsed : null,
      zoneName: current.speedLimitZoneName || null,
      source: 'NZTA National Speed Limit Register',
      sourceUrl: 'https://www.nzta.govt.nz/partners/speed-management/national-speed-limit-register'
    });
  }
  if (url.pathname === '/api/route-options') {
    const from = validateCoordinatePair(url.searchParams.get('from'));
    const to = validateCoordinatePair(url.searchParams.get('to'));
    if (!from || !to) return json({ error: 'Valid NZ coordinates required' }, 400);
    const stops = (url.searchParams.get('stops') || '')
      .split(';')
      .filter(Boolean)
      .map((value) => validateCoordinatePair(value))
      .filter(Boolean);
    if (stops.length > 23) return json({ error: 'At most 23 intermediate stops are supported' }, 400);
    return json(await routeOptions(from, to, env, stops));
  }
  if (url.pathname === '/api/search') {
    const query = (url.searchParams.get('q') || '').trim();
    if (query.length < 3 || query.length > 120) return json({ error: 'Search query must be 3–120 characters' }, 400);
    const wait = Math.max(0, 1050 - (Date.now() - lastSearchAt));
    if (wait) await new Promise((resolve) => setTimeout(resolve, wait));
    lastSearchAt = Date.now();
    const language = url.searchParams.get('lang') === 'zh' ? 'zh' : 'en';
    const searchUrl = `https://nominatim.openstreetmap.org/search?format=jsonv2&addressdetails=1&namedetails=1&accept-language=${language}&limit=6&countrycodes=nz&q=${encodeURIComponent(query)}`;
    const results = await upstreamJson(searchUrl, { 'user-agent': 'KiwiLens/0.1 (https://github.com/yaohuangguan/kiwi-lens)', 'referer': 'https://github.com/yaohuangguan/kiwi-lens', accept: 'application/json' });
    return json(results.map((place) => {
      const address = place.address || {};
      const poiClasses = new Set([
        'amenity', 'tourism', 'shop', 'office', 'leisure', 'healthcare',
        'craft', 'historic', 'railway', 'aeroway', 'club', 'sport'
      ]);
      const isPoi = poiClasses.has(place.class);
      const streetAddress = [
        [address.house_number, address.road || address.pedestrian].filter(Boolean).join(' '),
        address.suburb || address.neighbourhood,
        address.city || address.town || address.village,
        address.postcode,
        'New Zealand'
      ].filter(Boolean).filter((item, index, values) => values.indexOf(item) === index).join(', ');
      const fullAddress = place.display_name || streetAddress;
      const name = isPoi
        ? (place.name || place.namedetails?.name || fullAddress)
        : fullAddress;
      return {
        id: place.place_id,
        name,
        address: isPoi ? (streetAddress || fullAddress) : fullAddress,
        label: fullAddress,
        isPoi,
        latitude: Number(place.lat),
        longitude: Number(place.lon)
      };
    }));
  }
  if (url.pathname === '/api/route') {
    const from = validateCoordinatePair(url.searchParams.get('from'));
    const to = validateCoordinatePair(url.searchParams.get('to'));
    if (!from || !to) return json({ error: 'Valid NZ coordinates required' }, 400);
    const stops = (url.searchParams.get('stops') || '')
      .split(';')
      .filter(Boolean)
      .map((value) => validateCoordinatePair(value))
      .filter(Boolean);
    if (stops.length > 23) return json({ error: 'At most 23 intermediate stops are supported' }, 400);
    const points = [from, ...stops, to];
    const routeUrl = `https://routing.openstreetmap.de/routed-car/route/v1/driving/${points.map((point) => point.join(',')).join(';')}?overview=full&geometries=geojson&steps=true`;
    const result = await upstreamJson(routeUrl, { 'user-agent': 'KiwiLens/0.1 (https://github.com/yaohuangguan/kiwi-lens)', referer: 'https://routing.openstreetmap.de/', accept: 'application/json' });
    if (result.code !== 'Ok' || !result.routes?.length) return json({ error: 'No driving route found' }, 422);
    const selected = result.routes[0];
    const steps = selected.legs.flatMap((leg) => leg.steps.map((step) => {
      const laneIntersection = step.intersections?.find((intersection) => Array.isArray(intersection.lanes) && intersection.lanes.length);
      const lanes = laneIntersection?.lanes?.map((lane) => ({
        indications: Array.isArray(lane.indications) ? lane.indications : [],
        valid: lane.valid === true
      }));
      return {
        distance: step.distance,
        duration: step.duration,
        name: step.name || '',
        maneuver: step.maneuver?.type || 'continue',
        modifier: step.maneuver?.modifier || '',
        instruction: [step.maneuver?.type, step.maneuver?.modifier, step.name].filter(Boolean).join(' '),
        location: step.maneuver.location,
        ...(lanes?.length ? { lanes } : {})
      };
    }));
    return json({ coordinates: selected.geometry.coordinates, distance: selected.distance, duration: selected.duration, steps });
  }
  return json({ error: 'Not found' }, 404);
}

export default {
  async fetch(request, env, ctx) {
    const pathname = new URL(request.url).pathname;
    if (!pathname.startsWith('/api/')) return env.ASSETS.fetch(request);
    try {
      const featureResponse = await handleAccount(request, env) || await handlePlaces(request, env);
      if (featureResponse) return featureResponse;
      return await handleApi(request, env, ctx);
    } catch (error) {
      console.error(error);
      return json({ error: String(error.message || error) }, 502);
    }
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(syncCameras(env));
  }
};
