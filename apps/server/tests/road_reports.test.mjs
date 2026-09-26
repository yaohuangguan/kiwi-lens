import test from 'node:test';
import assert from 'node:assert/strict';
import { createRoadReport, readRoadReports } from '../src/road_reports.mjs';

function envWithStore() {
  let stored = null;
  return {
    CAMERA_DATA: {
      async get() { return stored; },
      async put(_key, value) { stored = JSON.parse(value); }
    }
  };
}

test('creates and reads a short-lived NZ road report', async () => {
  const env = envWithStore();
  const now = new Date('2026-09-26T02:00:00Z');
  const report = await createRoadReport(env, {
    type: 'roadworks',
    latitude: -36.85,
    longitude: 174.76,
    headingDegrees: 375
  }, { id: 'user-1', displayName: 'Sam' }, now);
  assert.equal(report.type, 'roadworks');
  assert.equal(report.observation, 'observed');
  assert.equal(report.headingDegrees, 15);
  assert.equal(report.metadata.reporterName, 'Sam');
  assert.equal(report.metadata.reporterId, 'user-1');
  assert.equal((await readRoadReports(env, now)).length, 1);
  assert.equal((await readRoadReports(env, new Date('2026-09-26T05:00:00Z'))).length, 0);
});

test('rejects invalid or non-NZ road reports', async () => {
  const env = envWithStore();
  await assert.rejects(
    () => createRoadReport(env, { type: 'incident', latitude: 0, longitude: 0 }),
    /Valid NZ road report/
  );
});
