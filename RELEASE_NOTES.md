# Krill Floating Ball v0.2.1

## 中文简体

这是 Krill Floating Ball 的一次稳定性、口径和公开发布整理版本。它补齐了开机启动、精灵球风格图标、套餐额度口径修正、展开栏视觉优化和低开销绘制策略，并更新了 GitHub README 使用的最新截图。

### 主要更新

- 新增菜单栏开机启动开关，可直接开启或关闭登录后自动启动。
- 新增精灵球风格应用图标，中心使用 `K` 表示 Krill Floating Ball。
- 菜单栏图标改为同风格的 template 图标，可随系统浅色/深色菜单栏自动变为黑色或白色。
- 优化悬浮球液体效果：水位关联周剩余额度百分比，颜色与套餐进度条使用同一套阈值规则。
- 优化展开栏布局：今日统计卡片、钱包余额、生效套餐、套餐时间范围、剩余时间和额度进度条更紧凑且更易读。
- 修正总额度/周额度/月额度进度条样式，统一使用纯色进度条，并避免半像素绘制产生细线。
- 修正刷新失败时不覆盖上一次成功刷新时间。
- 收起展开栏后释放右侧面板窗口，降低长期驻留内存占用。
- README 补充最新 CPU、内存和能耗截图，方便评估常驻开销。

### 额度口径

- `plan.billing_type = usd_monthly`：套餐总额度为 `quota.daily_limit_usd`，并且不计入周额度。
- `plan.billing_type = usd_weekly`：周额度为 `quota.daily_limit_usd`，套餐总额度为 `quota.daily_limit_usd * 4`。
- 生效套餐仅统计 `active = true` 且当前时间位于 `subscription_start_at` 与 `subscription_end_at` 之间的套餐。

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.1-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac，并已做 ad-hoc 签名但未经过 Apple Developer ID 公证。首次打开时如被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

Intel Mac 用户可以下载源码后使用构建脚本自行构建。

## English

This release prepares Krill Floating Ball for public distribution with launch-at-login support, updated capture-ball-style icons, corrected subscription quota rules, a cleaner hover panel, lower-overhead rendering, and refreshed GitHub README screenshots.

### Highlights

- Added a native menu bar launch-at-login toggle.
- Added a capture-ball-inspired app icon with a central `K` mark.
- Updated the menu bar icon to the same visual style. It is a template icon and follows the system light/dark appearance.
- Improved the liquid floating ball: fill level follows weekly remaining quota, and colors share the same threshold rules as subscription progress bars.
- Refined the hover panel layout for today's stats, wallet balance, active subscriptions, date ranges, remaining time, and quota rows.
- Unified total/weekly/monthly progress bar rendering with solid colors and pixel-aligned drawing to avoid thin rendering artifacts.
- Fixed failed refreshes so they do not overwrite the previous successful refresh time.
- Releases the hover panel window after collapse to reduce long-running memory footprint.
- Added latest CPU, memory, and energy screenshots to the README for easier overhead evaluation.

### Quota Rules

- `plan.billing_type = usd_monthly`: subscription total quota is `quota.daily_limit_usd`, and it is not counted as weekly quota.
- `plan.billing_type = usd_weekly`: weekly quota is `quota.daily_limit_usd`, and subscription total quota is `quota.daily_limit_usd * 4`.
- Active subscriptions are counted only when `active = true` and the current time is within `subscription_start_at` and `subscription_end_at`.

### Download

Download `Krill-Floating-Ball-v0.2.1-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. It is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

Intel Macs can build from source with the included scripts.
