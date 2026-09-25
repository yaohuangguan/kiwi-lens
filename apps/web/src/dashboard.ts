import './account.css';
import './site.css';
import { currentProfile, initAccount, type AccountProfile, type Language } from './account';
import { renderProfileView } from './profile-view';

const logo = `
  <span class="site-logo" aria-hidden="true"><img src="/favicon.svg" alt="" /></span>
  <span class="site-wordmark">TASMAN</span>`;

let language: Language = 'en';
let voiceEnabled = true;

document.documentElement.lang = 'en-NZ';
document.title = 'Dashboard · Tasman';
document.body.dataset.surface = 'dashboard';
document.body.innerHTML = `
  <div class="dashboard-shell">
    <header class="dashboard-header">
      <a class="site-brand" href="/">${logo}</a>
      <nav><a href="/">Website</a><a class="site-primary-button compact" href="/app">Open navigator <span>↗</span></a></nav>
    </header>
    <main class="dashboard-layout">
      <aside class="dashboard-sidebar">
        <span class="dashboard-label">ACCOUNT</span>
        <h1 id="dashboardTitle">Your Tasman</h1>
        <p id="dashboardIntro">Sign in to keep recent trips, favorite places, notes and personal reviews together.</p>
        <div id="dashboardAccount" class="dashboard-account"></div>
        <div class="dashboard-help"><strong>Navigation stays available</strong><p>You can always use Tasman in guest mode. An account adds synchronization and history.</p><a href="/app">Continue as guest →</a></div>
      </aside>
      <section class="dashboard-main">
        <div class="dashboard-topline"><div><span class="dashboard-label">DASHBOARD</span><h2 id="dashboardGreeting">Your activity, all in one place.</h2></div><span class="dashboard-status"><i></i><span id="dashboardStatusText">Guest mode</span></span></div>
        <div id="dashboardEmpty" class="dashboard-empty">
          <div class="dashboard-empty-intro">
            <div class="dashboard-empty-icon">◎</div>
            <div><h3>Sign in to make Tasman yours</h3><p>Navigation stays available without an account. Sign in when you want history and personal context to follow you.</p></div>
          </div>
          <div class="dashboard-empty-grid">
            <article><span>↗</span><strong>Recent navigation</strong><p>Keep a lightweight history of destinations, travel modes and trip distance.</p></article>
            <article><span>♥</span><strong>Saved places + notes</strong><p>Favorite places and keep private notes for the locations you return to.</p></article>
            <article><span>★</span><strong>Your own reviews</strong><p>Store personal ratings and comments separately from public Google reviews.</p></article>
          </div>
          <div class="dashboard-empty-actions"><a class="site-primary-button" href="/app">Open navigator <span>→</span></a><small>Account features are optional. Core navigation works in guest mode.</small></div>
        </div>
        <div id="dashboardContent" class="dashboard-content" hidden></div>
      </section>
    </main>
  </div>`;

const accountRoot = document.getElementById('dashboardAccount') as HTMLElement;
const contentRoot = document.getElementById('dashboardContent') as HTMLElement;

function renderDashboard() {
  const profile = currentProfile();
  const signedIn = Boolean(profile);
  (document.getElementById('dashboardEmpty') as HTMLElement).hidden = signedIn;
  contentRoot.hidden = !signedIn;
  (document.getElementById('dashboardStatusText') as HTMLElement).textContent = signedIn
    ? (language === 'zh' ? '已同步' : 'Account synced')
    : (language === 'zh' ? '访客模式' : 'Guest mode');
  (document.getElementById('dashboardGreeting') as HTMLElement).textContent = signedIn
    ? (language === 'zh' ? '欢迎回来，这是你的近期活动。' : 'Welcome back. Here’s your recent activity.')
    : (language === 'zh' ? '你的活动，集中在一个页面。' : 'Your activity, all in one place.');
  (document.getElementById('dashboardTitle') as HTMLElement).textContent = language === 'zh' ? '你的 Tasman' : 'Your Tasman';
  (document.getElementById('dashboardIntro') as HTMLElement).textContent = language === 'zh'
    ? '登录后可集中查看最近行程、收藏地点、备注和个人评价。'
    : 'Sign in to keep recent trips, favorite places, notes and personal reviews together.';
  if (profile) renderProfileView(contentRoot, language, () => {});
}

window.addEventListener('kiwi-account-change', renderDashboard);
void initAccount(accountRoot, () => language, () => voiceEnabled, (profile: AccountProfile) => {
  language = profile.language;
  voiceEnabled = profile.voiceEnabled;
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en-NZ';
  renderDashboard();
});
renderDashboard();
