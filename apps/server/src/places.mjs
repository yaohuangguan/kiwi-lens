function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' }
  });
}

function nzPoint(value) {
  const [lon, lat] = (value || '').split(',').map(Number);
  return lon > 166 && lon < 179 && lat > -48 && lat < -34 ? [lon, lat] : null;
}

export async function handlePlaces(request, env) {
  const url = new URL(request.url);
  if (url.pathname === '/api/suggest') {
    if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
    if (!env.GEOAPIFY_API_KEY) return json({ error: 'Address autocomplete is not configured' }, 503);
    const query = (url.searchParams.get('q') || '').trim();
    if (query.length < 3 || query.length > 120) return json({ error: 'Query must be 3–120 characters' }, 400);
    const point = nzPoint(url.searchParams.get('near'));
    const provider = new URL('https://api.geoapify.com/v1/geocode/autocomplete');
    provider.searchParams.set('text', query);
    provider.searchParams.set('filter', 'countrycode:nz');
    provider.searchParams.set('lang', url.searchParams.get('lang') === 'zh' ? 'zh' : 'en');
    provider.searchParams.set('limit', '6');
    provider.searchParams.set('format', 'json');
    provider.searchParams.set('apiKey', env.GEOAPIFY_API_KEY);
    if (point) provider.searchParams.set('bias', `proximity:${point.join(',')}`);
    const upstream = await fetch(provider, { signal: AbortSignal.timeout(10000) });
    if (!upstream.ok) return json({ error: 'Address autocomplete unavailable' }, 502);
    const data = await upstream.json();
    return json((data.results || []).filter((place) =>
      Number.isFinite(place.lat) && Number.isFinite(place.lon) && place.country_code?.toLowerCase() === 'nz'
    ).map((place) => ({ id: place.place_id || place.datasource?.raw?.osm_id || place.formatted,
      label: place.formatted, latitude: place.lat, longitude: place.lon })));
  }
  if (url.pathname === '/api/reverse') {
    if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
    const point = nzPoint(url.searchParams.get('at'));
    if (!point) return json({ error: 'Valid NZ coordinates required' }, 400);
    const provider = new URL('https://nominatim.openstreetmap.org/reverse');
    provider.searchParams.set('format', 'jsonv2');
    provider.searchParams.set('lat', String(point[1]));
    provider.searchParams.set('lon', String(point[0]));
    provider.searchParams.set('zoom', '14');
    provider.searchParams.set('addressdetails', '1');
    const upstream = await fetch(provider, {
      headers: { 'user-agent': 'KiwiLens/0.1 (https://github.com/yaohuangguan/kiwi-lens)',
        referer: 'https://github.com/yaohuangguan/kiwi-lens', accept: 'application/json' },
      signal: AbortSignal.timeout(10000)
    });
    if (!upstream.ok) return json({ error: 'Current-place lookup unavailable' }, 502);
    const data = await upstream.json();
    if (data.address?.country_code !== 'nz') return json({ error: 'Location is outside New Zealand' }, 422);
    const address = data.address || {};
    return json({ label: [address.road || address.suburb || address.neighbourhood,
      address.suburb || address.city || address.town || address.village,
      address.city || address.town || address.region].filter(Boolean).filter((item, index, values) => values.indexOf(item) === index).join(', ') || data.display_name });
  }
  return null;
}
