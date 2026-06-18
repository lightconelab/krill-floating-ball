# Krill Floating Ball

English | [中文简体](README.md)

Krill Floating Ball is a low-overhead native macOS floating widget for checking Krill AI subscription quota, today's usage, and wallet balance directly on the desktop.

> This is an unofficial desktop companion for Krill AI usage monitoring. It is not affiliated with or endorsed by Krill AI.

## Screenshots

| Menu Bar Icon | Menu Actions | Floating Ball |
| --- | --- | --- |
| <img src="docs/images/menubar-icon.png" width="96" alt="Menu bar icon"> | <img src="docs/images/menubar-menu.png" width="260" alt="Menu actions"> | <img src="docs/images/floating-ball.png" width="120" alt="Floating ball"> |

| Expanded Panel | Floating Overview |
| --- | --- |
| <img src="docs/images/expanded-panel.png" width="420" alt="Expanded panel"> | <img src="docs/images/floating-overview.png" width="520" alt="Floating overview"> |

| Krill Account Comparison |
| --- |
| <img src="docs/images/krill-profile.png" width="900" alt="Krill account comparison"> |

| CPU Usage | Memory Usage | Energy Impact |
| --- | --- | --- |
| <img src="docs/images/cpu-usage.png" width="300" alt="CPU usage"> | <img src="docs/images/memory-usage.png" width="300" alt="Memory usage"> | <img src="docs/images/energy-impact.png" width="300" alt="Energy impact"> |

## Features

- Native Swift/AppKit implementation with no Dock icon and a lightweight menu bar entry.
- Always-on-top draggable 80px floating ball.
- Low-overhead rendering: the floating animation runs only when needed, and the hover panel window is released after collapse.
- Liquid quota indicator: the fill level follows weekly remaining quota, with stronger colors and pulse effects at low quota.
- Hover panel showing today's spend, request count, cache rate, wallet balance, refresh time, and all active subscriptions, making it easy to compare against the Krill account center.
- Configurable auto-refresh interval from the menu bar. The default interval is 30 seconds.
- Manual refresh, token setup, token clearing, launch-at-login toggle, and quit actions are available from the menu bar.
- Failed refreshes keep the previous successful data and do not overwrite the last successful refresh time.
- Krill API token is stored in macOS Keychain, not in source files or local config files.
- App and menu bar icons use a capture-ball-inspired `K` mark. The menu bar icon follows the system light/dark appearance.

## Requirements

- macOS 13.0 or later.
- Apple Silicon Mac for the current prebuilt release asset.
- Swift 6.0 or later if building from source.

## Install From Release

1. Download the latest zip from [GitHub Releases](https://github.com/lightconelab/krill-floating-ball/releases/latest).
2. Unzip `Krill-Floating-Ball-v0.2.1-macOS-arm64.zip`.
3. Open `Krill Floating Ball.app`.
4. On first launch, set your Krill API token from the prompt or from the menu bar item `设置 Krill Token...`.

The current app is ad-hoc signed but not notarized with an Apple Developer ID. If macOS blocks the first launch, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

## Build From Source

```bash
git clone https://github.com/lightconelab/krill-floating-ball.git
cd krill-floating-ball
./scripts/build_app.sh
open "dist/Krill Floating Ball.app"
```

To produce the release zip locally:

```bash
./scripts/package_release.sh
```

The packaged app will be written to `dist/`.

## Usage

1. Launch `Krill Floating Ball.app`.
2. Enter your Krill API token when prompted, or choose `设置 Krill Token...` from the menu bar.
3. Drag the floating ball to your preferred position.
4. Hover over the ball to inspect today's usage, wallet balance, and active subscriptions.
5. Use the menu bar to refresh manually, change the auto-refresh interval, enable or disable launch at login, clear the token, or quit the app.

## Data Scope

- Active subscriptions are filtered by `active = true` and the current time being within `subscription_start_at` and `subscription_end_at`.
- Weekly quota aggregates all active subscriptions.
- When `plan.billing_type = usd_monthly`, the subscription total quota is `quota.daily_limit_usd`, and it is not counted as weekly quota.
- When `plan.billing_type = usd_weekly`, weekly quota is `quota.daily_limit_usd`, and the subscription total quota is `quota.daily_limit_usd * 4`.
- Today's statistics are requested from the local day's `00:00:00` to the current time, using the user's current time zone.
- If an API refresh fails, the app waits for the next scheduled refresh or manual refresh and keeps the last successful refresh timestamp unchanged.

## Privacy

- The app calls Krill APIs directly from your Mac.
- The API token is saved in macOS Keychain.
- The repository does not include tokens, secrets, analytics, telemetry, or crash reporting.

## Development Notes

The release artifact is intentionally not committed to Git. Build outputs are ignored via `.gitignore`; downloadable app bundles are distributed through GitHub Releases.

## License

MIT. See [LICENSE](LICENSE).
