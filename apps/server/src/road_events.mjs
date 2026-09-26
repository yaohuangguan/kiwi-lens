// NZTA Traffic and Travel v4 stays inside this adapter.
export const ROAD_EVENTS_SOURCE = 'https://trafficnz.info/service/traffic/rest/4/events/all/10';
export const ROAD_EVENTS_SOURCE_PAGE = 'https://www.journeys.nzta.govt.nz/highway-conditions';
const CACHE_KEY = 'road-events/current';
const FRESH_MS = 5 * 60 * 1000;
const NZ_BOUNDS = { minLon: 166, maxLon: 179, minLat: -48, maxLat: -34 };

function text(value, limit = 400) {
  return typeof value === 'string' ? value.trim().slice(0, limit) : '';
}

function geometryPosition(geometry) {
  if (typeof geometry !== 'string' || geometry.length > 100000) return null;
  const pairs = [...geometry.matchAll(/(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)/g)];
  if (!pairs.length || pairs.length > 5000) return null;
  const middle = pairs[Math.floor(pairs.length / 2)];
  const longitude = Number(middle[1]);
  const latitude = Number(middle[2]);
  if (
    longitude <= NZ_BOUNDS.minLon || longitude >= NZ_BOUNDS.maxLon ||
    latitude <= NZ_BOUNDS.minLat || latitude >= NZ_BOUNDS.maxLat
  ) return null;
  return { latitude, longitude };
}

function eventType(event) {
  const impact = text(event.impact).toLowerCase();
  const category = text(event.eventType).toLowerCase();
  const description = text(event.eventDescription).toLowerCase();
  const comments = text(event.eventComments).toLowerCase();
  const combined = `${category} ${description} ${comments}`;
  if (impact === 'road closed' || /road closure|closed to all traffic/.test(combined)) {
    return 'roadClosure';
  }
  if (/flood/.test(combined)) return 'flooding';
  if (/\bslip\b|landslide/.test(combined)) return 'slip';
  if (/road work|roadwork|road works|road construction|maintenance|pavement repair|resurfacing/.test(combined)) {
    return 'roadworks';
  }
  return 'incident';
}

function severity(event, type) {
  const impact = text(event.impact).toLowerCase();
  if (type === 'roadClosure') return 'critical';
  if (type === 'flooding' || type === 'slip') return 'warning';
  if (/delay|caution|lane closed|stop\/go/.test(impact)) return 'warning';
  return 'advisory';
}

export function normalizeRoadEvent(event, now = new Date()) {
  if (!event || event.status !== 'Active' || event.id == null) return null;
  const location = geometryPosition(event.geometry);
  if (!location) return null;
  const from = Date.parse(event.startDate || '');
  const until = Date.parse(event.endDate || '');
  const time = now.getTime();
  if (Number.isFinite(from) && from > time) return null;
  if (Number.isFinite(until) && until <= time) return null;

  const type = eventType(event);
  const sourceId = String(event.id);
  return {
    id: `nzta:event:${sourceId}`,
    type,
    location,
    roadName: text(event.locationArea, 160) || text(event.journey?.name, 80) || null,
    severity: severity(event, type),
    confidence: event.geometry.startsWith('POINT') ? 0.95 : 0.75,
    observation: 'official',
    validFrom: Number.isFinite(from) ? new Date(from).toISOString() : null,
    validUntil: Number.isFinite(until) ? new Date(until).toISOString() : null,
    source: {
      provider: 'NZTA Traffic and Travel',
      country: 'NZ',
      region: text(event.region?.name, 80) || null,
      sourceId,
      updatedAt: event.eventModified || event.eventCreated || null
    },
    metadata: {
      description: text(event.eventDescription, 160),
      comments: text(event.eventComments, 400),
      impact: text(event.impact, 80),
      planned: event.planned === true,
      eventType: text(event.eventType, 80),
      alternativeRoute: text(event.alternativeRoute, 240),
      expectedResolution: text(event.expectedResolution, 120),
      geometryType: text(event.geometry, 24).split(' ')[0] || null
    }
  };
}

export async function fetchNztaRoadEvents(fetcher = fetch, now = new Date()) {
  const response = await fetcher(ROAD_EVENTS_SOURCE, {
    headers: {
      accept: 'application/json',
      'user-agent': 'Tasman/0.1 (https://github.com/yaohuangguan/kiwi-lens)'
    },
    signal: AbortSignal.timeout(15000)
  });
  if (!response.ok) throw new Error(`NZTA road events HTTP ${response.status}`);
  const body = await response.json();
  const raw = body?.response?.roadevent;
  if (!Array.isArray(raw)) throw new Error('NZTA road events payload is invalid');
  const events = raw.map((event) => normalizeRoadEvent(event, now)).filter(Boolean);
  if (!events.length) throw new Error('NZTA road events payload contained no active usable events');
  return {
    events,
    source: ROAD_EVENTS_SOURCE_PAGE,
    checkedAt: now.toISOString(),
    syncStatus: 'live',
    syncError: null
  };
}

export async function readRoadEventState(env) {
  return await env.CAMERA_DATA.get(CACHE_KEY, 'json');
}

export async function loadRoadEventState(env, fetcher = fetch, now = new Date()) {
  const stored = await readRoadEventState(env);
  const checked = Date.parse(stored?.checkedAt || '');
  const fresh = Number.isFinite(checked) && now.getTime() - checked < FRESH_MS;
  if (fresh && Array.isArray(stored.events)) return stored;

  try {
    const live = await fetchNztaRoadEvents(fetcher, now);
    await env.CAMERA_DATA.put(CACHE_KEY, JSON.stringify(live));
    return live;
  } catch (error) {
    if (Array.isArray(stored?.events) && stored.events.length) {
      const stale = {
        ...stored,
        checkedAt: now.toISOString(),
        syncStatus: 'stale',
        syncError: String(error.message || error)
      };
      await env.CAMERA_DATA.put(CACHE_KEY, JSON.stringify(stale));
      return stale;
    }
    throw error;
  }
}
