# Krill Floating Ball v0.2.4

## 中文简体

这是 Krill Floating Ball 的使用统计与刷新稳定性优化版本。它完善展开栏的统计信息展示，新增多统计范围切换，并优化自动刷新、接口超时和多次切换统计范围后的内存占用。

### 主要更新

- 使用统计支持 `额度周`、`套餐期`、`今日`、`7日`、`30日` 范围切换。
- 使用统计新增 `Tokens` 卡片。
- 花费、请求数、Tokens 卡片展示趋势折线，并根据内容自适应卡片宽度。
- 缓存率改为按渠道展示小型进度条，减少多渠道情况下的高度占用。
- 自动刷新改为在上一次刷新任务完成后再顺延计算下一次刷新时间，避免固定间隔与慢请求互相重叠。
- 切换统计范围时会取消过期请求，避免旧请求继续解码和更新 UI。
- 新增接口超时控制：套餐接口 12 秒，统计接口 20 秒。
- API 请求改用无缓存 `ephemeral URLSession`，降低共享缓存和长期驻留对象带来的内存开销。
- 趋势数据在 JSON 解码阶段采样到最多 64 点，降低近 30 日等大范围统计的峰值内存。
- 展开栏关闭后清空面板快照，减少隐藏窗口继续持有旧统计数据的情况。
- 更新 README 截图：展开栏、悬浮球整体效果、贴边进度条整体效果。

### 性能说明

- 自动刷新默认仍为 30 秒，可在菜单栏调整。
- 下一次自动刷新会在当前刷新完成后开始计时。
- 刷新失败不会覆盖上一次成功刷新时间。
- 统计趋势数据最多保留 64 个采样点，用于降低长期运行和频繁切换范围时的内存压力。

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.4-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac，并已做 ad-hoc 签名但未经过 Apple Developer ID 公证。首次打开时如被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

Intel Mac 用户可以下载源码后使用构建脚本自行构建。

## English

This release improves usage statistics, refresh stability, and memory behavior. It adds multi-range statistics in the expanded panel and optimizes auto-refresh scheduling, API timeouts, and memory usage after repeated statistic range switches.

### Highlights

- Usage statistics now support quota week, subscription period, today, 7-day, and 30-day ranges.
- Added a Tokens card to the statistics section.
- Spend, requests, and Tokens cards now include sparklines and adapt to their content.
- Cache rates are now shown as compact per-channel progress bars.
- Automatic refresh scheduling now starts the next interval after the previous refresh finishes, avoiding fixed-interval overlap with slow requests.
- Switching statistic ranges cancels stale requests so old responses do not continue decoding or update the UI.
- Added explicit API timeouts: 12 seconds for subscription data and 20 seconds for statistics.
- API requests now use an ephemeral no-cache URLSession to reduce shared cache and long-lived memory overhead.
- Trend data is sampled to at most 64 points during JSON decoding, reducing peak memory usage for larger ranges such as 30 days.
- Hidden panel snapshots are cleared after collapse so old statistic data is not retained unnecessarily.
- Refreshed README screenshots for the expanded panel, floating overview, and edge-bar overview.

### Performance Notes

- The default auto-refresh interval remains 30 seconds and can be changed from the menu bar.
- The next automatic refresh is scheduled only after the current refresh completes.
- Failed refreshes keep the previous successful refresh timestamp unchanged.
- Trend data is capped at 64 sampled points to reduce memory pressure during long-running use and repeated range switching.

### Download

Download `Krill-Floating-Ball-v0.2.4-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. It is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

Intel Macs can build from source with the included scripts.
