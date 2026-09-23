import test from 'node:test';
import assert from 'node:assert/strict';
import { pbkdf2Sync } from 'node:crypto';
import { hashPassword, verifyPassword } from '../src/auth.mjs';

const salt = '00112233445566778899aabbccddeeff';

test('new password hashes are versioned scrypt values', async () => {
  const stored = await hashPassword('long-secret-password', salt);
  assert.match(stored, /^scrypt-v1\$[0-9a-f]{64}$/);
  assert.equal(await verifyPassword('long-secret-password', salt, stored), true);
  assert.equal(await verifyPassword('wrong-password', salt, stored), false);
});

test('existing PBKDF2 hashes remain valid', async () => {
  const stored = pbkdf2Sync('long-secret-password', Buffer.from(salt, 'hex'), 210_000, 32, 'sha256').toString('hex');
  assert.equal(await verifyPassword('long-secret-password', salt, stored), true);
  assert.equal(await verifyPassword('wrong-password', salt, stored), false);
});
