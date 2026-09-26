const KEY = 'road-reports/current';
const MAX_REPORTS = 250;
const ALLOWED = new Set(['incident', 'roadworks', 'roadClosure', 'congestion', 'flooding', 'slip']);

function validCoordinate(latitude, longitude) {
  return Number.isFinite(latitude) && Number.isFinite(longitude) &&
    longitude > 166 && longitude < 179 && latitude > -48 && latitude < -34;
}

export async function readRoadReports(env, now = new Date()) {
  const state = await env.CAMERA_DATA.get(KEY, 'json');
  const reports = Array.isArray(state?.reports) ? state.reports : [];
  return reports.filter((report) => {
    const until = Date.parse(report.validUntil || '');
    return Number.isFinite(until) && until > now.getTime();
  });
}

export async function createRoadReport(env, payload, now = new Date()) {
  const latitude = Number(payload?.latitude);
  const longitude = Number(payload?.longitude);
  const type = String(payload?.type || '');
  if (!validCoordinate(latitude, longitude) || !ALLOWED.has(type)) {
    throw new TypeError('Valid NZ road report required');
  }
  const heading = Number(payload?.headingDegrees);
  const id = crypto.randomUUID();
  const report = {
    id: 'tasman:report:' + id,
    type,
    location: { latitude, longitude },
    geometry: [{ latitude, longitude }],
    severity: type === 'roadClosure' ? 'critical' : type === 'incident' ? 'warning' : 'advisory',
    confidence: 0.65,
    observation: 'observed',
    headingDegrees: Number.isFinite(heading) ? ((heading % 360) + 360) % 360 : null,
    validFrom: now.toISOString(),
    validUntil: new Date(now.getTime() + 2 * 60 * 60 * 1000).toISOString(),
    source: {
      provider: 'Tasman road reports',
      country: 'NZ',
      region: null,
      sourceId: id,
      updatedAt: now.toISOString()
    },
    metadata: {
      description: String(payload?.description || '').trim().slice(0, 120),
      userReported: true
    }
  };
  const current = await readRoadReports(env, now);
  const reports = [report, ...current].slice(0, MAX_REPORTS);
  await env.CAMERA_DATA.put(KEY, JSON.stringify({ reports, updatedAt: now.toISOString() }));
  return report;
}
