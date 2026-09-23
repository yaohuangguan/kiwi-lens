export type Coordinate = [longitude: number, latitude: number];

export interface Camera {
  id: string;
  name: string;
  region: string;
  suburb: string;
  location: string;
  type: string;
  latitude: number;
  longitude: number;
  source: string;
  updatedAt: string;
}

export interface RouteLane {
  indications: string[];
  valid: boolean;
}

export interface RouteStep {
  distance: number;
  duration: number;
  name: string;
  instruction: string;
  maneuver: string;
  modifier?: string;
  location: Coordinate;
  lanes?: RouteLane[];
}

export interface Route {
  coordinates: Coordinate[];
  distance: number;
  duration: number;
  steps: RouteStep[];
}

export interface RouteCamera {
  camera: Camera;
  alongMeters: number;
  offsetMeters: number;
  confidence: 'high' | 'medium';
}

const R = 6371008.8;
const rad = (degrees: number) => degrees * Math.PI / 180;
const deg = (radians: number) => radians * 180 / Math.PI;

export function distanceMeters(a: Coordinate, b: Coordinate): number {
  const dLat = rad(b[1] - a[1]);
  const dLon = rad(b[0] - a[0]);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[1])) * Math.cos(rad(b[1])) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

export function bearingDegrees(a: Coordinate, b: Coordinate): number {
  const lon = rad(b[0] - a[0]);
  const y = Math.sin(lon) * Math.cos(rad(b[1]));
  const x = Math.cos(rad(a[1])) * Math.sin(rad(b[1])) - Math.sin(rad(a[1])) * Math.cos(rad(b[1])) * Math.cos(lon);
  return (deg(Math.atan2(y, x)) + 360) % 360;
}

export function angleDifference(a: number, b: number): number {
  return Math.abs(((a - b + 540) % 360) - 180);
}

export function projectToSegment(point: Coordinate, start: Coordinate, end: Coordinate) {
  const latitude = rad((start[1] + end[1]) / 2);
  const metersPerLon = 111320 * Math.cos(latitude);
  const metersPerLat = 110540;
  const x = (point[0] - start[0]) * metersPerLon;
  const y = (point[1] - start[1]) * metersPerLat;
  const dx = (end[0] - start[0]) * metersPerLon;
  const dy = (end[1] - start[1]) * metersPerLat;
  const lengthSquared = dx * dx + dy * dy;
  const fraction = lengthSquared ? Math.max(0, Math.min(1, (x * dx + y * dy) / lengthSquared)) : 0;
  const offsetMeters = Math.hypot(x - fraction * dx, y - fraction * dy);
  return { fraction, offsetMeters, segmentMeters: Math.sqrt(lengthSquared) };
}

export function nearestOnRoute(point: Coordinate, coordinates: Coordinate[]) {
  let best = { alongMeters: 0, offsetMeters: Infinity, segmentIndex: 0, bearing: 0 };
  let cumulative = 0;
  for (let i = 0; i < coordinates.length - 1; i++) {
    const start = coordinates[i];
    const end = coordinates[i + 1];
    if (!start || !end) continue;
    const projection = projectToSegment(point, start, end);
    if (projection.offsetMeters < best.offsetMeters) {
      best = {
        alongMeters: cumulative + projection.fraction * distanceMeters(start, end),
        offsetMeters: projection.offsetMeters,
        segmentIndex: i,
        bearing: bearingDegrees(start, end)
      };
    }
    cumulative += distanceMeters(start, end);
  }
  return best;
}

export function normalizeRoad(value: string): string {
  return value.toLowerCase()
    .replace(/\b(state highway|highway)\s*(\d+)/g, 'sh$2')
    .replace(/\b(road|rd|street|st|avenue|ave|drive|dr|motorway|mw|expressway|lane|ln)\b/g, '')
    .replace(/camera\s*[a-z]\b/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export function roadMatches(cameraLocation: string, roadName: string): boolean {
  const camera = normalizeRoad(cameraLocation);
  const road = normalizeRoad(roadName);
  if (!camera || !road) return false;
  if (camera === road || camera.includes(road) || road.includes(camera)) return true;
  const words = road.split(' ').filter((word) => word.length > 2 || /^sh\d+$/.test(word));
  return words.length > 0 && words.every((word) => camera.split(' ').includes(word));
}

function routeRoadAt(steps: RouteStep[], alongMeters: number): string {
  let distance = 0;
  for (const step of steps) {
    distance += step.distance;
    if (alongMeters <= distance + 120) return step.name;
  }
  return steps.at(-1)?.name ?? '';
}

/** Conservative route corridor. CSV lacks lane and enforcement-direction metadata. */
export function matchCamerasToRoute(cameras: Camera[], route: Route): RouteCamera[] {
  return cameras.flatMap((camera) => {
    const nearest = nearestOnRoute([camera.longitude, camera.latitude], route.coordinates);
    const sameRoad = roadMatches(camera.location, routeRoadAt(route.steps, nearest.alongMeters));
    const threshold = sameRoad ? 75 : 28;
    if (nearest.offsetMeters > threshold) return [];
    // Intersections can sit just off the centreline; require a road-name match there.
    if (camera.type.toLowerCase().includes('red light') && !sameRoad && nearest.offsetMeters > 18) return [];
    return [{ camera, alongMeters: nearest.alongMeters, offsetMeters: nearest.offsetMeters, confidence: sameRoad && nearest.offsetMeters <= 35 ? 'high' as const : 'medium' as const }];
  }).sort((a, b) => a.alongMeters - b.alongMeters);
}

export function formatDistance(meters: number, lang: 'zh' | 'en' = 'zh'): string {
  if (meters >= 1000) return `${(meters / 1000).toFixed(meters < 10000 ? 1 : 0)} km`;
  return `${Math.max(0, Math.round(meters / 10) * 10)} ${lang === 'zh' ? '米' : 'm'}`;
}

export function cameraLabel(type: string, lang: 'zh' | 'en'): string {
  const lower = type.toLowerCase();
  if (lang === 'en') return lower.includes('red light') ? 'red-light camera' : lower.includes('average') ? 'average-speed camera' : 'fixed speed camera';
  return lower.includes('red light') ? '红灯摄像头' : lower.includes('average') ? '区间测速摄像头' : '固定测速摄像头';
}
