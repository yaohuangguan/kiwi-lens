import test from 'node:test';
import assert from 'node:assert/strict';
import seed from '../data/cameras.json' with { type: 'json' };
import { syncCameras } from '../src/worker.mjs';

function fakeEnv() {
  let value = null;
  return {
    CAMERA_DATA: {
      async get() { return value; },
      async put(_key, serialized) { value = JSON.parse(serialized); }
    }
  };
}

function nztaHtml(date, cameras) {
  const rows = cameras.map((camera) => `<tr><td>${camera.suburb}</td><td>${camera.location}</td><td>${camera.type}</td><td>${camera.latitude}</td><td>${camera.longitude}</td></tr>`).join('');
  return `<main><p>Last update: ${date}</p><h3>Northland</h3><table>${rows}</table></main>`;
}

test('successful sync records added and removed cameras while retaining a complete snapshot', async () => {
  const env = fakeEnv();
  const replacement = { suburb: 'Testville', location: 'Test Road', type: 'Spot speed', latitude: -36.85, longitude: 174.76 };
  const html = nztaHtml('27 August 2026', [...seed.cameras.slice(1), replacement]);
  const state = await syncCameras(env, async () => new Response(html));
  assert.equal(state.syncStatus, 'live');
  assert.equal(state.sourceUpdatedAt, '2026-08-27');
  assert.equal(state.cameras.length, 125);
  assert.deepEqual(state.change, { added: 1, removed: 1 });
});

test('older NZTA snapshots cannot replace a newer KV snapshot', async () => {
  const env = fakeEnv();
  const newerHtml = nztaHtml('27 August 2026', seed.cameras);
  const newer = await syncCameras(env, async () => new Response(newerHtml));
  const olderHtml = nztaHtml('26 August 2026', seed.cameras.slice(1));
  const retained = await syncCameras(env, async () => new Response(olderHtml));
  assert.equal(retained.syncStatus, 'stale');
  assert.equal(retained.sourceUpdatedAt, newer.sourceUpdatedAt);
  assert.equal(retained.cameras.length, newer.cameras.length);
});
