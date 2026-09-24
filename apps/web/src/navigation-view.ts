import { nearestOnRoute, type Coordinate, type Route } from '@kiwi-lens/core';

const EARTH_RADIUS_METRES = 6_371_008.8;

/** Keeps the vehicle below the screen centre so more of the upcoming road is visible. */
export function lookAheadCenter(position: Coordinate, gpsHeading: number | null, route: Route, aheadMetres?: number): Coordinate {
  const projection = nearestOnRoute(position, route.coordinates);
  const heading = gpsHeading !== null && Number.isFinite(gpsHeading) ? gpsHeading : projection.bearing;
  const metres = aheadMetres ?? (projection.offsetMeters < 100 ? 170 : 100);
  const bearing = heading * Math.PI / 180;
  const latitude = position[1] * Math.PI / 180;
  const longitude = position[0] * Math.PI / 180;
  const distance = metres / EARTH_RADIUS_METRES;
  const nextLatitude = Math.asin(Math.sin(latitude) * Math.cos(distance) + Math.cos(latitude) * Math.sin(distance) * Math.cos(bearing));
  const nextLongitude = longitude + Math.atan2(Math.sin(bearing) * Math.sin(distance) * Math.cos(latitude), Math.cos(distance) - Math.sin(latitude) * Math.sin(nextLatitude));
  return [nextLongitude * 180 / Math.PI, nextLatitude * 180 / Math.PI];
}
