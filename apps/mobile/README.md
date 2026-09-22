# Flutter App（下一期）

这里预留 Flutter 移动端。第一期没有创建一个无法运行的空 Flutter 工程；等确定 Android/iOS 发布目标后，在本目录运行 `flutter create . --platforms android,ios`。

移动端直接使用 `../../packages/contracts/openapi.yaml` 中的 API：`/api/cameras`、`/api/search`、`/api/route`。地图、路线摄像头高亮、距离倒计时和语音文案可以参照 `../../packages/core/src/index.ts` 的算法移植到 Dart；Dart 代码需要独立测试同一路线与坐标夹具。

后台导航需要原生能力：Android 前台服务与持续定位通知、iOS Background Modes Location Updates，以及系统音频会话。PWA 无法保证切后台后持续 GPS 或语音。
