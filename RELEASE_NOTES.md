# Krill Floating Ball v0.2.8

## 中文简体

这是 Krill Floating Ball 的使用统计、内存占用和公开文档刷新版本。它继续保持轻量原生 AppKit 实现，不引入 WebKit、Safari 或 JavaScriptCore。

### 主要更新

- 使用统计范围文案调整为更清晰的 `月卡单窗口` / `月卡`。
- 月卡相关统计范围会稳定绑定到当前生效的月卡上下文，减少多套餐场景下的理解成本。
- 优化刷新与切换统计范围时的内存开销，减少大范围统计带来的临时内存压力，并在 Krill 账号弹窗关闭后释放临时资源。
- 移除 Krill 账号弹窗输入框的系统用户名/密码 content type 提示，减少 macOS AutoFill 与 LocalAuthentication helper 被额外唤起的概率。
- 更新中文和英文 README，替换展开栏、悬浮球展开、贴边进度条、菜单栏、CPU、内存和能耗截图。

### 修复说明

- 统计范围文案更贴近真实口径，避免用户误解 `额度周` 和 `套餐期` 对应哪个套餐。
- 多月卡同时生效时，月卡相关统计范围会保持稳定。
- 大范围统计切换时减少临时内存分配，降低多次切换后的内存压力。

### 性能与依赖

- 应用仍为原生 Swift/AppKit 实现。
- Release 二进制未链接 WebKit、Safari 或 JavaScriptCore。
- 继续避免引入浏览器内核或网页内容进程。

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.8-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac，并已做 ad-hoc 签名但未经过 Apple Developer ID 公证。首次打开时如被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

Intel Mac 用户可以下载源码后使用构建脚本自行构建。

## English

This release refines usage statistic ranges, memory behavior, and public documentation. The app remains a lightweight native AppKit utility without WebKit, Safari, or JavaScriptCore.

### Highlights

- Renamed the usage statistic ranges from `额度周` / `套餐期` to the clearer `月卡单窗口` / `月卡`.
- Monthly statistic ranges now stay tied to a stable active monthly-plan context, making multi-plan scenarios easier to understand.
- Reduced memory overhead during refresh and statistic range switching, especially for large statistic ranges, and released temporary account-dialog resources after close.
- Removed system username/password content-type hints from the Krill account dialog to reduce unnecessary macOS AutoFill and LocalAuthentication helper activation.
- Refreshed the Chinese and English README screenshots for the expanded panel, floating overview, edge progress bar, menu, CPU, memory, and energy references.

### Fix Notes

- Statistic range labels now better match the actual aggregation scope.
- When multiple monthly plans are active, monthly statistics remain stable.
- Large statistic ranges now create fewer temporary allocations, reducing memory pressure after repeated range switching.

### Performance And Dependencies

- The app remains a native Swift/AppKit implementation.
- The release binary does not link WebKit, Safari, or JavaScriptCore.
- The app continues to avoid browser engines and web-content helper processes.

### Download

Download `Krill-Floating-Ball-v0.2.8-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. It is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

Intel Macs can build from source with the included scripts.
