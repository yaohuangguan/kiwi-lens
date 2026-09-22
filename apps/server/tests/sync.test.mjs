import test from 'node:test';
import assert from 'node:assert/strict';
import { parseNztaPage } from '../src/sync.mjs';

test('rejects a challenge page instead of deleting known cameras', () => {
  assert.throws(() => parseNztaPage('<html><body>challenge</body></html>'), /update date not found/);
});

test('rejects a partial table instead of replacing all cameras', () => {
  const html = '<main><p>Last update: 26 August 2026</p><h3>Auckland</h3><table><tr><td>CBD</td><td>Queen Street</td><td>Spot speed</td><td>-36.850</td><td>174.764</td></tr></table></main>';
  assert.throws(() => parseNztaPage(html), /refusing untrusted update/);
});
