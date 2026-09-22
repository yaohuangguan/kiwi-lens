# Kiwi Lens

面向新西兰驾驶者的固定安全摄像头导航。第一期为可安装的 PWA，由 Cloudflare Worker 在同一域名提供网页和 API；后续 iOS 客户端可复用 API 契约。

## Monorepo

```text
apps/
  web/       Vite + Leaflet PWA
  server/    Cloudflare Worker：摄像头同步、地址搜索、驾车路线 API
  mobile/    iOS 客户端预留目录
packages/
  core/      Web 路线投影、摄像头匹配与距离算法
  contracts/ HTTP API 契约，供移动端复用
scripts/     NZTA CSV 初始数据导入
```

## 本地运行

需要 Node.js 20+。运行 `npm install` 和 `npm run dev`，打开 `http://localhost:5173`。Vite 将 `/api` 代理到本地 Worker `http://localhost:8787`；Worker 也直接提供已打包的 PWA。首次使用请允许定位；没有 GPS 时可搜索起点和目的地。搜索与规划路线需要网络。

运行 `npm test` 执行算法、解析器和 Worker API 测试；`npm run build` 包含网页构建与 Worker dry-run 打包。

`apps/server/data/cameras.json` 已从用户提供的 NZTA CSV 导入 125 条记录，源更新时间为 2026-08-26。重新导入 CSV：

```bash
npm run data:import -- "path/to/NZTA_Fixed_Safety_Cameras.csv"
```

## NZTA 数据更新

Cloudflare Cron 每 6 小时检查 [NZTA 固定安全摄像头列表](https://www.nzta.govt.nz/travelling-on-our-roads/safety-cameras/about-safety-cameras/fixed-safety-camera-locations)，将验证后的快照写入 Workers KV。KV 为空时会立即提供已导入的 CSV 数据，并在首次读取时后台尝试同步。只有解析到官方更新时间、50–1000 条有效新西兰坐标，且日期不早于当前快照时，才会替换数据；否则保留原快照并记录错误。PWA 启动时及每 15 分钟重新拉取数据，也在设备上保留最近一次成功读取的缓存。

NZTA 当前公开的是网页列表，不是摄像头变更推送，所以这不是秒级实时更新。在页面可访问的前提下，官方发布后通常在下一次 6 小时检查时同步；若页面被反爬验证拦截，会显示缓存状态。Workers KV 的跨地区传播也不是瞬时。若 NZTA 将来提供稳定数据 API，应将 `apps/server/src/sync.mjs` 改用该 API。

## Cloudflare 部署

当前推荐生产架构是 **Cloudflare Workers full-stack SPA**：一次部署同时发布 `apps/web/dist` 静态资源和 `/api/*` Worker API。Cloudflare 官方 Static Assets 支持这种 SPA + Worker API 的同域部署方式。

首次部署：

```bash
npm install
npx wrangler login
npx wrangler whoami
npm run deploy
```

项目使用 Wrangler 4 的资源自动 provision；`CAMERA_DATA` 只有 binding、没有固定 `id` 时，真实 `wrangler deploy` 会尝试为草稿 binding 自动创建 KV。部署完成后测试：

```bash
curl https://<your-worker>.workers.dev/api/health
```

应返回 `ok: true` 和摄像头数量。Cron 使用 UTC 时间，每 6 小时触发一次。可在 Cloudflare Dashboard → Workers & Pages → kiwi-lens 查看 Logs、Triggers 和 Bindings。

如果你的 Wrangler/账号环境没有自动创建 KV，手动执行：

```bash
npx wrangler kv namespace create CAMERA_DATA
```

命令会输出 namespace ID。把该 ID 填入 `wrangler.jsonc`：

```json
"kv_namespaces": [
  { "binding": "CAMERA_DATA", "id": "<输出的 namespace id>" }
]
```

然后再次运行 `npm run deploy`。

注意：`npm run build` 现在只构建共享 core 和 Web；它不会再在首次部署前执行 Worker dry-run。需要单独检查 Worker 打包时运行 `npm run check:worker`。本地 `wrangler dev` 使用本地 KV，与线上数据分离。

### 可选：Web 单独部署到 Vercel

`apps/web` 本身是 Vite SPA，可以单独部署到 Vercel，但它仍依赖 Cloudflare Worker API。推荐生产环境仍使用上面的 Cloudflare 同域方案。

如果需要 Vercel Preview：

1. Vercel Root Directory 设为 `apps/web`。
2. Build Command 使用 `npm run build`，Output Directory 使用 `dist`。
3. 增加环境变量 `VITE_API_BASE_URL=https://<your-worker>.workers.dev`。
4. Worker API 已允许跨域 GET 请求。

不设置 `VITE_API_BASE_URL` 时，Web 默认使用同域 `/api/*`，适用于 Cloudflare full-stack 部署。

## 导航能力与限制

- 浏览器前台 Geolocation 实时跟随位置，使用 Screen Wake Lock 尽可能保持屏幕唤醒。
- 地址搜索通过 Worker 代理到 OpenStreetMap Nominatim；仅用户提交搜索时请求。路线和转弯步骤通过 Worker 代理到 OSRM，底图使用 OpenStreetMap 图块。
- 摄像头沿路线投影，并结合道路名和路线中心线距离筛选。路线上的摄像头高亮；仅对高可信匹配自动语音提示 800 米和 300 米，持续更新距离。
- NZTA CSV 没有车道或执法朝向字段。相邻道路误报可降低，但同一路面反方向摄像头不能可靠区分；驾驶者始终应以现场标志和法规为准。
- PWA 进入后台或锁屏后，浏览器可能停止 GPS 与语音。持续后台导航需要 `apps/mobile` 的 iOS 原生后台定位能力。
- 公共 Nominatim、OSRM 和 OSM 图块服务仅适合开发及小规模试用。正式运营前须换成符合服务条款且具有容量保障的服务，并配置限流、监控与可用性保障。

## API

本地 Worker 默认监听 `http://localhost:8787`，生产环境同域提供 PWA 与 API。字段见 [OpenAPI 契约](packages/contracts/openapi.yaml)。

- `GET /api/health`：服务状态与摄像头数量
- `GET /api/cameras`：完整摄像头数据、更新时间和同步状态
- `GET /api/search?q=Auckland`：新西兰地址搜索
- `GET /api/route?from=174.76,-36.85&to=174.78,-36.90`：驾车路线几何线及逐向步骤

## 隐私

GPS 在设备浏览器中用于导航与匹配提醒。路线起终点会发给本项目 Worker 和路线服务；搜索文字会发给地址服务。Worker 不记录用户位置历史。浏览器仅缓存摄像头数据和语言/语音偏好。
