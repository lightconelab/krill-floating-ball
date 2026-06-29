# Krill Floating Ball

中文简体 | [English](README.en.md)

Krill Floating Ball 是一个原生 macOS 桌面悬浮工具，用于快速查看 Krill AI 的套餐额度、使用统计、缓存率和钱包余额。它以 80px 液体悬浮球展示当前额度水位，贴近屏幕边缘时可自动切换为细长贴边进度条，鼠标悬浮后展开完整信息面板。

> 本项目是 Krill AI 的非官方桌面辅助工具，与 Krill AI 官方无关联，也不代表 Krill AI 官方背书。截图中的额度、钱包和使用数据仅作界面示例。

## 预览

### 悬浮球与展开栏

<p align="center">
  <img src="docs/images/floating-overview.png" width="880" alt="Krill Floating Ball 悬浮球和展开栏整体效果">
</p>

| 悬浮球 | 展开栏 |
| --- | --- |
| <img src="docs/images/floating-ball.png" width="160" alt="悬浮球"> | <img src="docs/images/expanded-panel.png" width="760" alt="展开栏"> |

### 贴边进度条

贴近屏幕边缘时，悬浮球可以自动吸附为进度条。左右边缘显示竖向进度条，上下边缘显示横向进度条；鼠标悬浮时仍会展开完整信息面板。

| 贴边展开 | 竖向贴边条 | 横向贴边条 |
| --- | --- | --- |
| <img src="docs/images/edge-progress-overview.png" width="700" alt="贴边进度条和展开栏"> | <img src="docs/images/edge-progress-vertical.png" width="90" alt="竖向贴边进度条"> | <img src="docs/images/edge-progress-horizontal.png" width="240" alt="横向贴边进度条"> |

### 菜单栏与账号

| 菜单栏图标 | 菜单栏功能 |
| --- | --- |
| <img src="docs/images/menubar-icon.png" width="96" alt="菜单栏图标"> | <img src="docs/images/menubar-menu.png" width="240" alt="菜单栏功能"> |

| Krill 账号 | 未配置账号 |
| --- | --- |
| <img src="docs/images/login-prompt.png" width="520" alt="Krill 账号弹窗"> | <img src="docs/images/missing-login-overview.png" width="720" alt="未配置账号状态"> |

## 功能

- 原生 Swift/AppKit 实现，无 Dock 图标，常驻 macOS 菜单栏。
- 桌面置顶 80px 液体悬浮球，可拖拽定位。
- 默认开启贴边进度条：靠近屏幕边缘自动吸附，支持多显示器场景，可在菜单栏关闭。
- 鼠标悬浮展示展开栏，包含使用统计、钱包余额、刷新状态和所有生效套餐。
- 使用统计支持 `月卡单窗口`、`月卡`、`今日`、`7日`、`30日`。
- 花费、请求数和 Tokens 展示趋势折线；缓存率按渠道展示进度条。
- 自动刷新间隔可配置，默认 30 秒；下一次自动刷新会在上一次刷新完成后顺延计时。
- 支持手动刷新、开机启动、余额提醒区间设置、Krill 账号管理、桌面悬浮球显示开关、贴边进度条开关和退出应用。
- 刷新失败时保留上一次成功数据，并在刷新时间旁显示状态标签，不覆盖上一次成功刷新时间。
- Krill 账号信息保存到 macOS Keychain，不写入源码或配置文件。

## 展示内容

- 展开栏展示使用统计、缓存率、钱包余额、刷新状态和当前生效套餐。
- 生效套餐卡片展示套餐名称、时间范围、额度进度和剩余时间。
- 悬浮球和贴边进度条用于快速感知当前可用状态，详细信息以展开栏为准。
- 钱包余额作为独立资金余额展示，不混入套餐卡片。
- 截图中的数值仅用于展示界面效果，不代表固定额度规则或实际账号数据。

具体展示会随账号套餐、余额和使用情况变化；README 不展开内部计算细节。

## 系统要求

- macOS 13.0 或更高版本。
- 当前预构建 Release 包面向 Apple Silicon Mac。
- 从源码构建需要 Swift 6.0 或更高版本。

## 下载安装

1. 打开 [GitHub Releases](https://github.com/lightconelab/krill-floating-ball/releases/latest)。
2. 下载最新的 `Krill-Floating-Ball-v*-macOS-arm64.zip`。
3. 解压后打开 `Krill Floating Ball.app`。
4. 首次启动时输入 Krill AI 邮箱和密码，或从菜单栏选择 `Krill 账号`。

当前预构建包已做 ad-hoc 签名，但没有使用 Apple Developer ID 公证。首次打开时如果被 macOS 阻止，可以右键点击 App 选择 `打开`，或在 `系统设置 -> 隐私与安全性` 中允许打开。

## 从源码构建

```bash
git clone https://github.com/lightconelab/krill-floating-ball.git
cd krill-floating-ball
./scripts/build_app.sh
open "dist/Krill Floating Ball.app"
```

生成本地 Release zip：

```bash
./scripts/package_release.sh
```

构建产物会输出到 `dist/` 目录。`dist/`、`.build/` 和 zip 包不会提交到 Git 仓库。

## 使用方式

1. 启动 `Krill Floating Ball.app`。
2. 在首次弹窗中输入 Krill AI 邮箱和密码。
3. 拖动悬浮球到合适位置。
4. 鼠标悬浮在悬浮球或贴边进度条上查看完整使用情况。
5. 在菜单栏中手动刷新、显示或隐藏桌面悬浮球、开启或关闭贴边进度条、调整自动刷新间隔、调整余额提醒区间、开启或关闭开机启动、管理 Krill 账号或退出应用。

## 性能

Krill Floating Ball 使用原生 AppKit 绘制，不依赖 Electron 或 WebView。应用会在展开栏收起后释放面板窗口，隐藏状态下减少绘制和窗口开销；Release 构建使用 `-Osize` 并对可执行文件执行 `strip -x`。

实际 CPU、内存和能耗会受设备、macOS 版本、显示器缩放、统计范围和账号数据量影响。以下截图来自一次本地运行，仅作为量级参考。

| CPU 占用 | 内存占用 |
| --- | --- |
| <img src="docs/images/floating-ball-cpu.png" width="520" alt="CPU 占用"> | <img src="docs/images/memory-usage.png" width="520" alt="内存占用"> |

<p align="center">
  <img src="docs/images/energy-impact.png" width="720" alt="能耗影响">
</p>

## 隐私

- Krill 邮箱和密码保存到 macOS Keychain。
- 登录信息仅用于连接 Krill AI 服务，不写入仓库、源码或本地配置文件。
- 项目不包含埋点、遥测、崩溃上报或第三方统计 SDK。

## 项目结构

```text
Sources/TrellisFloatingBall/   macOS AppKit 源码
Resources/                     Info.plist 和 App 图标资源
scripts/                       构建与打包脚本
docs/images/                   README 截图资源
dist/                          本地构建产物，已忽略
```

## 说明

Krill Floating Ball 是第三方辅助工具，实际展示以当前账号状态为准。欢迎通过 Issue 反馈复现步骤、截图、macOS 版本和应用版本。

## 许可证

MIT。详见 [LICENSE](LICENSE)。
