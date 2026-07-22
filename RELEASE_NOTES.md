# Krill Floating Ball v0.2.12

## 中文简体

这是 Krill Floating Ball 的 Codex 模型智商分页、时间显示与刷新可靠性优化版本。展开栏现在以更紧凑的宽度完整展示模型排行和精确更新时间。

### 主要更新

- Codex 模型智商调整为每页展示 4 张卡片，卡片较多时可通过标题右侧的紧凑分页控件查看。
- 模型更新时间改为北京时间，并完整显示为 `yyyy-MM-dd HH:mm:ss`，日期区域会根据内容动态计算宽度，避免截断。
- 优化模型数据与视觉配色的刷新和合并流程，降低单一路径异常导致旧数据或配色失效的概率。
- 兼容最新模型配色样式；未取得对应配色时仍会使用内置安全回退色。
- 模型刷新完成后释放解析阶段产生的临时内存，同时保持原生 AppKit 实现，不引入浏览器内核或网页内容进程。

### 验证情况

- Swift 测试：20 项全部通过。
- Release 包：Apple Silicon `arm64`。
- 签名：ad-hoc 签名，未经过 Apple Developer ID 公证。
- SHA-256：`7efd72beef6d58c2e1ae62776b1e7f21e5f35fb1c492205562346826463187f6`

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.12-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

首次打开时如被 macOS 阻止，可以右键点击 App 选择“打开”，或在“系统设置 → 隐私与安全性”中允许打开。Intel Mac 用户可以下载源码并使用项目构建脚本自行构建。

## English

This release improves Codex model IQ pagination, timestamp presentation, and refresh reliability. The expanded panel now presents the ranking and precise update time in a more compact width.

### Highlights

- Changed Codex model IQ pagination to 4 cards per page, with compact controls in the section header for additional models.
- Displayed the complete model update timestamp in Beijing time using `yyyy-MM-dd HH:mm:ss`, with dynamically measured width to prevent clipping.
- Improved model-data and visual-color refresh merging so a single unavailable path is less likely to leave stale content or incorrect colors.
- Added compatibility with the latest model color styles while retaining safe built-in fallback colors.
- Released temporary parsing memory after model refreshes while keeping the app fully native AppKit without browser engines or web-content processes.

### Verification

- Swift tests: all 20 tests passed.
- Release target: Apple Silicon `arm64`.
- Signing: ad-hoc signed and not notarized with an Apple Developer ID.
- SHA-256: `7efd72beef6d58c2e1ae62776b1e7f21e5f35fb1c492205562346826463187f6`

### Download

Download `Krill-Floating-Ball-v0.2.12-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

If macOS blocks the first launch, right-click the app and choose Open, or allow it in System Settings → Privacy & Security. Intel Mac users can build from source with the included scripts.
