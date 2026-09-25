import test from 'node:test';
import assert from 'node:assert/strict';
import worker, { readCameraState, syncCameras } from '../src/worker.mjs';

function fakeEnv(initial = null) {
  let value = initial;
  return {
    CAMERA_DATA: {
      async get() { return value; },
      async put(_key, serialized) { value = JSON.parse(serialized); }
    },
    ASSETS: { fetch: async () => new Response('asset') }
  };
}

test('Worker API serves the full seeded camera list when KV is empty', async () => {
  const env = fakeEnv();
  const state = await readCameraState(env);
  assert.equal(state.cameras.length, 125);
  const response = await worker.fetch(new Request('https://example.test/api/health'), env, { waitUntil() {} });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).cameraCount, 125);
});

test('cross-origin address requests get a readable configuration response', async () => {
  const response = await worker.fetch(new Request('https://kiwi-lens.nzs.workers.dev/api/suggest?q=Queen', {
    headers: { Origin: 'https://preview.example' }
  }), fakeEnv(), { waitUntil() {} });
  assert.equal(response.status, 503);
  assert.equal(response.headers.get('access-control-allow-origin'), '*');
});

test('address suggestions expose a place name and street address', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({
    results: [{
      place_id: 'gallery-1',
      name: 'Auckland Art Gallery Toi o Tāmaki',
      address_line1: 'Wellesley Street East',
      address_line2: 'Auckland Central, Auckland 1010, New Zealand',
      formatted: 'Auckland Art Gallery Toi o Tāmaki, Wellesley Street East, Auckland',
      country_code: 'nz',
      lat: -36.8509,
      lon: 174.7666
    }]
  }), { headers: { 'content-type': 'application/json' } });
  try {
    const env = { ...fakeEnv(), GEOAPIFY_API_KEY: 'test-key' };
    const response = await worker.fetch(
      new Request('https://example.test/api/suggest?q=gallery&near=174.7633,-36.8485'),
      env,
      { waitUntil() {} }
    );
    assert.equal(response.status, 200);
    const [suggestion] = await response.json();
    assert.equal(suggestion.name, 'Auckland Art Gallery Toi o Tāmaki');
    assert.equal(
      suggestion.address,
      'Wellesley Street East, Auckland Central, Auckland 1010, New Zealand'
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('explore returns nearby Google places with Yelp-style metadata', async () => {
  const originalFetch = globalThis.fetch;
  let requestBody = null;
  globalThis.fetch = async (_url, options = {}) => {
    requestBody = JSON.parse(options.body);
    return new Response(JSON.stringify({
      places: [{
        id: 'ChIJexplore1',
        displayName: { text: 'Auckland Art Gallery' },
        formattedAddress: 'Wellesley Street East, Auckland 1010, New Zealand',
        primaryTypeDisplayName: { text: 'Art gallery' },
        rating: 4.7,
        userRatingCount: 4200,
        priceLevel: 'PRICE_LEVEL_FREE',
        currentOpeningHours: { openNow: true },
        location: { latitude: -36.8509, longitude: 174.7666 },
        photos: [{ name: 'places/example/photos/photo-1' }]
      }]
    }), { headers: { 'content-type': 'application/json' } });
  };
  try {
    const env = { ...fakeEnv(), GOOGLE_ROUTES_API_KEY: 'test-key' };
    const response = await worker.fetch(
      new Request('https://example.test/api/explore?at=174.7633,-36.8485&category=activities'),
      env,
      { waitUntil() {} }
    );
    assert.equal(response.status, 200);
    assert.equal(requestBody.rankPreference, 'POPULARITY');
    assert.ok(requestBody.includedTypes.includes('museum'));
    const [place] = await response.json();
    assert.equal(place.name, 'Auckland Art Gallery');
    assert.equal(place.rating, 4.7);
    assert.equal(place.openNow, true);
    assert.equal(place.photoName, 'places/example/photos/photo-1');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('failed scheduled sync keeps validated cameras in KV', async () => {
  const env = fakeEnv();
  const state = await syncCameras(env, async () => new Response('<html>challenge</html>'));
  assert.equal(state.syncStatus, 'stale');
  assert.equal(state.cameras.length, 125);
  assert.equal((await readCameraState(env)).cameras.length, 125);
});

test('Worker rejects malformed route coordinates before upstream calls', async () => {
  const response = await worker.fetch(new Request('https://example.test/api/route?from=0,0&to=1,1'), fakeEnv(), { waitUntil() {} });
  assert.equal(response.status, 400);
});

test('speed limit API selects the currently effective NZTA record', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({
    features: [
      { attributes: {
        speedLimitZoneValue: '30',
        speedLimitZoneMaxValue: '30 km/h',
        speedLimitZoneName: 'OLD CBD',
        whenEffective: 0,
        whenIneffective: Date.now() - 1000
      } },
      { attributes: {
        speedLimitZoneValue: '50',
        speedLimitZoneMaxValue: '50 km/h',
        speedLimitZoneName: 'CURRENT CBD',
        whenEffective: Date.now() - 5000,
        whenIneffective: null
      } }
    ]
  }), { headers: { 'content-type': 'application/json' } });
  try {
    const response = await worker.fetch(
      new Request('https://example.test/api/speed-limit?at=174.7633,-36.8485'),
      fakeEnv(),
      { waitUntil() {} }
    );
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.speedLimitKph, 50);
    assert.equal(body.zoneName, 'CURRENT CBD');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('route API preserves OSRM lane guidance for turn steps', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({
    code: 'Ok',
    routes: [{
      distance: 1200,
      duration: 120,
      geometry: { coordinates: [[174.76, -36.85], [174.77, -36.86]] },
      legs: [{ steps: [{
        distance: 300,
        duration: 30,
        name: 'Queen Street',
        maneuver: { type: 'turn', modifier: 'right', location: [174.77, -36.86] },
        intersections: [{ lanes: [
          { indications: ['straight'], valid: false },
          { indications: ['straight', 'right'], valid: true }
        ] }]
      }] }]
    }]
  }), { headers: { 'content-type': 'application/json' } });
  try {
    const response = await worker.fetch(new Request(
      'https://example.test/api/route?from=174.76,-36.85&to=174.77,-36.86'
    ), fakeEnv(), { waitUntil() {} });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.deepEqual(body.steps[0].lanes, [
      { indications: ['straight'], valid: false },
      { indications: ['straight', 'right'], valid: true }
    ]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
