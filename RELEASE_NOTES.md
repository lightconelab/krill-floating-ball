# Krill Floating Ball v0.1.0

This is the first public release of Krill Floating Ball, a lightweight native macOS floating usage monitor for Krill AI accounts.

## Highlights

- Native AppKit menu bar app with no Dock icon.
- Always-on-top 80px floating ball showing weekly remaining quota.
- Liquid level and warning color change based on remaining weekly quota percentage.
- Hover panel with today's spend, request count, cache rate, wallet balance, refresh time, and active subscription cards.
- Configurable auto-refresh interval, defaulting to 30 seconds.
- Manual refresh and token management from the menu bar.
- Krill API token is stored in macOS Keychain.

## Download

Download `Krill-Floating-Ball-v0.1.0-macOS-arm64.zip`, unzip it, and open `Krill Floating Ball.app`.

The current prebuilt package is for Apple Silicon Macs. Intel Macs can build from source with the included script.

## macOS Security Notice

This release is ad-hoc signed but not notarized with an Apple Developer ID. On first launch, macOS may show a security warning. If you trust the source, right-click the app and choose `Open`, or allow it in `System Settings -> Privacy & Security`.

## Build From Source

```bash
git clone https://github.com/lightconelab/krill-floating-ball.git
cd krill-floating-ball
./scripts/build_app.sh
open "dist/Krill Floating Ball.app"
```
