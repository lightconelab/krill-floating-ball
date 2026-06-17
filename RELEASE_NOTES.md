# Krill Floating Ball v0.2.0

## 中文简体

这是 Krill Floating Ball 的第二个公开版本。本次更新补充了开机启动开关和应用图标，让应用更接近可长期使用的桌面工具。

### 新增功能

- 增加开机启动功能。
- 顶部菜单栏新增 `开机启动` 开关，可开启或关闭随系统登录自动启动。
- 增加应用图标：红白球体风格，中间带 `K`，用于表示 Krill AI 相关工具。

### 说明

- 开机启动使用 macOS 原生登录项服务实现，不额外增加后台常驻进程。
- 首次开启开机启动时，如果 macOS 要求批准，请在 `系统设置 -> 通用 -> 登录项` 中允许该应用。

### 下载

下载 `Krill-Floating-Ball-v0.2.0-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac。Intel Mac 用户可以下载源码后使用构建脚本自行构建。

### macOS 安全提示

当前版本已做 ad-hoc 签名，但没有使用 Apple Developer ID 公证。首次打开时 macOS 可能提示安全警告。如果你信任该来源，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

## English

This is the second public release of Krill Floating Ball. This update adds launch-at-login support and a dedicated app icon, making the app more suitable for daily desktop use.

### Added

- Added launch at login support.
- Added a menu bar toggle to enable or disable launch at login.
- Added a Krill-themed app icon: a red-and-white ball with a central `K`.

### Notes

- Launch at login uses the native macOS login item service and does not add an extra background daemon.
- If macOS requires approval after enabling launch at login, allow the app in `System Settings -> General -> Login Items`.

### Download

Download `Krill-Floating-Ball-v0.2.0-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. Intel Macs can build from source with the included script.

### macOS Security Notice

This release is ad-hoc signed but not notarized with an Apple Developer ID. On first launch, macOS may show a security warning. If you trust the source, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.
