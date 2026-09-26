import { pbkdf2, scrypt } from 'node:crypto';
import { verifyGoogleIdToken } from './google_token.mjs';

const encoder = new TextEncoder();
const COOKIE_NAME = 'kiwi_session';
const SESSION_SECONDS = 30 * 24 * 60 * 60;
const LEGACY_HASH_ITERATIONS = 210_000;
const PASSWORD_HASH_VERSION = 'scrypt-v1$';

function response(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers }
  });
}

function hex(bytes) {
  return Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

function fromHex(value) {
  if (!/^(?:[0-9a-f]{2})+$/i.test(value)) return new Uint8Array(0);
  return Uint8Array.from(value.match(/.{2}/g), (part) => Number.parseInt(part, 16));
}

async function digest(value) {
  return hex(await crypto.subtle.digest('SHA-256', encoder.encode(value)));
}

export async function hashPassword(password, saltHex) {
  const salt = fromHex(saltHex);
  if (salt.length !== 16) throw new Error('Invalid password salt');
  const derived = await new Promise((resolve, reject) => {
    scrypt(password, salt, 32, { N: 16_384, r: 8, p: 1, maxmem: 32 * 1024 * 1024 }, (error, key) => {
      if (error) reject(error);
      else resolve(key);
    });
  });
  return PASSWORD_HASH_VERSION + hex(derived);
}

function constantTimeEquals(a, b) {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index++) difference |= a.charCodeAt(index) ^ b.charCodeAt(index);
  return difference === 0;
}

export async function verifyPassword(password, saltHex, storedHash) {
  if (typeof storedHash !== 'string') return false;
  if (storedHash.startsWith(PASSWORD_HASH_VERSION)) {
    return constantTimeEquals(await hashPassword(password, saltHex), storedHash);
  }
  // Accounts created before the Worker-compatible migration used PBKDF2-SHA256.
  if (!/^[0-9a-f]{64}$/i.test(storedHash)) return false;
  const salt = fromHex(saltHex);
  if (salt.length !== 16) return false;
  const legacyHash = await new Promise((resolve, reject) => {
    pbkdf2(password, salt, LEGACY_HASH_ITERATIONS, 32, 'sha256', (error, key) => {
      if (error) reject(error);
      else resolve(hex(key));
    });
  });
  return constantTimeEquals(legacyHash, storedHash);
}

function cookieHeader(token, request) {
  const secure = new URL(request.url).protocol === 'https:' ? '; Secure' : '';
  return `${COOKIE_NAME}=${token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${SESSION_SECONDS}${secure}`;
}

function clearCookieHeader(request) {
  const secure = new URL(request.url).protocol === 'https:' ? '; Secure' : '';
  return `${COOKIE_NAME}=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0${secure}`;
}

function sessionToken(request) {
  const cookies = request.headers.get('cookie') || '';
  const match = cookies.match(/(?:^|;\s*)kiwi_session=([0-9a-f]{64})(?:;|$)/);
  return match?.[1] || null;
}

async function userFromRequest(db, request) {
  const token = sessionToken(request);
  if (!token) return null;
  return db.prepare(`SELECT users.id, users.email FROM sessions
    JOIN users ON users.id = sessions.user_id
    WHERE sessions.token_hash = ? AND sessions.expires_at > ?`)
    .bind(await digest(token), Date.now()).first();
}

export async function roadReportAuthor(db, request) {
  const user = await userFromRequest(db, request);
  if (!user) return null;
  const profile = await db.prepare(
    'SELECT display_name FROM profiles WHERE user_id = ?'
  ).bind(user.id).first();
  const displayName = String(profile?.display_name || '').trim();
  return {
    id: user.id,
    displayName: displayName || 'Tasman driver'
  };
}

async function userProfile(db, user) {
  const profile = await db.prepare('SELECT language, voice_enabled, display_name FROM profiles WHERE user_id = ?').bind(user.id).first();
  const googleIdentity = await db.prepare('SELECT google_sub FROM google_identities WHERE user_id = ?').bind(user.id).first();
  const passwordUser = await db.prepare('SELECT password_hash FROM users WHERE id = ?').bind(user.id).first();
  const recent = await db.prepare(`SELECT label, latitude, longitude FROM recent_destinations
    WHERE user_id = ? ORDER BY updated_at DESC LIMIT 20`).bind(user.id).all();
  const saved = await db.prepare(`SELECT place_id AS placeId, name, address, latitude, longitude,
      is_favorite AS isFavorite, note, updated_at AS updatedAt
    FROM place_bookmarks
    WHERE user_id = ? AND (is_favorite = 1 OR note <> '')
    ORDER BY updated_at DESC LIMIT 100`).bind(user.id).all();
  const routes = await db.prepare(`SELECT id, destination_name AS destinationName,
    destination_latitude AS latitude, destination_longitude AS longitude, mode,
    distance_meters AS distanceMeters, duration_seconds AS durationSeconds, started_at AS startedAt
    FROM route_history WHERE user_id = ? ORDER BY started_at DESC LIMIT 100`).bind(user.id).all();
  const reviews = await db.prepare(`SELECT place_id AS placeId, place_name AS placeName,
    rating, comment, updated_at AS updatedAt
    FROM place_reviews WHERE user_id = ? ORDER BY updated_at DESC LIMIT 100`).bind(user.id).all();
  return {
    user: { id: user.id, email: user.email, displayName: profile?.display_name || '', providers: [
      ...(passwordUser?.password_hash ? ['password'] : []), ...(googleIdentity ? ['google'] : [])
    ] },
    language: profile?.language === 'zh' ? 'zh' : 'en',
    voiceEnabled: profile?.voice_enabled !== 0,
    recentDestinations: recent.results || [],
    savedPlaces: (saved.results || []).map((place) => ({
      ...place,
      isFavorite: place.isFavorite === 1
    })),
    routeHistory: routes.results || [],
    reviews: reviews.results || []
  };
}

async function issueSession(db, user, request) {
  const token = hex(crypto.getRandomValues(new Uint8Array(32)));
  await db.prepare('INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)')
    .bind(await digest(token), user.id, Date.now() + SESSION_SECONDS * 1000).run();
  return response(await userProfile(db, user), 200, { 'set-cookie': cookieHeader(token, request) });
}

async function readBody(request) {
  if (!request.headers.get('content-type')?.startsWith('application/json')) return null;
  if (Number(request.headers.get('content-length') || 0) > 4096) return null;
  return request.json().catch(() => null);
}

function validEmail(email) {
  return typeof email === 'string' && email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

async function tooManyAttempts(db, email) {
  const row = await db.prepare('SELECT failures, window_start FROM login_attempts WHERE email = ?').bind(email).first();
  return Boolean(row && row.failures >= 5 && Date.now() - row.window_start < 15 * 60_000);
}

async function failedAttempt(db, email) {
  const now = Date.now();
  await db.prepare(`INSERT INTO login_attempts (email, failures, window_start) VALUES (?, 1, ?)
    ON CONFLICT(email) DO UPDATE SET failures = CASE WHEN ? - window_start >= 900000 THEN 1 ELSE failures + 1 END,
    window_start = CASE WHEN ? - window_start >= 900000 THEN ? ELSE window_start END`)
    .bind(email, now, now, now, now).run();
}

export async function handleAccount(request, env) {
  const path = new URL(request.url).pathname;
  if (!path.startsWith('/api/auth/') && !path.startsWith('/api/profile')) return null;
  if (!env.USER_DB) return response({ error: 'Account storage is not configured' }, 503);
  if (['POST', 'PATCH', 'DELETE'].includes(request.method)) {
    const origin = request.headers.get('origin');
    const client = request.headers.get('x-kiwi-client');
    if ((origin && origin !== new URL(request.url).origin) || !['web', 'mobile'].includes(client) || (client === 'mobile' && origin)) {
      return response({ error: 'Invalid request origin' }, 403);
    }
  }
  const db = env.USER_DB;

  if (path === '/api/auth/register' && request.method === 'POST') {
    const body = await readBody(request);
    const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
    const password = body?.password;
    if (!validEmail(email) || typeof password !== 'string' || password.length < 12 || password.length > 128) {
      return response({ error: 'Use a valid email and a password of 12–128 characters' }, 400);
    }
    const existing = await db.prepare('SELECT id FROM users WHERE email = ?').bind(email).first();
    if (existing) return response({ error: 'This email is already registered' }, 409);
    const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
    const user = { id: crypto.randomUUID(), email };
    try {
      await db.batch([
        db.prepare('INSERT INTO users (id, email, password_salt, password_hash, created_at) VALUES (?, ?, ?, ?, ?)')
          .bind(user.id, email, salt, await hashPassword(password, salt), Date.now()),
        db.prepare('INSERT INTO profiles (user_id, language, voice_enabled) VALUES (?, ?, ?)')
          .bind(user.id, body.language === 'zh' ? 'zh' : 'en', body.voiceEnabled === false ? 0 : 1)
      ]);
    } catch (error) {
      if (/UNIQUE/i.test(String(error))) return response({ error: 'This email is already registered' }, 409);
      throw error;
    }
    return issueSession(db, user, request);
  }

  if (path === '/api/auth/login' && request.method === 'POST') {
    const body = await readBody(request);
    const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
    if (!validEmail(email) || typeof body?.password !== 'string') return response({ error: 'Invalid credentials' }, 401);
    if (await tooManyAttempts(db, email)) return response({ error: 'Too many attempts. Try again in 15 minutes.' }, 429);
    const user = await db.prepare('SELECT id, email, password_salt, password_hash FROM users WHERE email = ?').bind(email).first();
    if (!user || !await verifyPassword(body.password, user.password_salt, user.password_hash)) {
      await failedAttempt(db, email);
      return response({ error: 'Invalid credentials' }, 401);
    }
    await db.prepare('DELETE FROM login_attempts WHERE email = ?').bind(email).run();
    return issueSession(db, user, request);
  }

  if (path === '/api/auth/google' && request.method === 'POST') {
    if (!env.GOOGLE_OAUTH_CLIENT_IDS) return response({ error: 'Google sign-in is not configured' }, 503);
    const body = await readBody(request);
    let identity;
    try {
      identity = await verifyGoogleIdToken(body?.idToken, env.GOOGLE_OAUTH_CLIENT_IDS);
    } catch {
      return response({ error: 'Google sign-in could not be verified' }, 401);
    }
    if (!validEmail(identity.email)) return response({ error: 'Google email is unavailable' }, 401);
    const linked = await db.prepare(`SELECT users.id, users.email FROM google_identities
      JOIN users ON users.id = google_identities.user_id WHERE google_sub = ?`).bind(identity.sub).first();
    if (linked) return issueSession(db, linked, request);
    // Never take over a password account based solely on an email claim.
    const existing = await db.prepare('SELECT id FROM users WHERE email = ?').bind(identity.email).first();
    if (existing) return response({ error: 'This email already has an account. Sign in with email first, then link Google in My Account.' }, 409);
    const user = { id: crypto.randomUUID(), email: identity.email };
    try {
      await db.batch([
        db.prepare('INSERT INTO users (id, email, password_salt, password_hash, created_at) VALUES (?, ?, ?, ?, ?)')
          .bind(user.id, user.email, '', '', Date.now()),
        db.prepare('INSERT INTO profiles (user_id, language, voice_enabled, display_name) VALUES (?, ?, ?, ?)')
          .bind(user.id, 'en', 1, identity.name),
        db.prepare('INSERT INTO google_identities (google_sub, user_id, created_at) VALUES (?, ?, ?)')
          .bind(identity.sub, user.id, Date.now())
      ]);
    } catch (error) {
      if (/UNIQUE/i.test(String(error))) return response({ error: 'Google account is already linked. Try signing in again.' }, 409);
      throw error;
    }
    return issueSession(db, user, request);
  }

  if (path === '/api/auth/logout' && request.method === 'POST') {
    const token = sessionToken(request);
    if (token) await db.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(await digest(token)).run();
    return response({ ok: true }, 200, { 'set-cookie': clearCookieHeader(request) });
  }

  const user = await userFromRequest(db, request);
  if (!user) return response({ error: 'Not signed in' }, 401);
  if ((path === '/api/auth/me' || path === '/api/profile') && request.method === 'GET') {
    return response(await userProfile(db, user));
  }
  if (path === '/api/auth/google/link' && request.method === 'POST') {
    if (!env.GOOGLE_OAUTH_CLIENT_IDS) return response({ error: 'Google sign-in is not configured' }, 503);
    const body = await readBody(request);
    let identity;
    try {
      identity = await verifyGoogleIdToken(body?.idToken, env.GOOGLE_OAUTH_CLIENT_IDS);
    } catch {
      return response({ error: 'Google sign-in could not be verified' }, 401);
    }
    if (identity.email !== user.email) return response({ error: 'Google email must match your account email' }, 409);
    const existing = await db.prepare('SELECT user_id FROM google_identities WHERE google_sub = ?').bind(identity.sub).first();
    if (existing && existing.user_id !== user.id) return response({ error: 'Google account is linked elsewhere' }, 409);
    const already = await db.prepare('SELECT google_sub FROM google_identities WHERE user_id = ?').bind(user.id).first();
    if (already && already.google_sub !== identity.sub) return response({ error: 'A different Google account is already linked' }, 409);
    if (!already) await db.prepare('INSERT INTO google_identities (google_sub, user_id, created_at) VALUES (?, ?, ?)')
      .bind(identity.sub, user.id, Date.now()).run();
    return response(await userProfile(db, user));
  }
  if (path === '/api/profile/details' && request.method === 'PATCH') {
    const body = await readBody(request);
    const displayName = typeof body?.displayName === 'string' ? body.displayName.trim() : null;
    if (displayName === null || displayName.length > 100) return response({ error: 'Display name must be at most 100 characters' }, 400);
    await db.prepare('UPDATE profiles SET display_name = ? WHERE user_id = ?').bind(displayName, user.id).run();
    return response(await userProfile(db, user));
  }
  if (path === '/api/profile' && request.method === 'PATCH') {
    const body = await readBody(request);
    if (!body || !['en', 'zh'].includes(body.language) || typeof body.voiceEnabled !== 'boolean') {
      return response({ error: 'Invalid preferences' }, 400);
    }
    await db.prepare('UPDATE profiles SET language = ?, voice_enabled = ? WHERE user_id = ?')
      .bind(body.language, body.voiceEnabled ? 1 : 0, user.id).run();
    return response(await userProfile(db, user));
  }
  if (path === '/api/profile/destinations' && request.method === 'POST') {
    const body = await readBody(request);
    if (typeof body?.label !== 'string' || body.label.length < 1 || body.label.length > 200 ||
      !(body.latitude > -48 && body.latitude < -34 && body.longitude > 166 && body.longitude < 179)) {
      return response({ error: 'Invalid destination' }, 400);
    }
    await db.prepare(`INSERT INTO recent_destinations (user_id, label, latitude, longitude, updated_at)
      VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id, latitude, longitude)
      DO UPDATE SET label = excluded.label, updated_at = excluded.updated_at`)
      .bind(user.id, body.label, body.latitude, body.longitude, Date.now()).run();
    await db.prepare(`DELETE FROM recent_destinations WHERE user_id = ? AND (latitude, longitude) NOT IN
      (SELECT latitude, longitude FROM recent_destinations WHERE user_id = ? ORDER BY updated_at DESC LIMIT 20)`)
      .bind(user.id, user.id).run();
    return response(await userProfile(db, user));
  }
  if (path === '/api/profile/places' && request.method === 'POST') {
    const body = await readBody(request);
    const placeId = typeof body?.placeId === 'string' ? body.placeId.trim() : '';
    const name = typeof body?.name === 'string' ? body.name.trim() : '';
    const address = typeof body?.address === 'string' ? body.address.trim() : '';
    const note = typeof body?.note === 'string' ? body.note.trim() : '';
    if (!placeId || placeId.length > 256 || !name || name.length > 200 || address.length > 500 ||
      note.length > 2000 || typeof body?.isFavorite !== 'boolean' ||
      !(body.latitude > -48 && body.latitude < -34 && body.longitude > 166 && body.longitude < 179)) {
      return response({ error: 'Invalid place bookmark' }, 400);
    }
    await db.prepare(`INSERT INTO place_bookmarks
      (user_id, place_id, name, address, latitude, longitude, is_favorite, note, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, place_id) DO UPDATE SET
        name = excluded.name,
        address = excluded.address,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        is_favorite = excluded.is_favorite,
        note = excluded.note,
        updated_at = excluded.updated_at`)
      .bind(
        user.id, placeId, name, address, body.latitude, body.longitude,
        body.isFavorite ? 1 : 0, note, Date.now()
      ).run();
    if (!body.isFavorite && !note) {
      await db.prepare('DELETE FROM place_bookmarks WHERE user_id = ? AND place_id = ?')
        .bind(user.id, placeId).run();
    }
    return response(await userProfile(db, user));
  }
  if (path === '/api/profile/routes' && request.method === 'POST') {
    const body = await readBody(request);
    const name = typeof body?.destinationName === 'string' ? body.destinationName.trim() : '';
    const mode = body?.mode;
    const distance = body?.distanceMeters;
    const duration = body?.durationSeconds;
    if (!name || name.length > 200 || !['drive', 'transit', 'walk', 'bicycle'].includes(mode) ||
      !(body.latitude > -48 && body.latitude < -34 && body.longitude > 166 && body.longitude < 179) ||
      (distance != null && (!Number.isFinite(distance) || distance < 0 || distance > 5_000_000)) ||
      (duration != null && (!Number.isFinite(duration) || duration < 0 || duration > 2_000_000))) {
      return response({ error: 'Invalid route history' }, 400);
    }
    await db.prepare(`INSERT INTO route_history (id, user_id, destination_name,
      destination_latitude, destination_longitude, mode, distance_meters, duration_seconds, started_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .bind(crypto.randomUUID(), user.id, name, body.latitude, body.longitude, mode,
        distance == null ? null : Math.round(distance), duration == null ? null : Math.round(duration), Date.now()).run();
    await db.prepare(`DELETE FROM route_history WHERE user_id = ? AND id NOT IN
      (SELECT id FROM route_history WHERE user_id = ? ORDER BY started_at DESC LIMIT 100)`)
      .bind(user.id, user.id).run();
    return response(await userProfile(db, user));
  }
  if (path === '/api/profile/reviews' && request.method === 'POST') {
    const body = await readBody(request);
    const placeId = typeof body?.placeId === 'string' ? body.placeId.trim() : '';
    const placeName = typeof body?.placeName === 'string' ? body.placeName.trim() : '';
    const comment = typeof body?.comment === 'string' ? body.comment.trim() : '';
    const rating = body?.rating;
    if (!placeId || placeId.length > 256 || !placeName || placeName.length > 200 ||
      !Number.isInteger(rating) || rating < 1 || rating > 5 || comment.length > 2000) {
      return response({ error: 'Invalid place review' }, 400);
    }
    await db.prepare(`INSERT INTO place_reviews
      (user_id, place_id, place_name, rating, comment, updated_at) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, place_id) DO UPDATE SET
        place_name = excluded.place_name, rating = excluded.rating,
        comment = excluded.comment, updated_at = excluded.updated_at`)
      .bind(user.id, placeId, placeName, rating, comment, Date.now()).run();
    return response(await userProfile(db, user));
  }
  return response({ error: 'Not found' }, 404);
}
