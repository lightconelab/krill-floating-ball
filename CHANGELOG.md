# Changelog

All notable changes to this project will be documented in this file.

## v0.2.1 - 2026-06-18

- Added refreshed README screenshots for the menu bar icon, menu actions, floating ball, expanded panel, floating overview, and Krill account comparison.
- Added CPU, memory, and energy screenshots for public overhead reference.
- Updated the menu bar icon to match the app icon style with a central `K` template mark.
- Refined the floating ball liquid animation and quota color thresholds while keeping low idle overhead.
- Improved expanded panel layout, typography, stat cards, active subscription cards, and progress bar rendering.
- Added a minimum auto-refresh interval guard to avoid accidental high-frequency refreshes.
- Released the hover panel window after collapse to reduce long-running memory usage.
- Corrected quota calculation for `usd_monthly` and `usd_weekly` billing types.
- Increased active subscription card typography for better readability.

## v0.2.0 - 2026-06-17

- Added launch at login support using the native macOS login item service.
- Added a menu bar toggle for enabling or disabling launch at login.
- Added a Krill-themed app icon inspired by a capture ball with a central `K`.

## v0.1.0 - 2026-06-17

Initial public release.

- Added a native macOS menu bar app with an always-on-top floating usage ball.
- Added an 80px liquid quota indicator driven by weekly remaining quota.
- Added hover panel with today's usage, wallet balance, refresh time, and active subscriptions.
- Added configurable auto-refresh interval and manual refresh from the menu bar.
- Added macOS Keychain storage for the Krill API token.
- Added low-overhead AppKit implementation with a lazy-created hover panel.
