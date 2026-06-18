# Krill Floating Ball v0.2.2

## 中文简体

这是 Krill Floating Ball 的一次口径修正与文档截图更新版本。它进一步修正悬浮球周可用额度池、未配置 Token 的空状态、套餐卡片排序，并更新了 GitHub README 使用的最新截图。

### 主要更新

- 修正悬浮球周可用额度池：当前生效的周额度套餐，会叠加与该周周期时间范围重叠的生效总额度套餐。
- 悬浮球液体颜色提醒仍按周可用额度池的剩余额度百分比分级。
- 修复未配置 Token 时，悬浮球底部不应出现灰色液体波浪的问题。
- 生效套餐卡片仅展示 `active = true` 且当前时间位于订阅开始和结束之间的套餐，并按套餐总额度剩余额度从高到低排序。
- README 更新悬浮球和展开栏整体效果、展开栏、悬浮球、未配置 Token 状态和输入 Token 弹窗截图。
- 中英文文档同步更新当前额度口径说明。

### 额度口径

- `plan.billing_type = usd_monthly`：套餐总额度为 `quota.daily_limit_usd`，并且不计入周额度。
- `plan.billing_type = usd_weekly`：周额度为 `quota.daily_limit_usd`，套餐总额度为 `quota.daily_limit_usd * 4`。
- 生效套餐仅统计 `active = true` 且当前时间位于 `subscription_start_at` 与 `subscription_end_at` 之间的套餐。
- 悬浮球展示当前周周期可用池：有周额度的生效套餐 + 与该周周期时间范围重叠的其他生效总额度套餐。

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.2-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac，并已做 ad-hoc 签名但未经过 Apple Developer ID 公证。首次打开时如被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

Intel Mac 用户可以下载源码后使用构建脚本自行构建。

## English

This release corrects quota aggregation, the missing-token empty state, active subscription ordering, and README screenshots.

### Highlights

- Corrected the floating ball weekly availability pool: active weekly-quota subscriptions now include overlapping active total-quota subscriptions within the current weekly quota window.
- Kept liquid color alerts based on the remaining percentage of that weekly availability pool.
- Fixed the missing-token state so the floating ball no longer renders a gray liquid wave before a token is configured.
- Active subscription cards now only show currently active subscriptions and are sorted by remaining total quota from high to low.
- Refreshed README screenshots for the floating overview, expanded panel, floating ball, missing-token state, and token prompt.
- Updated Chinese and English documentation to describe the current quota scope.

### Quota Rules

- `plan.billing_type = usd_monthly`: subscription total quota is `quota.daily_limit_usd`, and it is not counted as weekly quota.
- `plan.billing_type = usd_weekly`: weekly quota is `quota.daily_limit_usd`, and subscription total quota is `quota.daily_limit_usd * 4`.
- Active subscriptions are counted only when `active = true` and the current time is within `subscription_start_at` and `subscription_end_at`.
- The floating ball shows the current weekly availability pool: active subscriptions with weekly quota plus other active total-quota subscriptions whose subscription time range overlaps that weekly window.

### Download

Download `Krill-Floating-Ball-v0.2.2-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. It is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

Intel Macs can build from source with the included scripts.
