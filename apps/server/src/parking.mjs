export const AT_PARKING_SOURCE =
  'https://services2.arcgis.com/JkPEgZJGxhSjYOo0/arcgis/rest/services/ParkingService/FeatureServer/1';

const RADIUS_METERS = 1500;

function distanceMeters([lonA, latA], [lonB, latB]) {
  const radians = Math.PI / 180;
  const dLat = (latB - latA) * radians;
  const dLon = (lonB - lonA) * radians;
  const arc = Math.sin(dLat / 2) ** 2 +
    Math.cos(latA * radians) * Math.cos(latB * radians) * Math.sin(dLon / 2) ** 2;
  return 6371008.8 * 2 * Math.atan2(Math.sqrt(arc), Math.sqrt(1 - arc));
}

function count(value) {
  const number = Number(value);
  return value != null && value !== '' && Number.isInteger(number) && number >= 0 && number <= 10000
    ? number : null;
}

function clearance(value) {
  const number = Number.parseFloat(String(value ?? ''));
  return Number.isFinite(number) && number > 1 && number < 6 ? number : null;
}

export async function nearbyAtParking(center, fetcher = fetch) {
  const query = new URLSearchParams({
    f: 'geojson',
    where: "DATATYPE IN ('Covered Parking','Open Air Parking')",
    geometry: center.join(','),
    geometryType: 'esriGeometryPoint',
    inSR: '4326',
    spatialRel: 'esriSpatialRelIntersects',
    distance: String(RADIUS_METERS),
    units: 'esriSRUnit_Meter',
    outFields: 'OBJECTID,DATATYPE,SHORTDESCRIPTION,LONGDESCRIPTION,STREETNUMBER,STREET,SUBURB,STATUS,TOTALSPACES,MOBILITYSPACES,CLEARANCEMETERS',
    outSR: '4326',
    returnGeometry: 'true',
    resultRecordCount: '100',
  });
  const response = await fetcher(`${AT_PARKING_SOURCE}/query?${query}`, {
    headers: { accept: 'application/geo+json' },
    signal: AbortSignal.timeout(12000)
  });
  if (!response.ok) throw new Error(`AT parking HTTP ${response.status}`);
  const result = await response.json();
  if (!Array.isArray(result.features)) throw new Error('Invalid AT parking response');
  return result.features.flatMap((feature) => {
    const [longitude, latitude] = feature.geometry?.coordinates || [];
    const properties = feature.properties || {};
    if (!Number.isFinite(longitude) || !Number.isFinite(latitude) ||
        !Number.isInteger(properties.OBJECTID) ||
        /closed|inactive|removed/i.test(String(properties.STATUS || ''))) return [];
    const coordinate = [longitude, latitude];
    const distance = distanceMeters(center, coordinate);
    if (distance > RADIUS_METERS) return [];
    const address = [properties.STREETNUMBER, properties.STREET, properties.SUBURB]
      .filter(Boolean).join(' ');
    return [{
      id: `at-${properties.OBJECTID}`,
      source: 'at',
      name: String(properties.SHORTDESCRIPTION || properties.LONGDESCRIPTION || address || 'AT car park'),
      address,
      coordinate,
      distanceMeters: distance,
      googleMapsURI: '',
      totalSpaces: count(properties.TOTALSPACES),
      mobilitySpaces: count(properties.MOBILITYSPACES),
      clearanceMeters: clearance(properties.CLEARANCEMETERS),
    }];
  }).sort((a, b) => a.distanceMeters - b.distanceMeters).slice(0, 8);
}
