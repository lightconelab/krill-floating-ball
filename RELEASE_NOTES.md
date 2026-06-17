# Krill Floating Ball v0.1.0

## 中文简体

这是 Krill Floating Ball 的第一个公开版本。它是一个低开销的 macOS 原生悬浮球应用，用于在桌面查看 Krill AI 套餐使用情况。

### 主要功能

- Swift/AppKit 原生菜单栏应用，无 Dock 图标。
- 80px 桌面置顶悬浮球，展示周剩余额度。
- 球体液体水位和告警颜色会根据周剩余额度百分比变化。
- 鼠标悬浮展开今日花费、请求数、缓存率、钱包余额、刷新时间和生效套餐。
- 支持设置自动刷新间隔，默认 30 秒。
- 菜单栏支持手动刷新和 Token 管理。
- Krill API Token 保存到 macOS Keychain。

### 下载

下载 `Krill-Floating-Ball-v0.1.0-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac。Intel Mac 用户可以下载源码后使用构建脚本自行构建。

### macOS 安全提示

当前版本已做 ad-hoc 签名，但没有使用 Apple Developer ID 公证。首次打开时 macOS 可能提示安全警告。如果你信任该来源，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

### 从源码构建

```bash
git clone https://github.com/lightconelab/krill-floating-ball.git
cd krill-floating-ball
./scripts/build_app.sh
open "dist/Krill Floating Ball.app"
```

## English

This is the first public release of Krill Floating Ball, a lightweight native macOS floating usage monitor for Krill AI accounts.

### Highlights

- Native AppKit menu bar app with no Dock icon.
- Always-on-top 80px floating ball showing weekly remaining quota.
- Liquid level and warning color change based on remaining weekly quota percentage.
- Hover panel with today's spend, request count, cache rate, wallet balance, refresh time, and active subscription cards.
- Configurable auto-refresh interval, defaulting to 30 seconds.
- Manual refresh and token management from the menu bar.
- Krill API token is stored in macOS Keychain.

### Download

Download `Krill-Floating-Ball-v0.1.0-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. Intel Macs can build from source with the included script.

### macOS Security Notice

This release is ad-hoc signed but not notarized with an Apple Developer ID. On first launch, macOS may show a security warning. If you trust the source, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

### Build From Source

```bash
git clone https://github.com/lightconelab/krill-floating-ball.git
cd krill-floating-ball
./scripts/build_app.sh
open "dist/Krill Floating Ball.app"
```
