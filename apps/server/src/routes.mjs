const GOOGLE_ROUTES_URL = 'https://routes.googleapis.com/directions/v2:computeRoutes';

function seconds(value) {
  if (typeof value !== 'string' || !value.endsWith('s')) return null;
  const parsed = Number(value.slice(0, -1));
  return Number.isFinite(parsed) ? parsed : null;
}

function waypoint([longitude, latitude]) {
  return { location: { latLng: { latitude, longitude } } };
}

async function googleModeRoutes(from, to, mode, apiKey) {
  const driving = mode === 'DRIVE';
  const body = {
    origin: waypoint(from),
    destination: waypoint(to),
    travelMode: mode,
    computeAlternativeRoutes: driving,
    languageCode: 'en-NZ',
    regionCode: 'NZ',
    units: 'METRIC',
    polylineQuality: 'HIGH_QUALITY',
    ...(driving ? { routingPreference: 'TRAFFIC_AWARE_OPTIMAL' } : {})
  };

  const response = await fetch(GOOGLE_ROUTES_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-goog-api-key': apiKey,
      'x-goog-fieldmask': [
        'routes.duration',
        'routes.staticDuration',
        'routes.distanceMeters',
        'routes.polyline.encodedPolyline',
        'routes.routeLabels',
        'routes.description',
        'routes.routeToken',
        'routes.warnings'
      ].join(',')
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15000)
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error(`Google Routes ${mode} HTTP ${response.status}: ${detail.slice(0, 180)}`);
  }

  const payload = await response.json();
  return (payload.routes || []).slice(0, driving ? 3 : 1).map((route, index) => {
    const durationSeconds = seconds(route.duration);
    const staticDurationSeconds = seconds(route.staticDuration);
    return {
      id: `${mode.toLowerCase()}-${index}`,
      mode: mode.toLowerCase(),
      durationSeconds,
      staticDurationSeconds,
      trafficDelaySeconds: driving && durationSeconds != null && staticDurationSeconds != null
        ? Math.max(0, Math.round(durationSeconds - staticDurationSeconds))
        : null,
      distanceMeters: Number(route.distanceMeters || 0),
      encodedPolyline: route.polyline?.encodedPolyline || null,
      routeToken: route.routeToken || null,
      description: route.description || '',
      labels: Array.isArray(route.routeLabels) ? route.routeLabels : [],
      warnings: Array.isArray(route.warnings) ? route.warnings : [],
      provider: 'google'
    };
  });
}

async function fallbackDrivingRoutes(from, to) {
  const routeUrl =
    `https://routing.openstreetmap.de/routed-car/route/v1/driving/${from.join(',')};${to.join(',')}` +
    '?overview=full&geometries=geojson&steps=false&alternatives=3';
  const response = await fetch(routeUrl, {
    headers: {
      'user-agent': 'KiwiLens/0.1 (https://github.com/yaohuangguan/kiwi-lens)',
      referer: 'https://routing.openstreetmap.de/',
      accept: 'application/json'
    },
    signal: AbortSignal.timeout(15000)
  });
  if (!response.ok) throw new Error(`Fallback route HTTP ${response.status}`);
  const payload = await response.json();
  if (payload.code !== 'Ok') throw new Error('Fallback route unavailable');
  return (payload.routes || []).slice(0, 3).map((route, index) => ({
    id: `drive-${index}`,
    mode: 'drive',
    durationSeconds: Number(route.duration || 0),
    staticDurationSeconds: Number(route.duration || 0),
    trafficDelaySeconds: null,
    distanceMeters: Number(route.distance || 0),
    coordinates: route.geometry?.coordinates || [],
    encodedPolyline: null,
    routeToken: null,
    description: index === 0 ? 'Recommended route' : `Alternative ${index + 1}`,
    labels: [],
    warnings: [],
    provider: 'osm-fallback'
  }));
}

export async function routeOptions(from, to, env) {
  if (env.GOOGLE_ROUTES_API_KEY) {
    const modes = ['DRIVE', 'TRANSIT', 'WALK', 'BICYCLE'];
    const settled = await Promise.allSettled(
      modes.map((mode) => googleModeRoutes(from, to, mode, env.GOOGLE_ROUTES_API_KEY))
    );
    const options = settled.flatMap((result) => result.status === 'fulfilled' ? result.value : []);
    const driving = options.filter((option) => option.mode === 'drive');
    if (driving.length) {
      return {
        provider: 'google',
        trafficAvailable: true,
        options
      };
    }
  }

  const driving = await fallbackDrivingRoutes(from, to);
  return {
    provider: 'osm-fallback',
    trafficAvailable: false,
    options: driving
  };
}
