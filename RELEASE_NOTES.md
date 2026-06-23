# Krill Floating Ball v0.2.5

## 中文简体

这是 Krill Floating Ball 的展开栏体验与统计内存优化版本。它修复隐藏后再显示时贴边进度条状态残留的问题，优化展开栏与悬浮球的层级和自适应宽度，并进一步降低切换大范围统计时的内存峰值。

### 主要更新

- 修复菜单栏隐藏后再显示悬浮球时，进度条可能出现在屏幕中间的问题。
- 展开栏打开时保持悬浮球位于面板上方，避免面板完全盖住悬浮球导致无法拖拽。
- 展开栏会根据左右可用空间自适应宽度，减少右侧冗余留白。
- 使用统计卡片改为图标和标题居中、数值居中展示，趋势折线去掉额外灰色横线。
- 近 30 日等大范围统计改为按 7 天分片请求，并使用轻量 JSON 扫描只提取必要字段。
- 趋势数据最多保留 64 个采样点，分片处理期间主动释放堆内存压力，降低多次切换统计范围后的内存增长。
- 更新 README 截图：展开栏、悬浮球和展开栏整体效果、贴边进度条和展开栏整体效果。

### 性能说明

- 自动刷新默认仍为 30 秒，可在菜单栏调整。
- 下一次自动刷新会在当前刷新完成后开始计时。
- 刷新失败不会覆盖上一次成功刷新时间。
- 统计接口仍保留超时控制；大范围统计会分片请求，避免一次性解码过大的响应数据。

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.5-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac，并已做 ad-hoc 签名但未经过 Apple Developer ID 公证。首次打开时如被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

Intel Mac 用户可以下载源码后使用构建脚本自行构建。

## English

This release improves the expanded panel experience and reduces memory pressure while switching statistic ranges. It fixes the widget restore state after hide/show, keeps the floating ball draggable when the panel is open, and avoids large one-shot statistics decoding for longer ranges.

### Highlights

- Fixed the hide/show restore path so the edge quota bar no longer appears in the middle of the screen.
- Kept the floating ball window above the expanded panel so the ball remains draggable.
- Improved expanded-panel placement and adaptive width to reduce unnecessary blank space.
- Refined statistic cards with centered icon/title headers, centered values, and sparklines without the extra gray baseline.
- Large statistic ranges such as 30 days are now requested in 7-day chunks.
- Statistics responses are parsed with a lightweight field scanner, trend data is capped at 64 samples, and heap pressure is released between chunks to reduce memory growth after repeated range switches.
- Refreshed README screenshots for the expanded panel, floating overview, and edge-bar overview.

### Performance Notes

- The default auto-refresh interval remains 30 seconds and can be changed from the menu bar.
- The next automatic refresh is scheduled only after the current refresh completes.
- Failed refreshes keep the previous successful refresh timestamp unchanged.
- Statistics requests still use explicit timeouts, and large ranges avoid decoding a single large response in memory.

### Download

Download `Krill-Floating-Ball-v0.2.5-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. It is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

Intel Macs can build from source with the included scripts.
