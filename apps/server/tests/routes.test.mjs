import test from 'node:test';
import assert from 'node:assert/strict';
import { routeOptions } from '../src/routes.mjs';

test('Google driving alternatives request traffic on the polyline', async () => {
  const originalFetch = globalThis.fetch;
  const requests = [];
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body);
    requests.push(body);
    return new Response(JSON.stringify({ routes: body.travelMode === 'DRIVE' ? [{
      duration: '100s',
      staticDuration: '90s',
      distanceMeters: 1000,
      polyline: { encodedPolyline: 'abc' },
      travelAdvisory: { speedReadingIntervals: [
        { endPolylinePointIndex: 3, speed: 'NORMAL' },
        { startPolylinePointIndex: 3, endPolylinePointIndex: 5, speed: 'SLOW' }
      ] },
      legs: []
    }] : [] }), { headers: { 'content-type': 'application/json' } });
  };
  try {
    const plan = await routeOptions([174.76, -36.85], [174.77, -36.86], { GOOGLE_ROUTES_API_KEY: 'test' });
    const drive = requests.find((request) => request.travelMode === 'DRIVE');
    assert.deepEqual(drive.extraComputations, ['TRAFFIC_ON_POLYLINE']);
    assert.equal(drive.routingPreference, 'TRAFFIC_AWARE_OPTIMAL');
    assert.equal(plan.trafficAvailable, true);
    assert.deepEqual(plan.options[0].trafficIntervals.map((interval) => interval.speed), ['normal', 'slow']);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
