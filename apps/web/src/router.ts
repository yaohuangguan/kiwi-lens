const path = window.location.pathname.replace(/\/+$/, '') || '/';
const app = document.getElementById('app');

function renderBootState(label: string) {
  document.body.innerHTML = `
    <div style="min-height:100vh;display:grid;place-items:center;background:#f5f9ff;color:#071c35;font:600 14px system-ui,sans-serif">
      <div style="display:grid;justify-items:center;gap:14px">
        <span style="width:42px;height:42px;border-radius:13px;background:#071c35;box-shadow:0 10px 26px rgba(11,23,23,.18)"></span>
        <span style="color:#61758b">${label}</span>
      </div>
    </div>`;
}

async function boot() {
  try {
    if (path === '/app') {
      if (app) app.hidden = false;
      await import('./main');
      return;
    }

    app?.remove();

    if (path === '/dashboard') {
      renderBootState('Loading your Tasman dashboard…');
      await import('./dashboard');
      return;
    }

    renderBootState('Loading Tasman…');
    await import('./marketing');
  } catch (error) {
    console.error('Tasman route failed to load', error);
    document.body.innerHTML = `
      <main style="min-height:100vh;display:grid;place-items:center;padding:32px;background:#f5f9ff;font-family:system-ui,sans-serif;color:#071c35">
        <div style="max-width:520px;text-align:center"><h1>Tasman could not load this page.</h1><p style="color:#61758b">Refresh the page or return to the website.</p><a href="/" style="color:#0284c7;font-weight:700">Return home</a></div>
      </main>`;
  }
}

void boot();
