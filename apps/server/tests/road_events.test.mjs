import test from 'node:test';
import assert from 'node:assert/strict';

import {
  fetchNztaRoadEvents,
  loadRoadEventState,
  normalizeRoadEvent
} from '../src/road_events.mjs';

const NOW = new Date('2026-09-26T00:00:00Z');

function event(overrides = {}) {
  return {
    id: 42,
    status: 'Active',
    impact: 'Caution',
    eventType: 'Area Warning',
    eventDescription: 'Pavement Repairs',
    eventComments: 'Stop/Go traffic management',
    geometry: 'POINT (174.7633 -36.8485)',
    locationArea: 'SH 1 Auckland',
    startDate: '2026-09-25T00:00:00Z',
    endDate: '2026-09-27T00:00:00Z',
    eventModified: '2026-09-25T23:00:00Z',
    planned: true,
    region: { name: 'Auckland' },
    ...overrides
  };
}

test('normalizes live roadworks and closures into RoadEvent payloads', () => {
  const works = normalizeRoadEvent(event(), NOW);
  assert.equal(works.type, 'roadworks');
  assert.equal(works.severity, 'warning');
  assert.equal(works.source.country, 'NZ');
  assert.equal(works.location.longitude, 174.7633);

  const closure = normalizeRoadEvent(event({
    id: 43,
    impact: 'Road Closed',
    eventDescription: 'Crash',
    planned: false
  }), NOW);
  assert.equal(closure.type, 'roadClosure');
  assert.equal(closure.severity, 'critical');
});

test('drops future, expired and malformed road events', () => {
  assert.equal(normalizeRoadEvent(event({ startDate: '2026-09-27T00:00:00Z' }), NOW), null);
  assert.equal(normalizeRoadEvent(event({ endDate: '2026-09-25T00:00:00Z' }), NOW), null);
  assert.equal(normalizeRoadEvent(event({ geometry: 'POINT (0 0)' }), NOW), null);
});

test('fetches official NZTA response shape and normalizes usable events', async () => {
  const fetcher = async () => new Response(JSON.stringify({
    response: { roadevent: [event(), event({ id: 43, impact: 'Road Closed' })] }
  }), { status: 200, headers: { 'content-type': 'application/json' } });
  const state = await fetchNztaRoadEvents(fetcher, NOW);
  assert.equal(state.syncStatus, 'live');
  assert.equal(state.events.length, 2);
  assert.equal(state.events[1].type, 'roadClosure');
});

test('keeps last road-event snapshot when NZTA refresh fails', async () => {
  let stored = {
    events: [normalizeRoadEvent(event(), NOW)],
    checkedAt: '2026-09-25T23:00:00Z',
    syncStatus: 'live'
  };
  const env = {
    CAMERA_DATA: {
      async get() { return stored; },
      async put(_key, value) { stored = JSON.parse(value); }
    }
  };
  const state = await loadRoadEventState(
    env,
    async () => new Response('upstream failure', { status: 503 }),
    NOW
  );
  assert.equal(state.syncStatus, 'stale');
  assert.equal(state.events.length, 1);
});

test('Worker exposes normalized live NZTA road events at /api/road-events', async () => {
  const { default: worker } = await import('../src/worker.mjs');
  const store = new Map();
  const env = {
    CAMERA_DATA: {
      async get(key) { return store.get(key) ?? null; },
      async put(key, value) { store.set(key, JSON.parse(value)); }
    },
    ASSETS: { fetch: async () => new Response('asset') }
  };
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({
    response: { roadevent: [event(), event({ id: 44, impact: 'Road Closed' })] }
  }), { status: 200, headers: { 'content-type': 'application/json' } });
  try {
    const response = await worker.fetch(
      new Request('https://example.test/api/road-events'),
      env,
      { waitUntil() {} }
    );
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.syncStatus, 'live');
    assert.equal(body.events.length, 2);
    assert.equal(body.events[1].type, 'roadClosure');
  } finally {
    globalThis.fetch = originalFetch;
  }
});
