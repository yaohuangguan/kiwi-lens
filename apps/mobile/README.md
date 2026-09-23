# Kiwi Lens Mobile

Kiwi Lens 的原生移动端使用 Flutter，当前主地图与导航栈为 Google Maps Platform：

- `google_navigation_flutter`：地图浏览、POI 点击、路线与 turn-by-turn 导航
- Google Places：下一步用于搜索、地点详情、评分、营业时间和照片
- Cloudflare Worker：复用现有 Kiwi Lens 摄像头、账号及自有数据 API
- Flutter UI + 必要时原生扩展：相机采集、后台定位、CarPlay / Android Auto 等能力按需下沉

## 当前里程碑

第一版先把地图最核心的交互做实：

1. 浏览 Google 地图
2. 点击地图上的真实 POI
3. 从 Google POI 获取 Place ID、名称和坐标
4. 显示 Kiwi Lens 地点卡片
5. 点击 Navigate 后以 Place ID 设置目的地
6. 进入 Google Navigation SDK 的 turn-by-turn 导航

不会在主界面放没有功能的假搜索框或假按钮。搜索和完整地点卡片会在 Places API 接入后加入。

## 本地 Flutter

开发机当前 Flutter SDK：

```text
E:\SDK\flutter
```

当前版本：

```text
Flutter 3.47.5
Dart 3.13.4
```

## 平台要求

- Android API 24+
- iOS 16+
- Google Maps Platform 已启用 Billing
- 启用对应平台的 Navigation SDK / Maps SDK

## Google Maps API Key

API Key 不提交到 Git。

### Android

在 `android/local.properties` 中保留 Flutter SDK，并加入：

```properties
flutter.sdk=E:\\SDK\\flutter
MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY
```

生产 Key 应限制到 Android application：

```text
package: space.ps6.kiwilens
SHA-1: <release signing certificate SHA-1>
```

### iOS

复制：

```bash
cp ios/Flutter/Secrets.xcconfig.example ios/Flutter/Secrets.xcconfig
```

填写：

```text
MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY
```

Bundle ID：

```text
space.ps6.kiwilens
```

`Secrets.xcconfig` 已被 Git 忽略。

## Cloud Map Style

如果创建了 Google Cloud Map ID，可以启动时传：

```bash
flutter run --dart-define=MAP_ID=YOUR_MAP_ID
```

没有 Map ID 时使用 Google 默认地图样式。

## 下一步

- Places 搜索与地点详情
- Google Places 照片 / 营业时间 / 评分
- Kiwi Lens 摄像头 overlay
- 驾驶 HUD：速度、限速、摄像头距离、推荐车道
- 后台导航与语音
- 相机自动采集 / DriveSession
- CarPlay / Android Auto
- Kiwi Lens 自有地图样式

PWA 继续作为快速试驾版本，原生端与 PWA 共用 Cloudflare 后端，但导航能力逐步迁移到 Google Navigation SDK。
