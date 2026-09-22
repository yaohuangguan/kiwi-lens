import { load } from 'cheerio';
import { createHash } from 'node:crypto';

export const SOURCE_URL = 'https://www.nzta.govt.nz/travelling-on-our-roads/safety-cameras/about-safety-cameras/fixed-safety-camera-locations';
const REGIONS = new Set(['Northland', 'Auckland', 'Waikato', 'Bay of Plenty', 'Taranaki', 'Manawatū-Whanganui', 'Wellington', 'Canterbury', 'Otago', 'Southland']);

export function cameraId(location, latitude, longitude) {
  return createHash('sha256').update(`${location.toLowerCase()}|${latitude.toFixed(6)}|${longitude.toFixed(6)}`).digest('hex').slice(0, 16);
}

export function parseNztaPage(html) {
  const $ = load(html);
  const body = $('main').length ? $('main') : $('body');
  const text = body.text();
  const dateMatch = text.match(/Last\s+update\s*:\s*(\d{1,2})\s+([A-Za-z]+)\s+(20\d{2})/i);
  if (!dateMatch) throw new Error('NZTA update date not found; page may be blocked or its layout changed');
  const parsedDate = new Date(`${dateMatch[1]} ${dateMatch[2]} ${dateMatch[3]} 12:00:00 GMT`);
  if (Number.isNaN(parsedDate.getTime())) throw new Error('NZTA update date invalid');
  const updatedAt = parsedDate.toISOString().slice(0, 10);
  let region = '';
  const cameras = [];
  body.find('h2, h3, h4, table').each((_, element) => {
    if (element.tagName !== 'table') {
      const heading = $(element).text().replace(/\s+/g, ' ').trim();
      if (REGIONS.has(heading)) region = heading;
      return;
    }
    $(element).find('tr').each((__, row) => {
      const cells = $(row).find('td').map((___, cell) => $(cell).text().replace(/\s+/g, ' ').trim()).get();
      if (cells.length < 5) return;
      const [suburb, location, type, latText, lonText] = cells;
      const latitude = Number(latText?.replace(/[^\d.-]/g, ''));
      const longitude = Number(lonText?.replace(/[^\d.-]/g, ''));
      if (!location || !type || !/spot speed|average speed|red light/i.test(type)) return;
      if (!(latitude > -48 && latitude < -34 && longitude > 166 && longitude < 179)) return;
      cameras.push({ id: cameraId(location, latitude, longitude), name: `${location} — ${suburb}`, region, suburb, location, type, latitude, longitude, source: SOURCE_URL, updatedAt });
    });
  });
  const distinct = [...new Map(cameras.map((camera) => [camera.id, camera])).values()];
  if (distinct.length < 50 || distinct.length > 1000) throw new Error(`NZTA page parsed ${distinct.length} cameras; refusing untrusted update`);
  return { cameras: distinct, sourceUpdatedAt: updatedAt };
}

export async function fetchNztaCameras(fetcher = fetch) {
  const response = await fetcher(SOURCE_URL, {
    headers: { 'user-agent': 'KiwiLens/0.1 (+https://github.com/yaohuangguan/kiwi-lens)', accept: 'text/html' },
    signal: AbortSignal.timeout(15000)
  });
  if (!response.ok) throw new Error(`NZTA returned HTTP ${response.status}`);
  return parseNztaPage(await response.text());
}
