# Krill Floating Ball v0.2.9

## 中文简体

这是 Krill Floating Ball 的月卡剩余额度修正与公开文档刷新版本。它继续保持轻量原生 AppKit 实现，不引入 WebKit、Safari 或 JavaScriptCore。

### 主要更新

- 修正月卡套餐卡片的剩余额度计算口径，使其更贴近按窗口发放的实际展示规则，避免把未来窗口额度重复计算进去。
- 更新中文和英文 README 截图，替换菜单栏功能、悬浮球、悬浮球与展开栏整体效果、展开栏和 Krill 账号弹窗图片。
- 继续保持公开文档不暴露内部计算细节或特定数据源实现。

### 修复说明

- 月卡套餐卡片中的总剩余额度不再高于实际应展示值。
- 发布页与 README 预览图同步到当前版本界面。

### 性能与依赖

- 应用仍为原生 Swift/AppKit 实现。
- Release 二进制未链接 WebKit、Safari 或 JavaScriptCore。
- 继续避免引入浏览器内核或网页内容进程。

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.9-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac，并已做 ad-hoc 签名但未经过 Apple Developer ID 公证。首次打开时如被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

Intel Mac 用户可以下载源码后使用构建脚本自行构建。

## English

This release corrects the monthly-plan remaining-quota display and refreshes the public documentation screenshots. The app remains a lightweight native AppKit utility without WebKit, Safari, or JavaScriptCore.

### Highlights

- Corrected the monthly-plan card remaining-quota display so it better matches the window-based issuance behavior and no longer overcounts future windows.
- Refreshed the Chinese and English README screenshots for the menu, floating ball, floating overview, expanded panel, and Krill account dialog.
- Kept the public documentation free of internal calculation details and data-source-specific implementation notes.

### Fix Notes

- Monthly-plan cards no longer display an inflated remaining total.
- Release assets and README previews now match the current UI.

### Performance And Dependencies

- The app remains a native Swift/AppKit implementation.
- The release binary does not link WebKit, Safari, or JavaScriptCore.
- The app continues to avoid browser engines and web-content helper processes.

### Download

Download `Krill-Floating-Ball-v0.2.9-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. It is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

Intel Macs can build from source with the included scripts.
