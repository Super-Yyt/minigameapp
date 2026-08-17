# MiniGame Flutter 客户端

## Deep Link

登录回调固定为：

```text
minigame://auth/callback?token=...
```

Android 的 `AndroidManifest.xml` 和 iOS 的 `Info.plist` 已注册 `minigame` 协议。修改原生配置后需要卸载旧应用并重新安装，热重载不会更新协议注册。

Windows 需要先构建并将协议注册到当前用户：

```powershell
flutter build windows --debug
powershell -ExecutionPolicy Bypass -File .\tool\register_windows_protocol.ps1
Start-Process "minigame://auth/callback?token=test"
```

Windows 客户端采用单实例模式。已运行时，新的 `minigame://` 登录回调会转发给当前窗口并置前，不会再打开第二个客户端窗口。该功能需要重新构建和安装 Windows 客户端后生效。

使用其他构建模式时可明确指定程序：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\register_windows_protocol.ps1 `
  -Executable .\build\windows\x64\runner\Release\minigameapp.exe
```

注销 Windows 协议：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\register_windows_protocol.ps1 -Unregister
```

## 运行

```powershell
flutter run --dart-define=API_BASE=http://127.0.0.1:8000
```

Web 端固定使用 `3000` 端口，以匹配服务端的白名单回跳地址：

```powershell
flutter run -d chrome --web-port 3000 `
  --dart-define=API_BASE=http://127.0.0.1:8000
```

Web 登录会在当前标签页打开 Logto，完成后回到 `http://localhost:3000/?token=...`。客户端保存 Token 后会立即清理地址栏。移动端和桌面端仍使用 `minigame://auth/callback`。

## 联机大厅与邀请

首页工具栏提供“联机大厅”和“输入房间号加入”。创建房间后，游戏页工具栏可以复制房间号或邀请链接。邀请链接是 `http://localhost:3000/?room=<房间UUID>`；在 Web 打开会自动进入加入流程。客户端可使用 `minigame://join?room=<房间UUID>` 唤起并进入同一流程。

同一账号可以在多台设备保持登录，但同一时间只能用一个设备参与等待中或进行中的联机房间。第二台设备会收到拒绝提示，第一台设备不会被强制下线或退出对局。
