# Krill Floating Ball v0.2.7

## 中文简体

这是 Krill Floating Ball 的菜单、账号状态、登录请求兼容和公开文档整理版本。它继续保持原生 AppKit 与直接 HTTP 请求实现，不引入 WebKit、Safari 或 JavaScriptCore。

### 主要更新

- 登录请求补充本地生成并持久化的 `_kfp` fingerprint cookie，使 Krill 登录和数据获取继续走轻量 HTTP 请求路径。
- 菜单栏功能重新分组：立即刷新、桌面悬浮球、贴边进度条、刷新间隔、余额提醒区间、开机启动、Krill 账号和退出。
- `显示悬浮球` / `隐藏悬浮球` 合并为一个带勾选状态的 `桌面悬浮球`。
- `余额阈值` 调整为 `余额提醒区间`，并把 `恢复默认` 移入该设置弹窗。
- `设置 Krill 账号...` 调整为 `Krill 账号`，并把 `清除登录信息` 移入账号弹窗。
- 修复清除登录信息后展开栏仍可能残留旧套餐、钱包余额、使用统计、缓存率和刷新时间的问题。
- 修复菜单栏精灵球图标中横线贯穿中央 `K` 小圆圈的问题。
- 生效套餐卡片在筛选 `active = true && now >= start && now < end` 后，按接口返回的 `subscriptions` 原始顺序展示。
- 更新中文和英文 README，替换最新菜单、余额提醒区间、Krill 账号、展开栏和未登录状态截图。
- 对近期改动做了一轮保守代码简化，收敛空状态文案、HTTP 状态校验、统计卡片绘制和未使用回调。

### 修复说明

- 清除登录信息后，悬浮球会立即显示 `未登录`。
- 展开栏统计卡片显示 `--`，刷新时间回到 `--:--:--`。
- 套餐列表会清空，并提示先在菜单栏设置 Krill 账号。
- 统计范围回到 `今日`，`额度周` 和 `套餐期` 不再沿用旧账号状态。

### 性能与依赖

- 应用仍为原生 Swift/AppKit 实现。
- Release 二进制未链接 WebKit、Safari 或 JavaScriptCore。
- 请求层继续使用无缓存、无 URLCredentialStorage 的轻量网络配置。

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.7-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac，并已做 ad-hoc 签名但未经过 Apple Developer ID 公证。首次打开时如被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

Intel Mac 用户可以下载源码后使用构建脚本自行构建。

## English

This release refines the menu bar, account-clearing state, login request compatibility, and public documentation. The app remains a native AppKit utility using direct HTTP requests without WebKit, Safari, or JavaScriptCore.

### Highlights

- Added a locally generated and persisted `_kfp` fingerprint cookie for Krill login requests while keeping the lightweight direct HTTP request path.
- Reorganized menu bar actions into refresh, desktop widget, edge progress bar, refresh interval, balance alert ranges, launch at login, Krill account, and quit.
- Merged the separate show/hide floating ball actions into one checked `桌面悬浮球` menu item.
- Renamed balance threshold settings to balance alert ranges and moved restore-default into that dialog.
- Renamed the account menu item to `Krill 账号` and moved login clearing into the account dialog.
- Fixed stale data after clearing login information so quota, wallet balance, usage stats, cache rates, subscriptions, and refresh time reset immediately.
- Fixed the menu bar capture-ball icon so the divider no longer crosses the central `K` button.
- Active subscription cards now preserve the original `subscriptions` order returned by the API after active-time filtering.
- Refreshed the Chinese and English README screenshots for the latest menu, balance alert ranges, Krill account dialog, expanded panel, and missing-account state.
- Simplified recently touched code around empty-state labels, HTTP status validation, stat-card drawing, and unused callbacks without changing behavior.

### Fix Notes

- After clearing login information, the floating ball immediately shows `未登录`.
- Usage cards show `--`, and refresh time returns to `--:--:--`.
- Subscription cards are cleared and the panel asks the user to set the Krill account from the menu bar.
- The selected stats range falls back to `Today`; quota-week and subscription-period buttons no longer inherit stale account state.

### Performance And Dependencies

- The app remains a native Swift/AppKit implementation.
- The release binary does not link WebKit, Safari, or JavaScriptCore.
- The request layer continues to use a lightweight no-cache network configuration without URLCredentialStorage.

### Download

Download `Krill-Floating-Ball-v0.2.7-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. It is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

Intel Macs can build from source with the included scripts.
