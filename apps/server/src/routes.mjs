const GOOGLE_ROUTES_URL = 'https://routes.googleapis.com/directions/v2:computeRoutes';

function seconds(value) {
  if (typeof value !== 'string' || !value.endsWith('s')) return null;
  const parsed = Number(value.slice(0, -1));
  return Number.isFinite(parsed) ? parsed : null;
}

function waypoint([longitude, latitude]) {
  return { location: { latLng: { latitude, longitude } } };
}

function transitSummary(route) {
  const items = [];
  for (const leg of route.legs || []) {
    for (const step of leg.steps || []) {
      const details = step.transitDetails;
      if (!details) continue;
      const line = details.transitLine || {};
      const vehicle = line.vehicle || {};
      const stops = details.stopDetails || {};
      items.push({
        lineName: line.nameShort || line.name || '',
        headsign: details.headsign || '',
        vehicleType: vehicle.type || '',
        vehicleName: vehicle.name?.text || '',
        color: line.color || '',
        textColor: line.textColor || '',
        departureStop: stops.departureStop?.name || '',
        arrivalStop: stops.arrivalStop?.name || '',
        departureTime: stops.departureTime || null,
        arrivalTime: stops.arrivalTime || null,
        stopCount: Number(details.stopCount || 0),
        agencies: (line.agencies || []).map((agency) => agency.name).filter(Boolean)
      });
    }
  }
  return items;
}

function trafficIntervals(route) {
  return (route.travelAdvisory?.speedReadingIntervals || []).map((interval) => ({
    startPolylinePointIndex: Number(interval.startPolylinePointIndex || 0),
    endPolylinePointIndex: Number(interval.endPolylinePointIndex || 0),
    speed: interval.speed === 'TRAFFIC_JAM'
      ? 'trafficJam'
      : interval.speed === 'SLOW'
        ? 'slow'
        : 'normal'
  }));
}

function trafficSummary(intervals) {
  const counts = { normal: 0, slow: 0, trafficJam: 0 };
  for (const interval of intervals) counts[interval.speed] += 1;
  return counts;
}

function routeSteps(route) {
  const result = [];
  for (const leg of route.legs || []) {
    for (const step of leg.steps || []) {
      const instruction = step.navigationInstruction || {};
      const point = step.startLocation?.latLng;
      if (!point) continue;
      const maneuverName = String(instruction.maneuver || '').toLowerCase();
      const modifier = maneuverName.includes('left')
        ? 'left'
        : maneuverName.includes('right')
          ? 'right'
          : maneuverName.includes('uturn')
            ? 'uturn'
            : undefined;
      result.push({
        distance: Number(step.distanceMeters || 0),
        duration: seconds(step.staticDuration) || 0,
        name: '',
        instruction: instruction.instructions || '',
        maneuver: maneuverName.includes('roundabout')
          ? 'roundabout'
          : maneuverName.includes('destination')
            ? 'arrive'
            : maneuverName.includes('depart')
              ? 'depart'
              : 'turn',
        modifier,
        location: [Number(point.longitude), Number(point.latitude)]
      });
    }
  }
  return result;
}

async function googleModeRoutes(from, to, mode, apiKey, stops = []) {
  const driving = mode === 'DRIVE';
  const supportsStops = mode !== 'TRANSIT';
  const body = {
    origin: waypoint(from),
    destination: waypoint(to),
    ...(supportsStops && stops.length
      ? { intermediates: stops.slice(0, 23).map(waypoint) }
      : {}),
    travelMode: mode,
    computeAlternativeRoutes: driving && stops.length === 0,
    languageCode: 'en-NZ',
    regionCode: 'NZ',
    units: 'METRIC',
    polylineQuality: 'HIGH_QUALITY',
    ...(driving ? { routingPreference: 'TRAFFIC_AWARE_OPTIMAL', extraComputations: ['TRAFFIC_ON_POLYLINE'] } : {})
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
        'routes.warnings',
        'routes.travelAdvisory.speedReadingIntervals',
        'routes.legs.steps.distanceMeters',
        'routes.legs.steps.staticDuration',
        'routes.legs.steps.startLocation',
        'routes.legs.steps.navigationInstruction',
        'routes.legs.steps.transitDetails'
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
    const intervals = trafficIntervals(route);
    const traffic = trafficSummary(intervals);
    const warnings = Array.isArray(route.warnings) ? route.warnings : [];
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
      warnings,
      traffic,
      trafficIntervals: intervals,
      steps: routeSteps(route),
      transit: mode === 'TRANSIT' ? transitSummary(route) : [],
      provider: 'google'
    };
  });
}

async function fallbackDrivingRoutes(from, to, stops = []) {
  const points = [from, ...stops.slice(0, 23), to];
  const routeUrl =
    `https://routing.openstreetmap.de/routed-car/route/v1/driving/${points.map((point) => point.join(',')).join(';')}` +
    `?overview=full&geometries=geojson&steps=false&alternatives=${stops.length ? 'false' : '3'}`;
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
    traffic: { normal: 0, slow: 0, trafficJam: 0 },
    trafficIntervals: [],
    steps: [],
    transit: [],
    provider: 'osm-fallback'
  }));
}

export async function routeOptions(from, to, env, stops = []) {
  if (env.GOOGLE_ROUTES_API_KEY) {
    const modes = stops.length ? ['DRIVE', 'WALK', 'BICYCLE'] : ['DRIVE', 'TRANSIT', 'WALK', 'BICYCLE'];
    const settled = await Promise.allSettled(
      modes.map((mode) => googleModeRoutes(from, to, mode, env.GOOGLE_ROUTES_API_KEY, stops))
    );
    const options = settled.flatMap((result) => result.status === 'fulfilled' ? result.value : []);
    const driving = options.filter((option) => option.mode === 'drive');
    if (driving.length) {
      return {
        provider: 'google',
        trafficAvailable: driving.some((option) => option.trafficIntervals.length > 0),
        stopsApplied: stops.length,
        options
      };
    }
  }

  const driving = await fallbackDrivingRoutes(from, to, stops);
  return {
    provider: 'osm-fallback',
    trafficAvailable: false,
    stopsApplied: stops.length,
    options: driving
  };
}
