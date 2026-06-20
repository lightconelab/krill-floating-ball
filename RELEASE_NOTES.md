# Krill Floating Ball v0.2.3

## 中文简体

这是 Krill Floating Ball 的贴边显示与性能稳定性优化版本。它新增贴边剩余额度悬浮条，完善多显示器拖拽边界处理，并继续降低长期运行时的 CPU、内存和能耗开销。

### 主要更新

- 新增贴边剩余额度悬浮条：悬浮球靠近屏幕边缘时，会默认吸附为细长进度条。
- 贴边进度条会根据边缘方向自动切换形态：左右边缘显示竖向进度条，上下边缘显示横向进度条。
- 菜单栏新增贴边进度条开关，用户可以关闭该效果并恢复普通悬浮球贴边逻辑。
- 收紧拖拽边界，避免悬浮球或贴边进度条被拖出屏幕导致不可见，并兼容外置显示器场景。
- 优化悬浮球动画调度：贴边进度条模式不再运行液体波浪动画，普通悬浮球按状态降低空闲帧率。
- 优化长期运行内存稳定性：收起后释放展开栏窗口，隐藏悬浮球时移除窗口观察者，停止刷新时取消刷新任务，视图离开窗口时停止动画 Timer。
- 优化 Token 读取体验：Token 首次读取后在进程内缓存，并使用 `kSecAttrAccessibleAfterFirstUnlock` 保存，减少正常使用中反复要求输入电脑密码的情况。
- 更新套餐时间、剩余时间、周额度/总额度展示，并继续按当前生效套餐和剩余额度口径计算悬浮球水位与提醒颜色。
- README 更新菜单栏功能、贴边竖向/横向效果、贴边 CPU 占用和悬浮球 CPU 占用截图。

### 性能说明

- 自动刷新默认仍为 30 秒，可在菜单栏调整。
- 刷新失败不会覆盖上一次成功刷新时间。
- 展开栏按需创建，收起后释放，减少长期驻留内存。
- 贴边进度条是静态绘制形态，不运行波浪动画，适合长期常驻。

### 下载与运行

下载 `Krill-Floating-Ball-v0.2.3-macOS-arm64.zip`，解压后打开 `Krill Floating Ball.app`。

当前预构建包面向 Apple Silicon Mac，并已做 ad-hoc 签名但未经过 Apple Developer ID 公证。首次打开时如被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

Intel Mac 用户可以下载源码后使用构建脚本自行构建。

## English

This release improves edge display behavior, drag safety, and long-running performance stability. It adds a slim edge quota bar, improves multi-display boundary handling, and further reduces CPU, memory, and energy overhead for always-on usage.

### Highlights

- Added an edge quota bar: when the floating ball approaches a screen edge, it snaps into a slim remaining-quota progress bar by default.
- The edge bar adapts to the edge direction: vertical on the left/right edges and horizontal on the top/bottom edges.
- Added a menu bar toggle for enabling or disabling the edge quota bar behavior.
- Tightened drag constraints so the widget cannot disappear outside the visible screen area, including external display setups.
- Optimized animation scheduling: the edge bar does not run the liquid wave animation, and the normal floating ball uses lower idle frame rates based on state.
- Improved long-running memory stability by releasing the hover panel after collapse, removing window observers when hidden, canceling refresh tasks on stop, and stopping animation timers when views leave their windows.
- Improved token read behavior: the token is cached in-process after the first successful Keychain load and stored with `kSecAttrAccessibleAfterFirstUnlock`, reducing repeated password prompts in normal use.
- Refined subscription time labels, weekly/total quota display, and quota calculation while keeping the floating ball liquid level and alert colors tied to the active remaining quota percentage.
- Refreshed README screenshots for menu actions, vertical/horizontal edge bars, edge-bar CPU usage, and floating-ball CPU usage.

### Performance Notes

- The default auto-refresh interval remains 30 seconds and can be changed from the menu bar.
- Failed refreshes keep the previous successful refresh timestamp unchanged.
- The hover panel is created on demand and released after collapse.
- The edge quota bar is a static drawing mode without wave animation, making it suitable for long-running always-on use.

### Download

Download `Krill-Floating-Ball-v0.2.3-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. It is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

Intel Macs can build from source with the included scripts.
