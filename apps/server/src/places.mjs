function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'access-control-allow-origin': '*' }
  });
}

function nzPoint(value) {
  const [lon, lat] = (value || '').split(',').map(Number);
  return lon > 166 && lon < 179 && lat > -48 && lat < -34 ? [lon, lat] : null;
}

function placesApiKey(env) {
  return env.GOOGLE_PLACES_SERVER_API_KEY || env.GOOGLE_ROUTES_API_KEY;
}

function localizedText(value) {
  if (!value) return '';
  if (typeof value === 'string') return value;
  return typeof value.text === 'string' ? value.text : '';
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
    ).map((place) => {
      const name = place.name || place.address_line1 || place.formatted;
      const addressParts = [
        place.address_line1 !== name ? place.address_line1 : null,
        place.address_line2
      ].filter(Boolean);
      return {
        id: place.place_id || place.datasource?.raw?.osm_id || place.formatted,
        name,
        address: addressParts.join(', ') || place.formatted,
        label: place.formatted,
        latitude: place.lat,
        longitude: place.lon
      };
    }));
  }
  if (url.pathname === '/api/place-details') {
    if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
    const apiKey = placesApiKey(env);
    if (!apiKey) return json({ error: 'Google Places server key is not configured' }, 503);
    const placeId = (url.searchParams.get('placeId') || '').trim();
    if (!/^[A-Za-z0-9_-]{8,300}$/.test(placeId)) return json({ error: 'Valid Google Place ID required' }, 400);
    const provider = new URL(`https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`);
    provider.searchParams.set('languageCode', url.searchParams.get('lang') === 'zh' ? 'zh-CN' : 'en');
    provider.searchParams.set('regionCode', 'NZ');
    const fieldMask = [
      'id', 'displayName', 'formattedAddress', 'primaryTypeDisplayName', 'rating',
      'userRatingCount', 'businessStatus', 'priceLevel', 'nationalPhoneNumber',
      'websiteUri', 'googleMapsUri', 'editorialSummary', 'regularOpeningHours',
      'photos', 'reviews'
    ].join(',');
    const upstream = await fetch(provider, {
      headers: { 'X-Goog-Api-Key': apiKey, 'X-Goog-FieldMask': fieldMask },
      signal: AbortSignal.timeout(12000)
    });
    if (!upstream.ok) return json({ error: `Google Places HTTP ${upstream.status}` }, upstream.status === 404 ? 404 : 502);
    const place = await upstream.json();
    return json({
      placeId: place.id || placeId,
      name: localizedText(place.displayName) || 'Selected place',
      address: place.formattedAddress || '',
      primaryType: localizedText(place.primaryTypeDisplayName),
      rating: Number.isFinite(place.rating) ? place.rating : null,
      userRatingCount: Number.isFinite(place.userRatingCount) ? place.userRatingCount : null,
      businessStatus: place.businessStatus || null,
      priceLevel: place.priceLevel || null,
      phone: place.nationalPhoneNumber || '',
      websiteUri: place.websiteUri || '',
      googleMapsUri: place.googleMapsUri || '',
      editorialSummary: localizedText(place.editorialSummary),
      openingHours: place.regularOpeningHours?.weekdayDescriptions || [],
      photos: (place.photos || []).slice(0, 8).filter((photo) => photo?.name).map((photo) => ({
        name: photo.name,
        attribution: (photo.authorAttributions || []).map((author) => author.displayName).filter(Boolean).join(', ')
      })),
      reviews: (place.reviews || []).slice(0, 5).map((review) => ({
        author: review.authorAttribution?.displayName || 'Google user',
        authorPhoto: review.authorAttribution?.photoUri || null,
        rating: Number.isFinite(review.rating) ? review.rating : null,
        text: localizedText(review.text) || localizedText(review.originalText),
        relativeTime: review.relativePublishTimeDescription || '',
        googleMapsUri: review.googleMapsUri || null
      }))
    });
  }
  if (url.pathname === '/api/place-photo') {
    if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405);
    const apiKey = placesApiKey(env);
    if (!apiKey) return json({ error: 'Google Places server key is not configured' }, 503);
    const name = (url.searchParams.get('name') || '').trim();
    if (!/^places\/[^/]+\/photos\/[^/]+$/.test(name)) return json({ error: 'Valid photo name required' }, 400);
    const provider = new URL(`https://places.googleapis.com/v1/${name}/media`);
    provider.searchParams.set('maxWidthPx', '1200');
    provider.searchParams.set('key', apiKey);
    const upstream = await fetch(provider, { redirect: 'follow', signal: AbortSignal.timeout(12000) });
    if (!upstream.ok) return json({ error: `Google Place Photo HTTP ${upstream.status}` }, 502);
    return new Response(upstream.body, {
      status: 200,
      headers: {
        'content-type': upstream.headers.get('content-type') || 'image/jpeg',
        'cache-control': 'no-store',
        'access-control-allow-origin': '*'
      }
    });
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
