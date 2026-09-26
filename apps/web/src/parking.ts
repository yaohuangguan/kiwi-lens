import type { Coordinate } from '@kiwi-lens/core';

export type ParkingPlace = {
  id: string;
  source: 'at' | 'google';
  name: string;
  address: string;
  coordinate: Coordinate;
  distanceMeters: number;
  googleMapsURI: string;
  totalSpaces: number | null;
  mobilitySpaces: number | null;
  clearanceMeters: number | null;
};
