# Krill Floating Ball v0.2.6

## 中文简体

这是 Krill Floating Ball 的登录体验、刷新链路和文档整理版本。它修复 Krill 登录账号弹窗中快捷键粘贴不生效的问题，登录后会立即刷新数据，并进一步降低网络请求和面板释放后的内存压力。

### 主要更新

- Krill 登录账号弹窗支持标准编辑菜单，并显式兼容 `Command + V` 和 `Control + V` 粘贴。
- 保存 Krill 邮箱和密码后，会取消旧的刷新任务并立即发起新请求，避免登录成功后仍等待下一轮自动刷新。
- 继续使用 macOS Keychain 保存 Krill 邮箱和密码；接口 Token 仅运行时登录获取，不写入源码或本地配置。
- 登录输入框关闭自动补全、写作工具和内容类型提示，减少系统自动填充链路带来的额外系统 helper 激活。
- 网络层关闭 Cookie、URL cache 和 URL credential storage，并在每次请求完成后释放临时 URLSession。
- 刷新结束和展开栏释放后主动向系统申请释放空闲堆内存，降低长期运行和多次切换统计范围后的常驻占用。
- 重写中文和英文 README，整理公开项目说明、截图、数据口径、隐私说明和性能说明。
- 替换最新 README 截图，移除旧 Token 配置时代的过期文档图片。

### 性能说明

- 本地 Release 构建空闲 CPU 回落到 `0.0%`。
- 使用 `vmmap` 观察到稳定后的 Physical footprint 约 `33MB`，启动或首次刷新期间峰值约 `56MB`。
- 活动监视器或 `ps RSS` 会把部分系统框架驻留页计入进程，数值通常会高于 Physical footprint。
- 应用未链接 WebKit、Safari 或 JavaScriptCore；如系统中出现 `SafariPlatformSupport.Helper`，它来自 macOS 的系统服务链路，并非本应用主动启动的 WebView/Safari 进程。

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.6-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac，并已做 ad-hoc 签名但未经过 Apple Developer ID 公证。首次打开时如被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

Intel Mac 用户可以下载源码后使用构建脚本自行构建。

## English

This release improves the Krill account login prompt, refresh flow, memory behavior, and public documentation. The login prompt now supports paste shortcuts, successful credential updates trigger an immediate refresh, and the request layer releases temporary network resources more aggressively.

### Highlights

- Added standard edit menu support and explicit `Command + V` / `Control + V` paste handling in the Krill account prompt.
- Saving Krill email and password now cancels stale refresh work and starts a fresh fetch immediately, avoiding a wait for the next automatic refresh.
- Krill email and password are stored in macOS Keychain; API tokens are obtained at runtime and kept in memory only.
- Disabled text completion, Writing Tools affordances, and autofill content type hints on the login fields to reduce unnecessary system helper activation.
- Disabled cookies, URL cache, and URL credential storage in the request layer, and invalidates temporary URLSession instances after each request.
- Added heap pressure relief after refresh completion and panel teardown to reduce long-running memory retention.
- Rewrote the Chinese and English README for public open-source use, including screenshots, data scope, privacy notes, and performance notes.
- Replaced the latest README screenshots and removed obsolete token-era documentation images.

### Performance Notes

- Local release build idle CPU returned to `0.0%`.
- `vmmap` showed a settled Physical footprint around `33MB`, with a launch/first-refresh peak around `56MB`.
- Activity Monitor or `ps RSS` may include resident system framework pages and can therefore show a higher number than Physical footprint.
- The app does not link WebKit, Safari, or JavaScriptCore. If `SafariPlatformSupport.Helper` appears, it comes from macOS system service paths, not from an app-owned WebView/Safari process.

### Download

Download `Krill-Floating-Ball-v0.2.6-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. It is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

Intel Macs can build from source with the included scripts.
