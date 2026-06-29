# Krill Floating Ball v0.2.8

## 中文简体

这是 Krill Floating Ball 的月卡统计范围、内存占用和公开文档刷新版本。它继续保持原生 AppKit 与直接 HTTP 请求实现，不引入 WebKit、Safari 或 JavaScriptCore。

### 主要更新

- 使用统计范围从 `额度周` / `套餐期` 调整为更明确的 `月卡单窗口` / `月卡`。
- `月卡单窗口` 与 `月卡` 都以当前生效月卡中 `subscription_start_at` 最早的那张月卡为统计基准。
- 优化刷新与切换统计范围时的内存开销：复用 JSON 编解码器、复用 API 日期解析器、避免 stats JSON 校验时整文件 mmap、优化字符串扫描，并在 Krill 账号弹窗关闭后释放账号校验 API client。
- 移除 Krill 账号弹窗输入框的系统用户名/密码 content type 提示，减少 macOS AutoFill 与 LocalAuthentication helper 被额外唤起的概率。
- 更新中文和英文 README，替换展开栏、月卡统计范围、贴边进度条、菜单栏、账号弹窗、CPU、内存和能耗截图。

### 修复说明

- 统计范围文案更贴近真实口径，避免用户误解 `额度周` 和 `套餐期` 对应哪个套餐。
- 多月卡同时生效时，月卡相关统计范围会稳定选择最早开始的生效月卡。
- 大 stats JSON 响应解析时减少临时内存分配，降低多次切换统计范围后的内存压力。

### 性能与依赖

- 应用仍为原生 Swift/AppKit 实现。
- Release 二进制未链接 WebKit、Safari 或 JavaScriptCore。
- 请求层继续使用无缓存、无 URLCredentialStorage 的轻量网络配置。

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.8-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac，并已做 ad-hoc 签名但未经过 Apple Developer ID 公证。首次打开时如被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

Intel Mac 用户可以下载源码后使用构建脚本自行构建。

## English

This release refines monthly-plan statistic ranges, memory behavior, and public documentation. The app remains a native AppKit utility using direct HTTP requests without WebKit, Safari, or JavaScriptCore.

### Highlights

- Renamed the usage statistic ranges from `额度周` / `套餐期` to the clearer `月卡单窗口` / `月卡`.
- Both monthly statistic ranges are scoped to the active monthly plan with the earliest `subscription_start_at`.
- Reduced memory overhead during refresh and statistic range switching by reusing JSON coders, reusing the API date parser, avoiding full-file mmap during stats JSON validation, optimizing string scanning, and releasing the account-validation API client after the Krill account dialog closes.
- Removed system username/password content-type hints from the Krill account dialog to reduce unnecessary macOS AutoFill and LocalAuthentication helper activation.
- Refreshed the Chinese and English README screenshots for the expanded panel, monthly statistic ranges, edge progress bar, menu, account dialog, CPU, memory, and energy references.

### Fix Notes

- Statistic range labels now better match the actual aggregation scope.
- When multiple monthly plans are active, monthly statistics consistently use the earliest-started active monthly plan.
- Large stats JSON responses now create fewer temporary allocations, reducing memory pressure after repeated statistic range switching.

### Performance And Dependencies

- The app remains a native Swift/AppKit implementation.
- The release binary does not link WebKit, Safari, or JavaScriptCore.
- The request layer continues to use a lightweight no-cache network configuration without URLCredentialStorage.

### Download

Download `Krill-Floating-Ball-v0.2.8-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. It is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

Intel Macs can build from source with the included scripts.
