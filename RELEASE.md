# 客户端全平台发布

工作流位于 `.github/workflows/client-release.yml`。手动运行会生成 Actions Artifacts；推送 `v*` 标签会额外创建 GitHub Release。

## 仓库变量

在 GitHub Repository Variables 中设置：

- `API_BASE`：生产 API 地址，例如 `https://api.example.com`。

## Android 签名 Secrets

- `ANDROID_KEYSTORE_BASE64`：JKS 文件的 Base64。
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

未设置时工作流会使用调试签名生成 APK，只适合测试分发。正式商店发布必须配置上述 Secrets。

## Apple 签名

默认产物是未签名 iOS `Runner.app` 和 macOS `.app`，用于后续企业签名、TestFlight 或公证流水线。App Store 发布还需要配置 Apple Developer 证书、Provisioning Profile、App Store Connect API Key 和 notarization，不应把证书直接提交到仓库。

## 产物

- Android APK
- Windows x64 ZIP
- Linux x64 tar.gz
- Flutter Web tar.gz
- iOS 未签名 tar.gz
- macOS app tar.gz

应用标识统一为 `com.zhaishis.minigame`，测试 Target 使用 `com.zhaishis.minigame.RunnerTests`。
