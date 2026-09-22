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
