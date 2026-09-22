# iOS 客户端（下一期）

本目录保留移动端位置。目标目前以 iOS 为主，且后台连续定位、路线摄像头提醒和语音播报是核心功能，因此建议优先采用 SwiftUI + Core Location + MapKit + AVSpeechSynthesizer。Flutter 也能开发 iOS 界面，但这些后台能力仍需按 Apple 的规则配置，并可能需要编写 Swift 平台代码。技术选型由产品决定后再创建工程，避免先生成用不到的空工程。

移动端将复用 `../../packages/contracts/openapi.yaml` 的 `/api/cameras`、`/api/search` 和 `/api/route`。`../../packages/core/src/index.ts` 中的路线投影、摄像头匹配和距离算法需要移植并用相同坐标夹具测试。PWA 无法保证锁屏后继续接收 GPS 或语音提示；iOS 客户端需要真实设备上的后台定位、电量和语音测试。
