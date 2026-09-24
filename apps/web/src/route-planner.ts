import type { Coordinate, Route } from '@kiwi-lens/core';

export type TravelMode = 'drive' | 'transit' | 'walk' | 'bicycle';

export type TransitLeg = {
  lineName: string;
  headsign: string;
  vehicleType: string;
  vehicleName: string;
  departureStop: string;
  arrivalStop: string;
  departureTime: string | null;
  arrivalTime: string | null;
  stopCount: number;
  agencies: string[];
};

export type TrafficSummary = {
  normal: number;
  slow: number;
  trafficJam: number;
};

export type RouteOption = {
  id: string;
  mode: TravelMode;
  durationSeconds: number;
  staticDurationSeconds: number | null;
  trafficDelaySeconds: number | null;
  distanceMeters: number;
  encodedPolyline: string | null;
  coordinates?: Coordinate[];
  routeToken: string | null;
  description: string;
  labels: string[];
  warnings: string[];
  traffic: TrafficSummary;
  transit: TransitLeg[];
  provider: string;
};

export type RoutePlan = {
  provider: string;
  trafficAvailable: boolean;
  stopsApplied: number;
  options: RouteOption[];
};

export async function fetchRoutePlan(
  baseUrl: string,
  from: Coordinate,
  to: Coordinate,
  stops: Coordinate[],
  signal?: AbortSignal
): Promise<RoutePlan> {
  const query = new URLSearchParams({
    from: from.join(','),
    to: to.join(',')
  });
  if (stops.length) query.set('stops', stops.map((stop) => stop.join(',')).join(';'));
  const response = await fetch(`${baseUrl}/api/route-options?${query.toString()}`, { signal });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error || `HTTP ${response.status}`);
  }
  return response.json() as Promise<RoutePlan>;
}

export function decodePolyline(encoded: string): Coordinate[] {
  if (!encoded) return [];
  const points: Coordinate[] = [];
  let index = 0;
  let latitude = 0;
  let longitude = 0;
  while (index < encoded.length) {
    let shift = 0;
    let result = 0;
    let byte = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    latitude += (result & 1) ? ~(result >> 1) : result >> 1;

    shift = 0;
    result = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    longitude += (result & 1) ? ~(result >> 1) : result >> 1;
    points.push([longitude / 1e5, latitude / 1e5]);
  }
  return points;
}

export function routeFromOption(option: RouteOption): Route {
  const coordinates = option.coordinates?.length
    ? option.coordinates
    : decodePolyline(option.encodedPolyline || '');
  return {
    coordinates,
    distance: option.distanceMeters,
    duration: option.durationSeconds,
    steps: []
  };
}

export function formatModeDuration(seconds: number | null | undefined) {
  if (!Number.isFinite(seconds) || !seconds) return '—';
  const minutes = Math.max(1, Math.round(seconds / 60));
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  return remainder ? `${hours} h ${remainder} min` : `${hours} h`;
}
