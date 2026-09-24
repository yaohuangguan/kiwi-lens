export type Language = 'en' | 'zh';
export type RecentDestination = { label: string; latitude: number; longitude: number };
export type SavedPlace = {
  placeId: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  isFavorite: boolean;
  note: string;
  updatedAt: number;
};
export type RouteHistory = { id: string; destinationName: string; latitude: number; longitude: number; mode: string; distanceMeters: number | null; durationSeconds: number | null; startedAt: number };
export type OwnReview = { placeId: string; placeName: string; rating: number; comment: string; updatedAt: number };
export type AccountProfile = {
  user: { id: string; email: string };
  language: Language;
  voiceEnabled: boolean;
  recentDestinations: RecentDestination[];
  savedPlaces: SavedPlace[];
  routeHistory: RouteHistory[];
  reviews: OwnReview[];
};

let profile: AccountProfile | null = null;
let mode: 'login' | 'register' = 'login';
let accountRoot: HTMLElement;
let getLanguage: () => Language;
let getVoiceEnabled: () => boolean;
let onProfileLoaded: (next: AccountProfile) => void;

async function accountApi<T>(path: string, method = 'GET', body?: object): Promise<T> {
  const response = await fetch(path, {
    method,
    credentials: 'same-origin',
    headers: method === 'GET' ? {} : { 'content-type': 'application/json', 'x-kiwi-client': 'web' },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
  return data as T;
}

const copy = {
  en: {
    title: 'Your account', guest: 'Guest mode: no preferences or destinations are saved.',
    signedIn: 'Signed in as', email: 'Email', password: 'Password (12+ characters)',
    login: 'Sign in', register: 'Create account', switchLogin: 'Already have an account? Sign in',
    switchRegister: 'New here? Create an account', logout: 'Sign out',
    warning: 'Email verification and password recovery are not available yet.',
    error: 'Could not connect to your account.'
  },
  zh: {
    title: '账户', guest: '访客模式：不会保存偏好或目的地。',
    signedIn: '已登录', email: '邮箱', password: '密码（至少 12 位）',
    login: '登录', register: '注册', switchLogin: '已有账户？登录',
    switchRegister: '没有账户？注册', logout: '退出登录',
    warning: '目前尚未提供邮箱验证和找回密码。',
    error: '无法连接账户。'
  }
};

export function isSignedIn() { return Boolean(profile); }
export function currentProfile() { return profile; }
export function ownReview(placeId: string) { return profile?.reviews?.find((review) => review.placeId === placeId) || null; }
export function currentAccountEmail() { return profile?.user.email || ''; }
export function recentDestinations() { return profile?.recentDestinations || []; }
export function savedPlace(placeId: string) {
  return profile?.savedPlaces?.find((place) => place.placeId === placeId) || null;
}

export function renderAccount() {
  if (!accountRoot) return;
  const words = copy[getLanguage()];
  accountRoot.replaceChildren();
  const heading = document.createElement('h3');
  heading.textContent = words.title;
  accountRoot.append(heading);
  if (profile) {
    const signedIn = document.createElement('p');
    signedIn.className = 'account-note';
    signedIn.textContent = `${words.signedIn} ${profile.user.email}`;
    const signOut = document.createElement('button');
    signOut.type = 'button';
    signOut.className = 'account-button secondary';
    signOut.textContent = words.logout;
    signOut.onclick = async () => {
      try { await accountApi('/api/auth/logout', 'POST'); } catch { /* clear client session anyway */ }
      profile = null;
      renderAccount();
      window.dispatchEvent(new Event('kiwi-account-change'));
    };
    accountRoot.append(signedIn, signOut);
    return;
  }
  const guest = document.createElement('p');
  guest.className = 'account-note';
  guest.textContent = words.guest;
  const form = document.createElement('form');
  form.className = 'account-form';
  const email = document.createElement('input');
  email.type = 'email';
  email.required = true;
  email.autocomplete = 'email';
  email.placeholder = words.email;
  email.setAttribute('aria-label', words.email);
  const password = document.createElement('input');
  password.type = 'password';
  password.required = true;
  password.minLength = mode === 'register' ? 12 : 1;
  password.autocomplete = mode === 'register' ? 'new-password' : 'current-password';
  password.placeholder = words.password;
  password.setAttribute('aria-label', words.password);
  const submit = document.createElement('button');
  submit.className = 'account-button';
  submit.type = 'submit';
  submit.textContent = mode === 'login' ? words.login : words.register;
  const status = document.createElement('span');
  status.className = 'account-error';
  status.setAttribute('role', 'status');
  form.append(email, password, submit, status);
  form.onsubmit = async (event) => {
    event.preventDefault();
    submit.disabled = true;
    status.textContent = '';
    try {
      const next = await accountApi<AccountProfile>(`/api/auth/${mode === 'login' ? 'login' : 'register'}`, 'POST', {
        email: email.value,
        password: password.value,
        language: getLanguage(),
        voiceEnabled: getVoiceEnabled()
      });
      profile = next;
      onProfileLoaded(next);
      renderAccount();
      window.dispatchEvent(new Event('kiwi-account-change'));
    } catch (error) {
      status.textContent = (error as Error).message || words.error;
      submit.disabled = false;
    }
  };
  const switchMode = document.createElement('button');
  switchMode.type = 'button';
  switchMode.className = 'account-link';
  switchMode.textContent = mode === 'login' ? words.switchRegister : words.switchLogin;
  switchMode.onclick = () => { mode = mode === 'login' ? 'register' : 'login'; renderAccount(); };
  const warning = document.createElement('p');
  warning.className = 'account-warning';
  warning.textContent = words.warning;
  accountRoot.append(guest, form, switchMode, warning);
}

export async function initAccount(root: HTMLElement, language: () => Language, voice: () => boolean,
  onLoaded: (next: AccountProfile) => void) {
  accountRoot = root;
  getLanguage = language;
  getVoiceEnabled = voice;
  onProfileLoaded = onLoaded;
  renderAccount();
  try {
    profile = await accountApi<AccountProfile>('/api/auth/me');
    onProfileLoaded(profile);
    renderAccount();
  } catch { /* guest mode is always usable */ }
}

export async function rememberPreferences(language: Language, voiceEnabled: boolean) {
  if (!profile) return;
  try {
    profile = await accountApi<AccountProfile>('/api/profile', 'PATCH', { language, voiceEnabled });
  } catch { /* do not block navigation when account storage is unavailable */ }
}

export async function rememberDestination(destination: RecentDestination) {
  if (!profile) return;
  try {
    profile = await accountApi<AccountProfile>('/api/profile/destinations', 'POST', destination);
  } catch { /* the route remains usable without persistence */ }
}

export async function savePlace(input: {
  placeId: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  isFavorite: boolean;
  note: string;
}) {
  if (!profile) throw new Error('Sign in to save places');
  profile = await accountApi<AccountProfile>('/api/profile/places', 'POST', input);
  return savedPlace(input.placeId);
}

export async function rememberRoute(input: {
  destinationName: string; latitude: number; longitude: number; mode: string;
  distanceMeters: number | null; durationSeconds: number | null;
}) {
  if (!profile) return;
  profile = await accountApi<AccountProfile>('/api/profile/routes', 'POST', input);
  window.dispatchEvent(new Event('kiwi-account-change'));
}

export async function saveOwnReview(input: {
  placeId: string; placeName: string; rating: number; comment: string;
}) {
  if (!profile) throw new Error('Sign in to save your review');
  profile = await accountApi<AccountProfile>('/api/profile/reviews', 'POST', input);
  window.dispatchEvent(new Event('kiwi-account-change'));
  return ownReview(input.placeId);
}
