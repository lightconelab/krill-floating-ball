# Krill Floating Ball v0.2.10

## 中文简体

这是 Krill Floating Ball 的 Codex 模型智商展示版本。它在展开栏中加入横向模型 IQ 排行，同时继续保持轻量原生 AppKit 实现，不引入 WebKit、Safari 或 JavaScriptCore。

### 主要更新

- 新增 `Codex 模型智商` 模块，在使用统计和生效套餐之间展示横向模型 IQ 卡片。
- 模型卡片按 IQ 数值从高到低排序，并使用更醒目的红、蓝、绿、青、黄配色区分卡片位置。
- 刷新中文和英文 README 截图，包含展开栏、悬浮球整体效果、贴边进度条整体效果、菜单栏功能和 Codex 模型智商模块。
- 继续保持公开文档不暴露内部计算细节或特定数据源实现。

### 性能与依赖

- 应用仍为原生 Swift/AppKit 实现。
- 新增模型 IQ 展示不使用浏览器内核，不会引入网页内容进程。
- 模型 IQ 数据采用轻量请求与内存缓存，避免随着自动刷新频率重复拉取和解析。
- Release 二进制未链接 WebKit、Safari 或 JavaScriptCore。

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.10-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac，并已做 ad-hoc 签名但未经过 Apple Developer ID 公证。首次打开时如被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

Intel Mac 用户可以下载源码后使用构建脚本自行构建。

## English

This release adds Codex model IQ ranking to Krill Floating Ball. The expanded panel now includes a horizontal model IQ section while the app remains a lightweight native AppKit utility without WebKit, Safari, or JavaScriptCore.

### Highlights

- Added a `Codex Model IQ` module between usage statistics and active subscriptions.
- Model cards are sorted from high to low by IQ score and use vivid red, blue, green, cyan, and yellow colors by card position.
- Refreshed the Chinese and English README screenshots for the expanded panel, floating overview, edge progress overview, menu actions, and the new Codex IQ module.
- Kept the public documentation free of internal calculation details and data-source-specific implementation notes.

### Performance And Dependencies

- The app remains a native Swift/AppKit implementation.
- The new model IQ module does not use a browser engine and does not introduce web-content helper processes.
- Model IQ data uses lightweight fetching with in-memory caching to avoid repeated download and parsing on every automatic refresh.
- The release binary does not link WebKit, Safari, or JavaScriptCore.

### Download

Download `Krill-Floating-Ball-v0.2.10-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. It is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

Intel Macs can build from source with the included scripts.
