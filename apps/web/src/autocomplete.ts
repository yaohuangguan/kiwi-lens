import { t, type Language } from './i18n';
import type { RecentDestination } from './account';

export type SuggestedPlace = { id: string | number; label: string; latitude: number; longitude: number };
type Target = 'origin' | 'destination';

export function initAutocomplete(options: {
  origin: HTMLInputElement;
  destination: HTMLInputElement;
  results: HTMLElement;
  language: () => Language;
  recent: () => RecentDestination[];
  select: (target: Target, place: SuggestedPlace) => void;
}) {
  let timer = 0;
  let pending: AbortController | null = null;
  let configured = true;
  let sequence = 0;

  function render(target: Target, places: SuggestedPlace[], heading?: string) {
    options.results.replaceChildren();
    if (heading) {
      const label = document.createElement('div');
      label.className = 'search-message';
      label.textContent = heading;
      options.results.append(label);
    }
    for (const place of places) {
      const button = document.createElement('button');
      button.className = 'result-item';
      button.type = 'button';
      const pin = document.createElement('span');
      pin.className = 'result-pin';
      pin.textContent = '⌖';
      const label = document.createElement('span');
      label.textContent = place.label;
      button.append(pin, label);
      button.onclick = () => {
        pending?.abort();
        window.clearTimeout(timer);
        options.results.hidden = true;
        options.select(target, place);
      };
      options.results.append(button);
    }
    options.results.hidden = !options.results.childElementCount;
  }

  function showRecent() {
    const recent = options.recent();
    if (recent.length) render('destination', recent.map((place, index) => ({ ...place, id: index })), t(options.language(), 'guestRecent'));
  }

  for (const [target, input] of [['origin', options.origin], ['destination', options.destination]] as const) {
    input.addEventListener('focus', () => {
      if (target === 'destination' && !input.value.trim()) showRecent();
    });
    input.addEventListener('input', () => {
      pending?.abort();
      window.clearTimeout(timer);
      const query = input.value.trim();
      if (query.length < 3) {
        if (target === 'destination' && !query) showRecent();
        else options.results.hidden = true;
        return;
      }
      const requestNumber = ++sequence;
      timer = window.setTimeout(async () => {
        pending = new AbortController();
        try {
          const searchUrl = `/api/search?q=${encodeURIComponent(query)}`;
          let response = await fetch(configured
            ? `/api/suggest?q=${encodeURIComponent(query)}&lang=${options.language()}`
            : searchUrl, { signal: pending.signal });
          if (configured && response.status === 503) {
            configured = false;
            response = await fetch(searchUrl, { signal: pending.signal });
          }
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          const places = await response.json() as SuggestedPlace[];
          if (requestNumber === sequence && input.value.trim() === query) render(target, places);
        } catch (error) {
          if ((error as Error).name !== 'AbortError' && requestNumber === sequence) options.results.hidden = true;
        }
      }, 450);
    });
  }
}
