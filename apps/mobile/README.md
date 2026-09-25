# Kiwi Lens Mobile

Kiwi Lens 的原生移动端使用 Flutter，支持在设置中切换 Google Maps 与 Mapbox 地图。Google 原生导航流程保留，Mapbox 浏览与路线使用独立适配器；详细边界和剩余验证见 [MAP_PROVIDERS.md](MAP_PROVIDERS.md)。

- `google_navigation_flutter`：地图浏览、POI 点击、路线与 turn-by-turn 导航
- `mapbox_maps_flutter`：第二地图渲染器、地点选择与 Kiwi Lens 覆盖物
- Cloudflare Worker `https://kiwi-lens.nzs.workers.dev`：地址自动补全、摄像头及限速 API
- iOS Core Location：手机顶部罗盘朝向；地图与 500 米雷达扇区跟随该方向，GPS course 仅为无罗盘时的行驶中回退
- 自定义 Flutter 导航顶栏、速度/摄像头浮层和紧凑行程卡；Google Navigation SDK 保留真实路线与转弯数据

## 当前里程碑

第一版先把地图最核心的交互做实：

1. 浏览 Google 或 Mapbox 地图
2. 通过搜索、Explore、收藏、最近地点、快捷地点、地图 POI 或长按坐标选择目的地
3. 显示统一 Kiwi Lens 地点预览；点击 Directions 才进入路线预览
4. 在路线预览中选择模式/备选路线；点击 Start 才开始导航
5. Google 路线继续使用 Google Navigation SDK；Mapbox 路线使用 GPS 与路线步骤提供基础引导

搜索页支持自动补全、地址完整展示与最近搜索；Explore 以新西兰道路出行相关地点为主。Google POI 的照片、评分、营业时间尚未接入原生地点卡；路线摄像头总数也尚未从原生导航路线中取得，因此显示 `—`。Mapbox 的原生重算路线、车道引导与沿途绕行时间尚未接入，界面不会编造这些数值。iOS 真机的罗盘与地图叠加层仍需用 Xcode 实测；iOS Simulator 没有磁力计。

## 本地 Flutter

推荐从仓库根目录使用 pnpm 统一触发 Flutter 开发任务。Flutter/Dart 自身依赖仍由 `flutter pub` 管理，这是 Flutter 官方机制；pnpm 负责整个 monorepo 的安装入口、脚本编排与 CI。

```bash
corepack enable
pnpm install
pnpm mobile:doctor
pnpm mobile:dev
```

`pnpm mobile:dev` 和 `pnpm mobile:run` 都会自动执行 `flutter pub get` 并选择可用的移动设备。在 macOS 上会自动启用 Flutter Swift Package Manager，优先使用已连接的 iPhone 或已启动的 iOS Simulator；如果没有运行中的 iOS 设备，会尝试自动启动可用的 iPhone Simulator。其他平台优先使用 Android 设备/模拟器，没有运行中的 Android 设备时会从 `flutter emulators` 列表中启动 AVD。

在 macOS/iOS 上启动器会为 `flutter run` 自动添加 `--no-dds`。Flutter 3.47 的 iOS Simulator 偶尔会在 Xcode 已成功编译后，因本机 Dart Development Service WebSocket 代理连接失败而退出；直接连接 VM Service 可以绕过这一层，同时保留普通开发运行和 hot reload。`flutter_tts` 当前出现的 Swift Package Manager compatibility 提示只是 warning，Flutter 仍会通过 CocoaPods 集成它。

### iPhone 真机开发与 Release 安装

连接 iPhone、解锁并信任 Mac，开启 iPhone Developer Mode。第一次还需要在 Xcode 中打开 `ios/Runner.xcworkspace`，在 **Runner → Signing & Capabilities** 勾选 Automatically manage signing，并选择自己的 Apple ID Personal Team。这个签名选择只需要配置一次。

之后从仓库根目录可以直接使用：

```bash
# 真机 Debug，保留 hot reload
pnpm mobile:ios

# 构建 Release 并直接覆盖安装到已连接的 iPhone
pnpm mobile:ios:install

# 需要分发包时生成 IPA
pnpm mobile:ios:ipa
```

`mobile:ios:install` 会执行 signed Release build，然后使用 Xcode `devicectl` 将 `build/ios/iphoneos/Runner.app` 安装到物理 iPhone，并尝试自动启动 Kiwi Lens。它不会调用 Flutter 的 `flutter install`，因为 Flutter install 会主动卸载旧 App；这里采用覆盖安装流程，更适合持续真机测试并尽量保留设备上的 App 数据。

免费 Personal Team 可以用于自己的 iPhone 开发安装，但 provisioning 有效期较短，需要定期重新签名安装。IPA 的正式分发/TestFlight 则通常需要 Apple Developer Program。

可以手动查看环境：

```bash
pnpm mobile:devices
pnpm mobile:emulators
```

如果没有可用模拟器，请先在 Android Studio → Device Manager 创建一个 Android Virtual Device。Flutter 与 Android SDK 必须安装在执行上述 pnpm 命令的同一环境可访问的位置。

推荐开发环境为 WSL2 或原生 Windows/macOS；如果使用 WSL2，项目与 SDK 可放在 Linux 文件系统：

```text
repo:    ~/work/kiwi-lens
Flutter: ~/flutter
Android: ~/Android/Sdk
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
flutter.sdk=/home/samyao/flutter
sdk.dir=/home/samyao/Android/Sdk
MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY
```

生产 Key 应限制到 Android application：

```text
package: me.samyao.kiwilens
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
me.samyao.kiwilens
```

`Secrets.xcconfig` 已被 Git 忽略。

### Google 登录

Google 登录需要在同一 Google Cloud 项目的 Auth Platform 中创建两个 OAuth 2.0 客户端：

1. **iOS 客户端**：Bundle ID 使用 `me.samyao.kiwilens`。复制 Client ID，并按 Google 提供的 reversed client ID 填写 URL scheme。
2. **Web application 客户端**：作为服务端 ID token 的 audience。这里不需要将 client secret 放入移动端或仓库。

仓库中的 `Secrets.xcconfig.example` 已填入 Kiwi Lens 的三个公开 OAuth 标识；复制为被 Git 忽略的 `Secrets.xcconfig` 后，只需再填写 Maps API Key。若将来更换 OAuth 客户端，iOS Client ID、Web/Server Client ID 和 reversed URL scheme 必须同步更新。

Cloudflare Worker 的 `GOOGLE_OAUTH_CLIENT_IDS` 已配置为当前 Web 与 iOS Client ID，D1 迁移 `0004_google_identity.sql` 已应用。更换客户端时也需同步更新 Worker binding。Worker 会验证 Google ID token 的签名、发行方、有效期、邮箱验证状态和 audience；请勿填写或提交 OAuth client secret。

首次登录的 Google 身份会创建 Kiwi Lens 账户；已经用邮箱密码注册的账户，需要先用密码登录，再在“我的”页面显式关联同邮箱 Google 账户，不会仅凭邮箱自动合并。iOS 上正式上架前，还要确认 Apple 的第三方登录审核要求，并按需提供 Sign in with Apple。

#### 自己的 iPhone 免费安装

WSL 可以完成代码开发、测试和 Android 构建，但 iOS 最终编译、签名和安装必须在 macOS + Xcode 上完成。测试自己的 iPhone 不要求先加入付费 Apple Developer Program；可以在 Xcode 登录普通 Apple Account，并使用自动生成的 Personal Team 做开发签名。

Mac 上的典型流程：

```bash
git clone git@github.com:yaohuangguan/kiwi-lens.git
cd kiwi-lens
corepack enable
pnpm install
flutter config --enable-swift-package-manager
pnpm mobile:get
cd apps/mobile
cp ios/Flutter/Secrets.xcconfig.example ios/Flutter/Secrets.xcconfig
# 填写 MAPS_API_KEY
open ios/Runner.xcodeproj
```

然后在 Xcode 的 Signing & Capabilities 中选择自己的 Personal Team，连接并信任 iPhone，开启 Developer Mode 后直接 Run。免费 Personal Team 的 provisioning 会过期，需要定期重新签名安装；这是自用测试方案，不是 App Store/TestFlight 分发方案。

## Cloud Map Style

如果创建了 Google Cloud Map ID，可以启动时传：

```bash
cd apps/mobile
flutter run --dart-define=MAP_ID=YOUR_MAP_ID
```

没有 Map ID 时使用 Google 默认地图样式。

## Drive Mode 架构

Google Navigation SDK 只负责导航底层能力，Kiwi Lens 自己拥有驾驶产品逻辑：

```text
Google Navigation SDK
        ↓
DriveEngine
├─ road-snapped location
├─ NavInfo / ETA / route changes
├─ speeding events
├─ CameraMatcher
├─ VoiceEngine
└─ system speed stream
        ↓
Kiwi Lens Drive HUD
```

当前 Drive Mode 即使没有设置目的地也可以启动。它会加载 Cloudflare `/api/cameras`，根据 road-snapped 行驶轨迹推导前进方向，筛选前方安全摄像头，并在约 800 m 和 300 m 触发 Kiwi Lens 自己的 UI + TTS 提醒。设置目的地后，同一套 DriveEngine 会继续消费 Google NavInfo，显示转弯、剩余距离和可用的推荐车道。

摄像头数据目前没有执法方向，因此 Free Drive 的匹配策略刻意保守：优先前进方向锥形范围内的摄像头，避免侧路或身后的明显误报。真实驾驶测试后再调提醒距离与 heading 阈值。

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
