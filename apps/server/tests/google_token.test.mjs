import test from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';

import { verifyGoogleIdToken } from '../src/google_token.mjs';

const crypto = globalThis.crypto || webcrypto;
const now = Date.now();
const audience = 'server-client.apps.googleusercontent.com';
const iosClient = 'ios-client.apps.googleusercontent.com';
const pair = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true, ['sign', 'verify']
);
const jwk = { ...(await crypto.subtle.exportKey('jwk', pair.publicKey)), kid: 'test-key', use: 'sig', alg: 'RS256' };
const fetchJwks = async () => new Response(JSON.stringify({ keys: [jwk] }), {
  headers: { 'cache-control': 'public, max-age=3600' }
});
const base64url = (value) => Buffer.from(value).toString('base64url');
async function token(overrides = {}) {
  const header = base64url(JSON.stringify({ alg: 'RS256', kid: 'test-key', typ: 'JWT' }));
  const claims = base64url(JSON.stringify({
    iss: 'https://accounts.google.com', aud: audience, azp: iosClient,
    sub: 'stable-google-sub', email: 'driver@gmail.com', email_verified: true,
    name: 'Driver', exp: Math.floor(now / 1000) + 3600, ...overrides
  }));
  const message = header + '.' + claims;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, new TextEncoder().encode(message));
  return message + '.' + base64url(signature);
}

test('accepts a Google-signed token for configured server and iOS clients', async () => {
  const identity = await verifyGoogleIdToken(await token(), audience + ',' + iosClient, { fetchJwks, now });
  assert.deepEqual(identity, { sub: 'stable-google-sub', email: 'driver@gmail.com', name: 'Driver' });
});

test('rejects expired, wrong audience and unverified email claims', async () => {
  for (const claims of [
    { exp: Math.floor(now / 1000) - 1 },
    { aud: 'other.apps.googleusercontent.com' },
    { email_verified: false },
  ]) {
    await assert.rejects(
      verifyGoogleIdToken(await token(claims), audience + ',' + iosClient, { fetchJwks, now })
    );
  }
});

test('rejects a tampered signature', async () => {
  const signed = await token();
  const parts = signed.split('.');
  parts[1] = base64url(JSON.stringify({ iss: 'https://accounts.google.com', aud: audience,
    azp: iosClient, sub: 'attacker', email: 'attacker@gmail.com',
    email_verified: true, exp: Math.floor(now / 1000) + 3600 }));
  await assert.rejects(verifyGoogleIdToken(parts.join('.'), audience + ',' + iosClient, { fetchJwks, now }),
    /signature/);
});
