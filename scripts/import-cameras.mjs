import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { createHash } from 'node:crypto';

function parseCsv(text) {
  const rows = [];
  let row = [];
  let cell = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (char === '"') {
      if (quoted && text[i + 1] === '"') { cell += '"'; i++; }
      else quoted = !quoted;
    } else if (char === ',' && !quoted) {
      row.push(cell.trim()); cell = '';
    } else if ((char === '\n' || char === '\r') && !quoted) {
      if (char === '\r' && text[i + 1] === '\n') i++;
      row.push(cell.trim()); cell = '';
      if (row.some(Boolean)) rows.push(row);
      row = [];
    } else cell += char;
  }
  row.push(cell.trim());
  if (row.some(Boolean)) rows.push(row);
  const headers = rows.shift()?.map((header) => header.replace(/^\uFEFF/, '')) || [];
  return rows.map((values) => Object.fromEntries(headers.map((header, i) => [header, values[i] || ''])));
}

const input = process.argv[2];
if (!input) throw new Error('Usage: npm run data:import -- <path-to-nzta.csv>');
const rows = parseCsv(await readFile(resolve(input), 'utf8'));
const cameras = rows.map((row) => {
  const latitude = Number(row.Latitude);
  const longitude = Number(row.Longitude);
  if (!(latitude > -48 && latitude < -34 && longitude > 166 && longitude < 179)) throw new Error(`Invalid coordinates: ${row.Name}`);
  const location = row.Location;
  return {
    id: createHash('sha256').update(`${location.toLowerCase()}|${latitude.toFixed(6)}|${longitude.toFixed(6)}`).digest('hex').slice(0, 16),
    name: row.Name, region: row.Region, suburb: row.Suburb, location, type: row['Camera Type'],
    latitude, longitude, source: row.Source, updatedAt: row['Source Last Updated']
  };
});
if (cameras.length < 50 || cameras.length > 1000) throw new Error(`Refusing suspicious CSV row count: ${cameras.length}`);
if (new Set(cameras.map((camera) => camera.id)).size !== cameras.length) throw new Error('Duplicate camera IDs');
const output = resolve('apps/server/data/cameras.json');
await mkdir(dirname(output), { recursive: true });
await writeFile(output, JSON.stringify({ cameras, sourceUpdatedAt: cameras[0].updatedAt }, null, 2) + '\n');
console.log(`Imported ${cameras.length} cameras into ${output}`);
