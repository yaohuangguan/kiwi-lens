import './site.css';

const logo = `<img class="site-lockup" src="/brand/tasman-lockup.png" alt="Tasman Maps & Navigation" />`;

document.documentElement.lang = 'en-NZ';
document.title = 'Tasman · Navigate New Zealand with clarity';
document.querySelector('meta[name="description"]')?.setAttribute(
  'content',
  'Tasman combines route planning, official NZ safety-camera data and focused driving guidance in one navigation experience.',
);
document.body.dataset.surface = 'marketing';
document.body.innerHTML = `
  <div class="site-shell">
    <header class="site-header">
      <a class="site-brand" href="/" aria-label="Tasman home">${logo}</a>
      <nav class="site-nav" aria-label="Main navigation">
        <a href="#product">Product</a>
        <a href="#platform">Platform</a>
        <a href="#safety">Safety data</a>
        <a href="#mobile">Mobile</a>
        <a href="#about">About</a>
        <div class="site-nav-mobile-actions">
          <a href="/dashboard">Sign in</a>
          <a class="mobile-primary" href="/app">Open navigator ↗</a>
        </div>
      </nav>
      <div class="site-header-actions">
        <a class="site-link-button" href="/dashboard">Sign in</a>
        <a class="site-primary-button compact" href="/app">Open navigator <span>↗</span></a>
      </div>
      <button class="site-menu" type="button" aria-label="Toggle navigation" aria-expanded="false">Menu</button>
    </header>

    <main>
      <section class="hero" id="product">
        <div class="hero-copy">
          <div class="hero-kicker"><span></span> Built for New Zealand roads</div>
          <h1>Navigate with a clearer view of what’s ahead.</h1>
          <p class="hero-lead">Tasman brings route planning, official safety-camera locations and focused driving guidance into one calm, practical experience.</p>
          <div class="hero-actions">
            <a class="site-primary-button" href="/app">Plan a route <span>→</span></a>
            <a class="site-secondary-button" href="#how-it-works">See how it works</a>
          </div>
          <div class="hero-proof" aria-label="Product highlights">
            <div><strong>NZ-wide</strong><span>Fixed-camera coverage</span></div>
            <div><strong>6-hour</strong><span>Source refresh checks</span></div>
            <div><strong>4 modes</strong><span>Drive, transit, walk, bike</span></div>
          </div>
        </div>

        <div class="hero-product" aria-label="Tasman navigation preview">
          <div class="product-glow"></div>
          <div class="product-window">
            <div class="product-window-bar">
              <div class="mini-brand">${logo}</div>
              <span class="live-pill"><i></i> Live route</span>
            </div>
            <div class="route-search-card">
              <div class="route-track"><i></i><span></span><b></b></div>
              <div><small>FROM</small><strong>Auckland Central</strong><small>TO</small><strong>Mission Bay</strong></div>
            </div>
            <div class="route-canvas">
              <svg viewBox="0 0 560 360" role="img" aria-label="Stylised route map">
                <path class="map-road secondary" d="M-20 62C110 40 128 142 255 130s176-93 330-64"></path>
                <path class="map-road secondary" d="M42 390c8-125 128-138 157-242S258 8 375-22"></path>
                <path class="map-road secondary" d="M140 390c-7-88 63-117 151-132s146-58 277-29"></path>
                <path class="map-route-shadow" d="M92 300c36-93 119-57 145-133s89-97 201-42"></path>
                <path class="map-route" d="M92 300c36-93 119-57 145-133s89-97 201-42"></path>
                <circle class="route-start" cx="92" cy="300" r="10"></circle>
                <circle class="route-end" cx="438" cy="125" r="12"></circle>
              </svg>
              <div class="camera-marker one">◉</div><div class="camera-marker two">◉</div>
              <div class="route-summary"><span>FASTEST ROUTE</span><strong>18 min</strong><small>8.4 km · 2 cameras ahead</small></div>
            </div>
          </div>
          <div class="floating-alert"><span class="alert-lens">◉</span><div><small>SAFETY CAMERA</small><strong>Great South Road</strong></div><b>780 m</b></div>
        </div>
      </section>

      <section class="trust-strip" aria-label="Data and platform information">
        <span>Powered by official public data</span>
        <strong>NZ Transport Agency Waka Kotahi</strong>
        <i></i><span>Google Maps Platform</span><i></i><span>Designed in Aotearoa</span>
      </section>

      <section class="section feature-intro" id="how-it-works">
        <div class="section-heading">
          <span class="section-label">ONE FOCUSED SYSTEM</span>
          <h2>Useful before the trip.<br />Quietly helpful on the road.</h2>
        </div>
        <p>Tasman is designed around the decisions drivers actually make: where to go, which route to take and what deserves attention next.</p>
      </section>

      <section class="feature-grid" id="safety">
        <article class="feature-card feature-card-large">
          <div class="feature-number">01</div>
          <div class="feature-icon">⌁</div>
          <h3>Route-aware safety cameras</h3>
          <p>See fixed safety cameras in context, with route matching and distance-based alerts that keep the information relevant.</p>
          <div class="camera-sequence"><span>Route begins</span><i></i><b>Camera · 800 m</b><i></i><span>Destination</span></div>
        </article>
        <article class="feature-card">
          <div class="feature-number">02</div>
          <div class="feature-icon">↗</div>
          <h3>Clearer route choices</h3>
          <p>Compare driving alternatives, traffic conditions and practical travel modes without burying the decision in clutter.</p>
          <div class="route-choice"><span class="active">18 min <small>Fastest</small></span><span>22 min <small>Calmer</small></span></div>
        </article>
        <article class="feature-card dark-card">
          <div class="feature-number">03</div>
          <div class="feature-icon">◎</div>
          <h3>Guidance that stays legible</h3>
          <p>Large next-step directions, lane guidance when available and a compact speed view built for quick glances.</p>
          <div class="guidance-sample"><b>↱</b><div><strong>350 m</strong><span>Turn right onto Khyber Pass Rd</span></div></div>
        </article>
      </section>

      <section class="section platform-section" id="platform">
        <div class="platform-heading">
          <div>
            <span class="section-label">PLATFORM</span>
            <h2>One navigation layer, built from accountable inputs.</h2>
          </div>
          <p>Tasman keeps routing, places, safety data and account features separate by design, then brings only the context you need into the map.</p>
        </div>
        <div class="capability-grid">
          <article>
            <span>01 · ROUTING</span>
            <strong>Traffic-aware route planning</strong>
            <p>Driving alternatives use Google routing data with live traffic context where available, while Tasman keeps the route comparison focused.</p>
            <em>Google Maps Platform</em>
          </article>
          <article>
            <span>02 · PLACES</span>
            <strong>Useful place context</strong>
            <p>Search, place details, ratings and destination context stay close to the map so planning does not turn into a separate browsing workflow.</p>
            <em>Places + map context</em>
          </article>
          <article>
            <span>03 · SAFETY</span>
            <strong>Validated NZTA camera data</strong>
            <p>The fixed-camera source is checked every six hours and only a validated snapshot replaces the previous known-good dataset.</p>
            <em>NZTA public source</em>
          </article>
          <article>
            <span>04 · CLIENTS</span>
            <strong>Web first, native where it matters</strong>
            <p>The PWA is built for fast planning and exploration. The native mobile client focuses on background-capable guidance and driving use.</p>
            <em>Vite PWA + Flutter</em>
          </article>
        </div>
        <div class="platform-principles">
          <div><b>Map-first</b><span>Important guidance stays visible without covering the route.</span></div>
          <div><b>Account optional</b><span>Core navigation works in guest mode; sign-in adds history and personal data.</span></div>
          <div><b>Data provenance</b><span>Safety information names its source and exposes freshness instead of hiding it.</span></div>
        </div>
      </section>

      <section class="section data-section">
        <div class="data-copy">
          <span class="section-label">TRUSTED INPUTS</span>
          <h2>Road awareness starts with accountable data.</h2>
          <p>Tasman checks the official New Zealand fixed safety-camera list every six hours. If a refresh fails, the last validated snapshot remains available instead of silently disappearing.</p>
          <a class="inline-link" href="https://www.nzta.govt.nz/travelling-on-our-roads/safety-cameras/about-safety-cameras/fixed-safety-camera-locations" target="_blank" rel="noopener noreferrer">View the NZTA source <span>↗</span></a>
        </div>
        <div class="data-pipeline" aria-label="Safety data processing flow">
          <div><small>01 · SOURCE</small><strong>NZTA safety-camera list</strong><span>Public, accountable source</span></div>
          <b>→</b>
          <div><small>02 · VERIFY</small><strong>Structured validation</strong><span>Completeness and change checks</span></div>
          <b>→</b>
          <div><small>03 · GUIDE</small><strong>Route-aware context</strong><span>Relevant information as you travel</span></div>
        </div>
      </section>

      <section class="section mobile-section" id="mobile">
        <div class="phone-stack" aria-hidden="true">
          <div class="phone phone-back"><span>ROUTE OVERVIEW</span><strong>Mission Bay</strong><div class="phone-route"></div></div>
          <div class="phone phone-front"><span>NEXT MANOEUVRE</span><div class="phone-turn">↱</div><strong>350 m</strong><small>Turn right onto Khyber Pass Rd</small><div class="phone-stats"><b>18 min</b><b>8.4 km</b></div></div>
        </div>
        <div class="mobile-copy">
          <span class="section-label">WEB + NATIVE MOBILE</span>
          <h2>Plan on the web. Take the guidance with you.</h2>
          <p>The web navigator is the fastest way to explore and plan today. The native mobile client is being built around background-capable guidance, voice alerts and a layout made for the road.</p>
          <ul><li>Saved places and recent destinations</li><li>Voice and lane guidance controls</li><li>Driving mode with camera alerts</li></ul>
          <a class="site-secondary-button light" href="/app">Try the web navigator</a>
        </div>
      </section>

      <section class="section account-section-marketing" id="about">
        <div>
          <span class="section-label">YOUR TASMAN</span>
          <h2>A separate dashboard for the places and trips you care about.</h2>
          <p>Sign in to review recent navigation, saved places, private notes and your own place ratings—without turning the public homepage into an account screen.</p>
        </div>
        <div class="dashboard-preview">
          <div class="dash-head"><span>ACCOUNT OVERVIEW</span><b>SL</b></div>
          <strong>Good afternoon</strong><small>Your recent activity at a glance</small>
          <div class="dash-stats"><span><b>12</b> Trips</span><span><b>7</b> Saved</span><span><b>3</b> Reviews</span></div>
          <a href="/dashboard">Open dashboard <span>→</span></a>
        </div>
      </section>

      <section class="section product-standard">
        <div>
          <span class="section-label">DESIGNED FOR RESPONSIBLE USE</span>
          <h2>Useful context, without pretending the map knows everything.</h2>
        </div>
        <div class="standard-copy">
          <p>Tasman treats navigation and camera information as driving aids. Road signs, current conditions and New Zealand law always take priority.</p>
          <div class="standard-facts">
            <span><b>Fixed cameras</b><small>The official source does not provide enforcement direction or lane data.</small></span>
            <span><b>Traffic context</b><small>Live traffic availability can vary by route, mode and Google data coverage.</small></span>
            <span><b>Guest-first</b><small>You can plan and navigate without creating an account.</small></span>
          </div>
        </div>
      </section>

      <section class="final-cta">
        <span class="section-label">READY WHEN YOU ARE</span>
        <h2>See the road ahead with Tasman.</h2>
        <p>Plan your next route and explore the navigation experience in your browser.</p>
        <a class="site-primary-button inverse" href="/app">Open Tasman <span>→</span></a>
      </section>
    </main>

    <footer class="site-footer">
      <a class="site-brand footer-brand" href="/">${logo}</a>
      <p>Navigation and safety information are driving aids only. Always follow road signs, conditions and New Zealand law.</p>
      <div><a href="/app">Navigator</a><a href="/dashboard">Dashboard</a><a href="mailto:hello@kiwilens.nz">Contact</a></div>
      <small>© ${new Date().getFullYear()} Tasman</small>
    </footer>
  </div>`;

const menu = document.querySelector<HTMLButtonElement>('.site-menu');
const nav = document.querySelector<HTMLElement>('.site-nav');
menu?.addEventListener('click', () => {
  const open = menu.getAttribute('aria-expanded') !== 'true';
  menu.setAttribute('aria-expanded', String(open));
  nav?.classList.toggle('open', open);
});

