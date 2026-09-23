# Kiwi Lens

## About

Kiwi Lens is a New Zealand-focused navigation and road-safety project that combines route guidance with fixed safety-camera awareness. It uses Google Maps for places and traffic-aware routing, NZTA camera data for safety alerts, and a focused navigation UI designed to keep route instructions, ETA, speed, upcoming turns, and relevant camera warnings visible without covering the map.

The project is built as a reusable full-stack monorepo: a Vite PWA and Cloudflare Worker power the web experience, shared core packages handle route/camera matching, and a Flutter mobile client provides a path toward native background navigation on Android and iOS.

面向新西兰驾驶者的固定安全摄像头导航。第一期为可安装的 PWA，由 Cloudflare Worker 在同一域名提供网页和 API；后续 Flutter Android/iOS 客户端可复用 API 契约。

## Monorepo

```text
apps/
  web/       Vite PWA + Google Maps JavaScript / Places / Routes
  server/    Cloudflare Worker：摄像头同步、账号、地址搜索与 lane enrichment API
  mobile/    Flutter Android/iOS + Google Navigation SDK
packages/
  core/      Web 路线投影、摄像头匹配与距离算法
  contracts/ HTTP API 契约，供移动端复用
scripts/     NZTA CSV 初始数据导入
```

## 本地运行

推荐在 WSL/Linux 文件系统运行，当前开发仓库位于 `~/work/kiwi-lens`。需要 Node.js 20+；运行 `npm install` 和 `npm run dev`，打开 `http://localhost:5173`。Vite 将 `/api` 代理到本地 Worker `http://localhost:8787`；Worker 也直接提供已打包的 PWA。首次使用请允许定位；没有 GPS 时可搜索起点和目的地。搜索与规划路线需要网络。

Web Google Maps 配置复制 `apps/web/.env.example` 到 `apps/web/.env.local`，填写 `VITE_GOOGLE_MAPS_API_KEY`。浏览器 API Key 会出现在客户端，这是 Google Maps Web 的正常工作方式，因此必须在 Google Cloud 中限制 **HTTP referrer**，并只允许项目实际使用的 Maps JavaScript / Places / Routes 能力。可选配置 `VITE_GOOGLE_MAP_ID`；未配置时开发阶段使用 `DEMO_MAP_ID`。

当前生产 Worker/PWA 地址是 `https://kiwi-lens.nzs.workers.dev`。同域部署时保持 `VITE_API_BASE_URL` 为空；其他域名托管的 Web 前端才指向这个 Worker。Google Maps 的 `RefererNotAllowedMapError` 不是 Worker CORS：请在 Google Cloud Console 的 **网页 API Key → Application restrictions → Websites** 添加 `https://kiwi-lens.nzs.workers.dev/*`（本地开发另加 `http://localhost:5173/*`），并启用 Maps JavaScript API、Places API、Routes API 与 Billing。不要取消 Key 限制。iOS Navigation SDK 使用独立的 iOS bundle ID 限制 Key。

地址补全等公开 GET API 支持跨域读取；账号登录/资料仍要求与 Worker 同域，以维持 SameSite cookie 和 CSRF 保护。更换 Worker 域名后请从新地址安装 PWA，旧域名的 Service Worker 不会自动迁移。


运行 `npm test` 执行算法、解析器和 Worker API 测试；`npm run build` 包含网页构建与 Worker dry-run 打包。

`apps/server/data/cameras.json` 已从用户提供的 NZTA CSV 导入 125 条记录，源更新时间为 2026-08-26。重新导入 CSV：

```bash
npm run data:import -- "path/to/NZTA_Fixed_Safety_Cameras.csv"
```

## NZTA 数据更新

Cloudflare Cron 每 6 小时检查 [NZTA 固定安全摄像头列表](https://www.nzta.govt.nz/travelling-on-our-roads/safety-cameras/about-safety-cameras/fixed-safety-camera-locations)，将验证后的快照写入 Workers KV。KV 为空时会立即提供已导入的 CSV 数据，并在首次读取时后台尝试同步。只有解析到官方更新时间、50–1000 条有效新西兰坐标，且日期不早于当前快照时，才会替换数据；否则保留原快照并记录错误。PWA 启动时及每 15 分钟重新拉取数据，也在设备上保留最近一次成功读取的缓存。

NZTA 当前公开的是网页列表，不是摄像头变更推送，所以这不是秒级实时更新。在页面可访问的前提下，官方发布后通常在下一次 6 小时检查时同步；若页面被反爬验证拦截，会显示缓存状态。Workers KV 的跨地区传播也不是瞬时。若 NZTA 将来提供稳定数据 API，应将 `apps/server/src/sync.mjs` 改用该 API。

## Cloudflare 部署

当前推荐生产架构是 **Cloudflare Workers full-stack SPA**：一次部署同时发布 `apps/web/dist` 静态资源和 `/api/*` Worker API。账号与会话使用 D1，摄像头缓存使用 Workers KV。

首次部署：

```bash
npm install
npx wrangler login
npx wrangler whoami
npm run db:migrate:remote
npm run deploy
```

本地开发首次使用账号功能前执行：

```bash
npm run db:migrate:local
```

部署完成后测试：

```bash
curl https://<your-worker>.workers.dev/api/health
```

应返回 `ok: true` 和摄像头数量。Cron 使用 UTC 时间，每 6 小时触发一次。可在 Cloudflare Dashboard → Workers & Pages → kiwi-lens 查看 Logs、Triggers、Bindings 和 D1 数据库。

如果 Wrangler 没有自动创建 `CAMERA_DATA` KV，手动执行：

```bash
npx wrangler kv namespace create CAMERA_DATA
```

然后把返回的 namespace ID 填入 `wrangler.jsonc`。本地 `wrangler dev` 使用本地 KV/D1，与线上数据分离。

### 可选：Web 单独部署到 Vercel

`apps/web` 本身是 Vite SPA，可以单独部署到 Vercel，但它仍依赖 Cloudflare Worker API。推荐生产环境仍使用 Cloudflare 同域方案。

如果需要 Vercel Preview：

1. Vercel Root Directory 设为 `apps/web`。
2. Build Command 使用 `npm run build`，Output Directory 使用 `dist`。
3. 增加环境变量 `VITE_API_BASE_URL=https://<your-worker>.workers.dev`。
4. Worker API 允许跨域 GET 请求。

不设置 `VITE_API_BASE_URL` 时，Web 默认使用同域 `/api/*`，适用于 Cloudflare full-stack 部署。

## 导航能力与限制

- 浏览器前台 Geolocation 实时跟随位置，使用 Screen Wake Lock 尽可能保持屏幕唤醒。
- PWA 底图与可点击 POI 使用 Google Maps JavaScript API；点击 Google POI 会读取 Place ID、名称、地址并显示 Kiwi Lens 地点卡片，可直接设为导航目的地。
- PWA 主路线使用 Google Maps JavaScript Routes library 的 traffic-aware driving route；Kiwi Lens 自己负责路线进度、转弯 HUD、ETA、实时车速、reroute 和语音。现有 Worker/OSRM 路线仅作为可选 lane enrichment：能匹配到同一转弯时补充推荐车道，没有可靠 lane 数据就不显示。
- 地址文字搜索目前仍通过 Worker/Nominatim，并可选使用 Geoapify 实时补全；地图 POI 与路线已经由 Google 提供，后续可再将搜索统一切到 Google Places Autocomplete。
- 摄像头沿 Google 路线投影，并结合道路名和路线中心线距离筛选。路线上的摄像头高亮；仅对高可信匹配自动语音提示 800 米和 300 米，持续更新距离。GPS 的 `coords.speed` 直接驱动 Kiwi Lens 时速 HUD。
- NZTA CSV 没有车道或执法朝向字段。相邻道路误报可降低，但同一路面反方向摄像头不能可靠区分；驾驶者始终应以现场标志和法规为准。
- PWA 进入后台或锁屏后，浏览器可能停止 GPS 与语音。持续后台导航需要 `apps/mobile` 的 Flutter 客户端配合 iOS/Android 原生后台定位能力。
- Nominatim/Geoapify 与 OSRM 目前只承担搜索 fallback / lane enrichment；正式运营前仍需确认容量与服务条款。Google Maps Platform 需要启用计费并对 Web 与原生 API Key 分别做平台和 API 限制。

## API

本地 Worker 默认监听 `http://localhost:8787`，生产环境同域提供 PWA 与 API。字段见 [OpenAPI 契约](packages/contracts/openapi.yaml)。

- `GET /api/health`：服务状态与摄像头数量
- `GET /api/cameras`：完整摄像头数据、更新时间和同步状态
- `GET /api/search?q=Auckland`：新西兰地址搜索
- `GET /api/route?from=174.76,-36.85&to=174.78,-36.90`：驾车路线几何线及逐向步骤

## 隐私

GPS 在设备浏览器中用于导航与匹配提醒。路线起终点会发给本项目 Worker 和路线服务；搜索文字会发给地址服务。Worker 不记录用户位置历史。浏览器仅缓存摄像头数据和语言/语音偏好。
