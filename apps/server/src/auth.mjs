const encoder = new TextEncoder();
const COOKIE_NAME = 'kiwi_session';
const SESSION_SECONDS = 30 * 24 * 60 * 60;
const HASH_ITERATIONS = 210_000;

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
  const key = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
  return hex(await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: HASH_ITERATIONS }, key, 256));
}

function constantTimeEquals(a, b) {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index++) difference |= a.charCodeAt(index) ^ b.charCodeAt(index);
  return difference === 0;
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

async function userProfile(db, user) {
  const profile = await db.prepare('SELECT language, voice_enabled FROM profiles WHERE user_id = ?').bind(user.id).first();
  const recent = await db.prepare(`SELECT label, latitude, longitude FROM recent_destinations
    WHERE user_id = ? ORDER BY updated_at DESC LIMIT 20`).bind(user.id).all();
  return {
    user: { id: user.id, email: user.email },
    language: profile?.language === 'zh' ? 'zh' : 'en',
    voiceEnabled: profile?.voice_enabled !== 0,
    recentDestinations: recent.results || []
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
    if ((origin && origin !== new URL(request.url).origin) || request.headers.get('x-kiwi-client') !== 'web') {
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
    const candidate = user ? await hashPassword(body.password, user.password_salt) : null;
    if (!user || !constantTimeEquals(candidate, user.password_hash)) {
      await failedAttempt(db, email);
      return response({ error: 'Invalid credentials' }, 401);
    }
    await db.prepare('DELETE FROM login_attempts WHERE email = ?').bind(email).run();
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
  return response({ error: 'Not found' }, 404);
}
