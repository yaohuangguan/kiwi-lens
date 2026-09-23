import { importLibrary } from '@googlemaps/js-api-loader';
import { distanceMeters, type Coordinate, type Route, type RouteStep } from '@kiwi-lens/core';

function maneuverParts(raw?: string) {
  const value = (raw || '').toLowerCase();
  if (value.includes('depart')) return { maneuver: 'depart', modifier: '' };
  if (value.includes('roundabout')) {
    return {
      maneuver: 'roundabout',
      modifier: value.includes('left') ? 'left' : value.includes('right') ? 'right' : ''
    };
  }
  if (value.includes('destination') || value.includes('arrive')) return { maneuver: 'arrive', modifier: '' };
  if (value.includes('left')) return { maneuver: 'turn', modifier: value.includes('slight') ? 'slight left' : value.includes('sharp') ? 'sharp left' : 'left' };
  if (value.includes('right')) return { maneuver: 'turn', modifier: value.includes('slight') ? 'slight right' : value.includes('sharp') ? 'sharp right' : 'right' };
  return { maneuver: value.includes('straight') ? 'continue' : 'turn', modifier: '' };
}

function coordinateFromDirectional(location?: google.maps.routes.DirectionalLocation | null): Coordinate | null {
  if (!location) return null;
  return [location.lng, location.lat];
}

function nearestLaneStep(step: RouteStep, laneRoute?: Route) {
  if (!laneRoute?.steps.length) return undefined;
  let best: { step: RouteStep; distance: number } | undefined;
  for (const candidate of laneRoute.steps) {
    if (!candidate.lanes?.length) continue;
    const distance = distanceMeters(step.location, candidate.location);
    if (distance > 100) continue;
    if (!best || distance < best.distance) best = { step: candidate, distance };
  }
  return best?.step;
}

export function enrichRouteLanes(route: Route, laneRoute?: Route): Route {
  if (!laneRoute) return route;
  return {
    ...route,
    steps: route.steps.map((step) => {
      const laneStep = nearestLaneStep(step, laneRoute);
      return laneStep?.lanes?.length ? { ...step, lanes: laneStep.lanes } : step;
    })
  };
}

export async function computeGoogleRoute(
  from: Coordinate,
  to: Coordinate,
  language: 'zh' | 'en'
): Promise<Route> {
  const { Route: GoogleRoute } = await importLibrary('routes');

  const { routes } = await GoogleRoute.computeRoutes({
    origin: { lat: from[1], lng: from[0] },
    destination: { lat: to[1], lng: to[0] },
    travelMode: 'DRIVING',
    routingPreference: 'TRAFFIC_AWARE',
    polylineQuality: 'HIGH_QUALITY',
    language: language === 'zh' ? 'zh-CN' : 'en-NZ',
    region: 'NZ',
    fields: [
      'path',
      'distanceMeters',
      'durationMillis',
      'viewport',
      'legs.steps.distanceMeters',
      'legs.steps.staticDurationMillis',
      'legs.steps.instructions',
      'legs.steps.maneuver',
      'legs.steps.startLocation'
    ]
  });

  const selected = routes?.[0];
  if (!selected?.path?.length) throw new Error('Google route geometry is empty');

  const coordinates: Coordinate[] = selected.path.map((point) => [point.lng, point.lat]);
  const steps: RouteStep[] = [];

  for (const leg of selected.legs || []) {
    for (const step of leg.steps || []) {
      const location = coordinateFromDirectional(step.startLocation) || coordinates[0]!;
      const parts = maneuverParts(step.maneuver ?? undefined);
      const routeStep: RouteStep = {
        distance: step.distanceMeters || 0,
        duration: (step.staticDurationMillis || 0) / 1000,
        name: step.instructions || '',
        instruction: step.instructions || '',
        maneuver: parts.maneuver,
        modifier: parts.modifier,
        location
      };
      steps.push(routeStep);
    }
  }

  return {
    coordinates,
    distance: selected.distanceMeters || 0,
    duration: (selected.durationMillis || 0) / 1000,
    steps
  };
}
