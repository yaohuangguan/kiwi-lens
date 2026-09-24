import { currentProfile, type Language } from './account';

function element(tag: string, className: string, content?: string) {
  const node = document.createElement(tag);
  node.className = className;
  if (content !== undefined) node.textContent = content;
  return node;
}

export function renderProfileView(root: HTMLElement, language: Language, openSignIn: () => void) {
  root.replaceChildren();
  const profile = currentProfile();
  if (!profile) {
    root.append(element('p', 'profile-empty', language === 'zh'
      ? '访客可直接使用导航。登录后可在这里同步行程、收藏和自己的评价。'
      : 'Navigation works as a guest. Sign in to sync trips, favorites and your own reviews.'));
    const button = element('button', 'account-button', language === 'zh' ? '登录或注册' : 'Sign in or register');
    button.onclick = openSignIn;
    root.append(button);
    return;
  }

  root.append(element('p', 'profile-email', profile.user.email));
  const stats = element('div', 'profile-stats');
  for (const [number, label] of [
    [profile.routeHistory?.length || 0, language === 'zh' ? '次导航' : 'Trips'],
    [profile.savedPlaces?.filter((place) => place.isFavorite).length || 0, language === 'zh' ? '个收藏' : 'Favorites'],
    [profile.reviews?.length || 0, language === 'zh' ? '条评价' : 'Reviews']
  ] as const) {
    const stat = element('div', 'profile-stat');
    stat.append(element('strong', '', String(number)), element('span', '', label));
    stats.append(stat);
  }
  root.append(stats);

  const section = (title: string, empty: string) => {
    const block = element('section', 'profile-section');
    block.append(element('h3', '', title));
    root.append(block);
    return { block, empty: () => block.append(element('p', 'profile-empty', empty)) };
  };
  const trips = section(language === 'zh' ? '最近导航' : 'Recent navigation',
    language === 'zh' ? '还没有导航记录。' : 'No trips recorded yet.');
  if (!profile.routeHistory?.length) trips.empty();
  for (const trip of profile.routeHistory || []) {
    const row = element('article', 'profile-item');
    row.append(element('strong', '', trip.destinationName));
    const distance = trip.distanceMeters == null ? '' : ` · ${(trip.distanceMeters / 1000).toFixed(1)} km`;
    row.append(element('small', '', `${trip.mode}${distance} · ${new Date(trip.startedAt).toLocaleString(language === 'zh' ? 'zh-NZ' : 'en-NZ')}`));
    trips.block.append(row);
  }

  const favorites = section(language === 'zh' ? '收藏地点与备注' : 'Favorite places and notes',
    language === 'zh' ? '还没有收藏地点。' : 'No saved places yet.');
  if (!profile.savedPlaces?.length) favorites.empty();
  for (const place of profile.savedPlaces || []) {
    const row = element('article', 'profile-item');
    row.append(element('strong', '', `${place.isFavorite ? '♥ ' : ''}${place.name}`));
    if (place.address) row.append(element('small', '', place.address));
    if (place.note) row.append(element('p', '', place.note));
    favorites.block.append(row);
  }

  const reviews = section(language === 'zh' ? '我的评价' : 'My reviews',
    language === 'zh' ? '还没有评价。打开地点卡片即可撰写。' : 'No reviews yet. Open a place card to write one.');
  if (!profile.reviews?.length) reviews.empty();
  for (const review of profile.reviews || []) {
    const row = element('article', 'profile-item');
    row.append(element('strong', '', `${review.placeName} · ${'★'.repeat(review.rating)}`));
    if (review.comment) row.append(element('p', '', review.comment));
    row.append(element('small', '', new Date(review.updatedAt).toLocaleDateString(language === 'zh' ? 'zh-NZ' : 'en-NZ')));
    reviews.block.append(row);
  }
}
