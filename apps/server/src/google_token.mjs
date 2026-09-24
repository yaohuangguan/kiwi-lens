const jwksUrl = 'https://www.googleapis.com/oauth2/v3/certs';
let cachedKeys;
let keysExpiresAt = 0;

function base64UrlBytes(value) {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error('Invalid ID token encoding');
  const decoded = atob(value.replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function jsonPart(value) {
  return JSON.parse(new TextDecoder().decode(base64UrlBytes(value)));
}

async function googleKeys(fetchJwks, now) {
  if (fetchJwks === globalThis.fetch && cachedKeys && now < keysExpiresAt) return cachedKeys;
  const response = await fetchJwks(jwksUrl);
  if (!response.ok) throw new Error('Google signing keys are unavailable');
  const body = await response.json();
  if (!Array.isArray(body.keys)) throw new Error('Invalid Google signing keys');
  const maxAge = Number(/max-age=(\d+)/.exec(response.headers.get('cache-control') || '')?.[1] || 300);
  if (fetchJwks === globalThis.fetch) {
    cachedKeys = body.keys;
    keysExpiresAt = now + Math.min(Math.max(maxAge, 60), 86400) * 1000;
  }
  return body.keys;
}

export async function verifyGoogleIdToken(idToken, allowedClientIds, { fetchJwks = globalThis.fetch, now = Date.now() } = {}) {
  if (typeof idToken !== 'string' || idToken.length > 10000) throw new Error('Invalid Google ID token');
  const parts = idToken.split('.');
  if (parts.length !== 3) throw new Error('Invalid Google ID token');
  const header = jsonPart(parts[0]);
  const claims = jsonPart(parts[1]);
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw new Error('Unsupported Google ID token');
  const allowed = String(allowedClientIds || '').split(',').map((value) => value.trim()).filter(Boolean);
  if (!allowed.length) throw new Error('Google sign-in is not configured');
  if (!allowed.includes(claims.aud) || (claims.azp && !allowed.includes(claims.azp))) {
    throw new Error('Google token audience mismatch');
  }
  if (!['accounts.google.com', 'https://accounts.google.com'].includes(claims.iss) ||
      !Number.isFinite(claims.exp) || claims.exp * 1000 <= now ||
      (Number.isFinite(claims.nbf) && claims.nbf * 1000 > now + 60000) ||
      typeof claims.sub !== 'string' || !claims.sub ||
      typeof claims.email !== 'string' ||
      claims.email_verified !== true && claims.email_verified !== 'true') {
    throw new Error('Invalid Google identity claims');
  }
  const jwks = await googleKeys(fetchJwks, now);
  const jwk = jwks.find((key) => key.kid === header.kid && key.kty === 'RSA' && key.use === 'sig' && key.alg === 'RS256');
  if (!jwk) throw new Error('Google signing key not found');
  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5', key, base64UrlBytes(parts[2]), new TextEncoder().encode(parts[0] + '.' + parts[1])
  );
  if (!valid) throw new Error('Google ID token signature failed');
  return { sub: claims.sub, email: claims.email.trim().toLowerCase(), name: String(claims.name || '').slice(0, 100) };
}
