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
