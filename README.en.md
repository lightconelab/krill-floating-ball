# Krill Floating Ball

[中文简体](README.md) | English

Krill Floating Ball is a native macOS desktop widget for monitoring Krill AI subscription quota, usage statistics, cache rate, and wallet balance. It shows the current quota level as an 80px liquid floating ball, can snap to a slim edge progress bar near screen borders, and expands into a detailed hover panel.

> This project is an unofficial desktop companion for Krill AI. It is not affiliated with or endorsed by Krill AI. Quota, wallet, and usage values in screenshots are examples only.

## Preview

### Floating Ball And Expanded Panel

<p align="center">
  <img src="docs/images/floating-overview.png" width="880" alt="Krill Floating Ball overview">
</p>

| Floating Ball | Expanded Panel |
| --- | --- |
| <img src="docs/images/floating-ball.png" width="160" alt="Floating ball"> | <img src="docs/images/expanded-panel.png" width="760" alt="Expanded panel"> |

### Edge Progress Bar

When the widget is near a screen edge, it can snap into a progress bar. Left and right edges use a vertical bar, while top and bottom edges use a horizontal bar. Hovering still opens the full information panel.

| Edge Panel | Vertical Bar | Horizontal Bar |
| --- | --- | --- |
| <img src="docs/images/edge-progress-overview.png" width="700" alt="Edge progress bar with expanded panel"> | <img src="docs/images/edge-progress-vertical.png" width="90" alt="Vertical edge progress bar"> | <img src="docs/images/edge-progress-horizontal.png" width="240" alt="Horizontal edge progress bar"> |

### Menu Bar And Account

| Menu Icon | Menu Actions |
| --- | --- |
| <img src="docs/images/menubar-icon.png" width="96" alt="Menu bar icon"> | <img src="docs/images/menubar-menu.png" width="240" alt="Menu actions"> |

| Krill Account | Missing Account |
| --- | --- |
| <img src="docs/images/login-prompt.png" width="520" alt="Krill account prompt"> | <img src="docs/images/missing-login-overview.png" width="720" alt="Missing account state"> |

## Features

- Native Swift/AppKit implementation with no Dock icon and a persistent macOS menu bar item.
- Always-on-top draggable 80px liquid floating ball.
- Edge progress bar enabled by default: the widget snaps near screen edges, supports multi-display setups, and can be disabled from the menu bar.
- Hover panel showing usage statistics, wallet balance, refresh status, and all active subscriptions.
- Usage statistics ranges: `Monthly Window`, `Monthly Plan`, `Today`, `7 Days`, and `30 Days`.
- Spend, requests, and Tokens include sparklines; cache rate is shown per channel.
- Configurable automatic refresh interval, defaulting to 30 seconds. The next automatic refresh is scheduled after the previous refresh completes.
- Manual refresh, launch at login, balance alert ranges, Krill account management, desktop widget visibility, edge progress bar mode, and quit actions from the menu bar.
- Failed refreshes keep the last successful data and show a status badge beside the refresh time without overwriting the last successful refresh timestamp.
- Krill account information is stored in macOS Keychain and is not written to source files or local configuration.

## What It Shows

- The expanded panel shows usage statistics, cache rate, wallet balance, refresh status, and active subscriptions.
- Active subscription cards show plan name, time range, quota progress, and remaining time.
- The floating ball and edge progress bar provide a quick visual status indicator; the expanded panel remains the detailed view.
- Wallet balance is shown separately from subscription cards.
- Values in screenshots are UI examples only and do not document fixed quota rules or real account data.

The exact display changes with the current account's subscriptions, balance, and usage. This README intentionally does not document internal calculation details.

## Requirements

- macOS 13.0 or later.
- The current prebuilt release asset targets Apple Silicon Macs.
- Swift 6.0 or later when building from source.

## Install From Release

1. Open [GitHub Releases](https://github.com/lightconelab/krill-floating-ball/releases/latest).
2. Download the latest `Krill-Floating-Ball-v*-macOS-arm64.zip`.
3. Unzip it and open `Krill Floating Ball.app`.
4. On first launch, enter your Krill AI email and password, or choose `Krill 账号` from the menu bar.

The current prebuilt app is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

## Build From Source

```bash
git clone https://github.com/lightconelab/krill-floating-ball.git
cd krill-floating-ball
./scripts/build_app.sh
open "dist/Krill Floating Ball.app"
```

Create a local release zip:

```bash
./scripts/package_release.sh
```

Build outputs are written to `dist/`. `dist/`, `.build/`, and zip files are ignored by Git.

## Usage

1. Launch `Krill Floating Ball.app`.
2. Enter your Krill AI email and password in the first-launch prompt.
3. Drag the floating ball to a preferred position.
4. Hover over the floating ball or edge progress bar to inspect detailed usage.
5. Use the menu bar to refresh manually, show or hide the desktop widget, enable or disable edge progress bar mode, change the automatic refresh interval, adjust balance alert ranges, enable or disable launch at login, manage the Krill account, or quit the app.

## Performance

Krill Floating Ball is drawn with native AppKit and does not use Electron or WebView. The app releases the hover panel window after collapse and reduces drawing and window overhead while hidden. Release builds use `-Osize` and strip the executable with `strip -x`.

Actual CPU, memory, and energy impact depend on the device, macOS version, display scaling, selected statistic range, and account data size. The screenshots below are from one local run and should be treated as rough reference points.

| CPU Usage | Memory Usage |
| --- | --- |
| <img src="docs/images/floating-ball-cpu.png" width="520" alt="CPU usage"> | <img src="docs/images/memory-usage.png" width="520" alt="Memory usage"> |

<p align="center">
  <img src="docs/images/energy-impact.png" width="720" alt="Energy impact">
</p>

## Privacy

- Krill email and password are stored in macOS Keychain.
- Login information is only used to connect to the Krill AI service and is not written to the repository, source files, or local config files.
- The project does not include analytics, telemetry, crash reporting, or third-party tracking SDKs.

## Project Layout

```text
Sources/TrellisFloatingBall/   macOS AppKit source code
Resources/                     Info.plist and app icon resources
scripts/                       Build and packaging scripts
docs/images/                   README screenshots
dist/                          Local build output, ignored by Git
```

## Notes

Krill Floating Ball is a third-party companion tool. The actual display depends on the current account state. Please include reproduction steps, screenshots, macOS version, and app version when opening an issue.

## License

MIT. See [LICENSE](LICENSE).
