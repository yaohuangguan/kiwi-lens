import test from 'node:test';
import assert from 'node:assert/strict';
import { nearbyAtParking } from '../src/parking.mjs';

test('AT parking search keeps public car parks near the destination and labels capacity as static', async () => {
  let requested;
  const fetcher = async (url) => {
    requested = new URL(url);
    return new Response(JSON.stringify({
      features: [
        {
          geometry: { coordinates: [174.766856, -36.848985] },
          properties: {
            OBJECTID: 130, DATATYPE: 'Covered Parking',
            SHORTDESCRIPTION: 'Victoria Street Car Park',
            STREETNUMBER: '30', STREET: 'Kitchener Street', SUBURB: 'CBD',
            STATUS: 'OK', TOTALSPACES: 850, MOBILITYSPACES: 6,
            AVAILABLESPACES: 12, CLEARANCEMETERS: '1.95'
          }
        },
        {
          geometry: { coordinates: [174.763238, -36.850883] },
          properties: { OBJECTID: 131, SHORTDESCRIPTION: 'Wellesley St West', STATUS: 'Closed' }
        },
        {
          geometry: { coordinates: [174.9, -36.9] },
          properties: { OBJECTID: 132, SHORTDESCRIPTION: 'Far away', STATUS: 'OK' }
        }
      ]
    }), { status: 200 });
  };
  const places = await nearbyAtParking([174.7633, -36.8485], fetcher);
  assert.equal(requested.searchParams.get('distance'), '1500');
  assert.match(requested.searchParams.get('where'), /Covered Parking/);
  assert.equal(places.length, 1);
  assert.equal(places[0].id, 'at-130');
  assert.equal(places[0].totalSpaces, 850);
  assert.equal(places[0].mobilitySpaces, 6);
  assert.equal(places[0].clearanceMeters, 1.95);
  assert.equal('availableSpaces' in places[0], false);
  assert.match(places[0].address, /Kitchener Street/);
});

test('parking endpoint returns AT locations and rejects invalid coordinates', async () => {
  const { default: worker } = await import('../src/worker.mjs');
  const invalid = await worker.fetch(
    new Request('https://example.test/api/parking?at=outside'),
    {},
    {}
  );
  assert.equal(invalid.status, 400);

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({
    features: [{
      geometry: { coordinates: [174.766856, -36.848985] },
      properties: { OBJECTID: 130, SHORTDESCRIPTION: 'Victoria Street Car Park', STATUS: 'OK', TOTALSPACES: 850 }
    }]
  }), { status: 200 });
  try {
    const response = await worker.fetch(
      new Request('https://example.test/api/parking?at=174.7633,-36.8485'),
      {},
      {}
    );
    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.source, 'Auckland Transport Open GIS');
    assert.equal(payload.places[0].totalSpaces, 850);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
