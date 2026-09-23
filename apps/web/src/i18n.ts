export type Language = 'en' | 'zh';

const messages = {
  en: {
    title: 'Kiwi Lens · Safer NZ navigation', description: 'NZ fixed safety camera navigation and alerts',
    map: 'New Zealand navigation map', settings: 'Open settings', locating: 'Locating', gpsUnavailable: 'GPS unavailable',
    enableLocation: 'Tap to enable location', permissionDenied: 'Location permission denied', gpsTemporary: 'Location unavailable',
    permissionHelp: 'Allow location for Kiwi Lens in iPhone Settings, then tap GPS again.',
    searchPanel: 'Route search', origin: 'Current location · tap to change', destination: 'Search destination',
    useGps: 'Use live location', searchButton: 'Search destination', follow: 'Follow location', recenter: 'Recenter map',
    noGps: 'Waiting for GPS location.', minQuery: 'Type at least 3 characters.', searching: 'Searching…',
    noResults: 'No NZ address found. Try another search.', searchFailed: 'Search failed',
    routeCalculating: 'Calculating route…', destinationFallback: 'Destination', routeError: 'Route unavailable',
    routeFailed: 'Could not calculate route', chooseOrigin: 'Choose a starting point or allow GPS.',
    turnDefault: 'Continue along the route', arrived: 'Arrive at destination',
    initialTitle: 'Explore New Zealand, drive with confidence', start: 'Start navigation', stop: 'End navigation',
    speedLimit: 'Speed limit', nextCamera: 'Next camera', gpsAccuracy: 'GPS accuracy', routeSteps: 'Route steps',
    camerasAlong: 'Cameras on route', distance: 'Distance', arrival: 'Arrival', dataDetails: 'Data details ↗',
    camerasLoading: 'Loading NZTA cameras…', camerasUnavailable: 'Camera data unavailable',
    cameraCount: 'NZTA fixed cameras', cached: 'cached', neverChecked: 'Not checked yet',
    synced: 'Up to date', stale: 'Official source unavailable; using cache', offline: 'Offline cache', seed: 'Initial CSV',
    drivingStarted: 'Active', drivingStopped: 'Inactive',
    settingsTitle: 'Navigation settings', closeSettings: 'Close settings', language: 'Language',
    languageDescription: 'App and voice alerts', voice: 'Voice guidance', voiceDescription: 'Turns and cameras',
    laneGuidance: 'Recommended lanes', laneGuidanceDescription: 'Show when route data includes lane guidance',
    drivingMode: 'Driving mode', drivingDescription: 'Keep the screen awake and track location in foreground',
    backgroundTitle: 'Background navigation',
    backgroundDescription: 'A PWA may pause GPS and speech when locked or in the background. The future iOS app will use native background location.',
    dataTitle: 'Camera data', closeData: 'Close data details', source: 'Data source',
    sourceUpdated: 'Source updated', lastChecked: 'Last checked', syncStatus: 'Sync status',
    autoSync: 'Automatic sync', autoSyncDescription: 'The server checks NZTA every 6 hours. Validated data is kept if syncing fails. Camera direction and lane data are not provided by NZTA; alerts are advisory.',
    sourceLink: 'View official NZTA list ↗', guestRecent: 'Recent destinations', currentPlace: 'Current location',
    autocompleteUnavailable: 'Live suggestions need a configured address provider. Press Enter to search.'
  },
  zh: {
    title: 'Kiwi Lens · NZ 安全导航', description: '新西兰固定安全摄像头导航提醒',
    map: '新西兰导航地图', settings: '打开设置', locating: '定位中', gpsUnavailable: 'GPS 不可用',
    enableLocation: '点按启用定位', permissionDenied: '定位未授权', gpsTemporary: '定位暂不可用',
    permissionHelp: '请在 iPhone 设置中允许 Kiwi Lens 使用定位，然后再次点按 GPS。',
    searchPanel: '路线搜索', origin: '当前位置 · 点击可改起点', destination: '搜索目的地',
    useGps: '使用实时位置', searchButton: '搜索目的地', follow: '跟随位置', recenter: '回到当前位置',
    noGps: '等待 GPS 定位。', minQuery: '请输入至少 3 个字符。', searching: '搜索中…',
    noResults: '未找到新西兰地址，请换个关键词。', searchFailed: '搜索失败',
    routeCalculating: '正在计算路线…', destinationFallback: '目的地', routeError: '路线暂不可用',
    routeFailed: '路线计算失败', chooseOrigin: '请选择起点，或允许 GPS 定位。',
    turnDefault: '沿路线行驶', arrived: '到达目的地',
    speedLimit: '当前限速', nextCamera: '下一摄像头', gpsAccuracy: 'GPS 精度', routeSteps: '路线步骤',
    initialTitle: '探索新西兰，安心出发', start: '开始导航', stop: '结束导航',
    camerasAlong: '沿途摄像头', distance: '路程', arrival: '预计到达', dataDetails: '数据详情 ↗',
    camerasLoading: '正在加载 NZTA 摄像头…', camerasUnavailable: '摄像头数据暂不可用',
    cameraCount: '个 NZTA 固定摄像头', cached: '缓存', neverChecked: '尚未检查',
    synced: '已同步', stale: '官方连接失败，使用缓存', offline: '离线缓存', seed: '初始 CSV',
    drivingStarted: '已启动', drivingStopped: '未启动',
    settingsTitle: '导航设置', closeSettings: '关闭设置', language: '语言',
    languageDescription: '界面及语音提示', voice: '语音提示', voiceDescription: '转弯及摄像头',
    laneGuidance: '推荐车道', laneGuidanceDescription: '路线数据包含车道信息时显示',
    drivingMode: '驾驶模式', drivingDescription: '保持屏幕唤醒，持续前台定位',
    backgroundTitle: '后台导航说明',
    backgroundDescription: 'PWA 切到后台或锁屏后，浏览器可能暂停 GPS 与语音。后续 iOS 客户端将使用原生后台定位。',
    dataTitle: '摄像头数据', closeData: '关闭数据详情', source: '数据来源',
    sourceUpdated: '官方更新时间', lastChecked: '最近检查', syncStatus: '同步状态',
    autoSync: '自动同步', autoSyncDescription: '服务器每 6 小时检查官方列表。同步失败时保留最近一次经过校验的数据。摄像头方向和车道未在官方列表中提供，提醒仅作辅助。',
    sourceLink: '查看 NZTA 官方列表 ↗', guestRecent: '最近的目的地', currentPlace: '当前位置',
    autocompleteUnavailable: '实时补全需要配置地址服务；按回车仍可搜索。'
  }
} as const;

export type MessageKey = keyof typeof messages.en;
export function t(language: Language, key: MessageKey) { return messages[language][key]; }

function setText(selector: string, value: string) {
  const node = document.querySelector<HTMLElement>(selector);
  if (node) node.textContent = value;
}

function setAttribute(selector: string, attribute: string, value: string) {
  document.querySelector<HTMLElement>(selector)?.setAttribute(attribute, value);
}

export function applyUiLanguage(language: Language) {
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en-NZ';
  document.title = t(language, 'title');
  setAttribute('meta[name="description"]', 'content', t(language, 'description'));
  setAttribute('#map', 'aria-label', t(language, 'map'));
  setAttribute('#settingsButton', 'aria-label', t(language, 'settings'));
  setAttribute('#gpsBadge', 'aria-label', t(language, 'useGps'));
  setAttribute('#gpsBadge', 'title', t(language, 'useGps'));
  setAttribute('#searchPanel', 'aria-label', t(language, 'searchPanel'));
  setAttribute('#originInput', 'placeholder', t(language, 'origin'));
  setAttribute('#originInput', 'aria-label', t(language, 'origin'));
  setAttribute('#destinationInput', 'placeholder', t(language, 'destination'));
  setAttribute('#destinationInput', 'aria-label', t(language, 'destination'));
  for (const [selector, key] of [['#useGpsButton', 'useGps'], ['#searchButton', 'searchButton'],
    ['#followButton', 'follow'], ['#recenterButton', 'recenter'], ['#closeSettings', 'closeSettings'],
    ['#closeData', 'closeData']] as const) {
    setAttribute(selector, 'aria-label', t(language, key));
    setAttribute(selector, 'title', t(language, key));
  }
  setText('.route-stats > div:nth-child(1) span', t(language, 'camerasAlong'));
  setText('.route-stats > div:nth-child(2) span', t(language, 'distance'));
  setText('.route-stats > div:nth-child(3) span', t(language, 'arrival'));
  setText('#dataButton', t(language, 'dataDetails'));
  setText('#settingsTitle', t(language, 'settingsTitle'));
  setText('#settingsOverlay .setting-row:nth-child(2) strong', t(language, 'language'));
  setText('.trip-detail-grid > div:nth-child(1) span', t(language, 'speedLimit'));
  setText('.trip-detail-grid > div:nth-child(2) span', t(language, 'nextCamera'));
  setText('.trip-detail-grid > div:nth-child(3) span', t(language, 'gpsAccuracy'));
  setText('.trip-detail-grid > div:nth-child(4) span', t(language, 'routeSteps'));
  setText('#settingsOverlay .setting-row:nth-child(2) small', t(language, 'languageDescription'));
  setText('#settingsOverlay .setting-row:nth-child(3) strong', t(language, 'voice'));
  setText('#settingsOverlay .setting-row:nth-child(3) small', t(language, 'voiceDescription'));
  setText('#laneSettingTitle', t(language, 'laneGuidance'));
  setText('#laneSettingDescription', t(language, 'laneGuidanceDescription'));
  setText('#settingsOverlay .setting-row:nth-child(5) strong', t(language, 'drivingMode'));
  setText('#settingsOverlay .setting-row:nth-child(5) small', t(language, 'drivingDescription'));
  setText('#settingsOverlay .info-card strong', t(language, 'backgroundTitle'));
  setText('#settingsOverlay .info-card p', t(language, 'backgroundDescription'));
  setText('#dataTitle', t(language, 'dataTitle'));
  setText('#dataOverlay .data-detail:nth-child(2) span', t(language, 'source'));
  setText('#dataOverlay .data-detail:nth-child(3) span', t(language, 'sourceUpdated'));
  setText('#dataOverlay .data-detail:nth-child(4) span', t(language, 'lastChecked'));
  setText('#dataOverlay .data-detail:nth-child(5) span', t(language, 'syncStatus'));
  setText('#dataOverlay .info-card strong', t(language, 'autoSync'));
  setText('#dataOverlay .info-card p', t(language, 'autoSyncDescription'));
  setText('#dataOverlay .source-link', t(language, 'sourceLink'));
}
