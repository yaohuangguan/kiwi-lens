# Kiwi Lens

面向新西兰驾驶者的固定安全摄像头导航。第一期是可安装 PWA；后续 Flutter App 使用同一套 server API 和数据契约。

## 目录

```text
apps/
  web/       Vite + Leaflet PWA
  server/    摄像头同步、地址搜索和驾车路线 API
  mobile/    Flutter 接入说明（下一期）
packages/
  core/      Web 路线投影、摄像头匹配与距离算法
  contracts/ HTTP API 契约，供 Flutter 复用
scripts/     NZTA CSV 初始数据导入
```

## 本地启动

需要 Node.js 20+。

```bash
npm install
npm run dev
```

打开 `http://localhost:5173`。首次使用请允许定位；如果电脑没有 GPS，可以在起点和目的地输入框分别搜索地址。新路线与搜索需要网络。

```bash
npm test
npm run build
```

`apps/server/data/cameras.json` 已从用户提供的 NZTA CSV 导入 125 条记录，源更新时间为 2026-08-26。要重新导入 CSV：

```bash
npm run data:import -- "path/to/NZTA_Fixed_Safety_Cameras.csv"
```

## 自动数据更新

Server 启动时和之后每 6 小时检查 [NZTA 固定安全摄像头列表](https://www.nzta.govt.nz/travelling-on-our-roads/safety-cameras/about-safety-cameras/fixed-safety-camera-locations)。只有解析出官方更新时间和 50–1000 条有效新西兰坐标时才替换内存中的数据；否则继续提供已经验证的初始 CSV。PWA 启动时及每 15 分钟重新拉取 server 数据，并在设备上保留最近一次成功读取的缓存。数据详情面板显示官方更新时间、最近检查时间及同步状态。

NZTA 目前公布的是网页列表，不是摄像头位置的实时推送接口。因此更新频率是“官方发布后最多约 6 小时同步”，取决于官方页面可访问性；被反爬验证挡住时会显示缓存状态。部署时需要持续运行 server，单独部署静态 PWA 不会自动同步。未来如 NZTA 提供稳定数据 API，应将 `apps/server/src/sync.mjs` 切换为该 API。

## 导航能力与限制

- 前台使用浏览器 Geolocation 实时跟随位置，并使用 Screen Wake Lock 尽可能保持驾驶时屏幕唤醒。
- 地址搜索经 server 代理到 OpenStreetMap Nominatim；仅在用户提交搜索时请求。
- 路线和转弯步骤经 server 代理到 OSRM；地图使用 OpenStreetMap 图块。
- 沿路线投影摄像头，结合道路名称和距路线中心线的距离筛选。路线上的摄像头高亮；只有高可信匹配自动语音提示 800 米和 300 米，并持续更新距离。
- CSV 没有车道或执法朝向字段。相邻道路可通过道路名与路线走廊降低误报，但同一路面的反方向摄像头无法可靠区分；驾驶者始终应以现场标志和法规为准。
- PWA 进入后台或锁屏后，浏览器可能停止 GPS 与语音。真正的后台导航要在 `apps/mobile` 用 Flutter 原生后台定位与前台服务实现。
- 公共 Nominatim、OSRM 和 OSM 图块服务仅适合开发与小规模试用；正式公开运营须换成遵循服务条款的自有或商业服务，并配置限流、监控与可用性保障。

## API

Server 默认监听 `http://localhost:8787`，Vite 把 `/api` 代理给它。完整字段见 [OpenAPI 契约](packages/contracts/openapi.yaml)。

- `GET /api/health`：服务状态与摄像头数量
- `GET /api/cameras`：完整摄像头数据、更新时间、同步状态
- `GET /api/search?q=Auckland`：新西兰地址搜索
- `GET /api/route?from=174.76,-36.85&to=174.78,-36.90`：驾车路线几何线和逐向步骤

## 隐私

GPS 在浏览器中用于导航与匹配提醒。路线起终点会发给本项目 server 和路线服务；搜索文字会发给地址服务。Server 不记录用户位置历史。浏览器仅缓存摄像头数据和语言/语音偏好。
