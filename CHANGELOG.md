# Changelog

All notable changes to this project will be documented in this file.

## v0.2.4 - 2026-06-23

- Added multi-range usage statistics for quota week, subscription period, today, last 7 days, and last 30 days.
- Added Tokens to the statistics cards, with compact value formatting and sparklines for spend, requests, and Tokens.
- Redesigned cache-rate display as compact per-channel progress bars.
- Changed automatic refresh scheduling so the next interval starts after the previous refresh finishes.
- Added explicit API timeouts and an ephemeral no-cache URLSession for lower network memory overhead.
- Reduced memory growth when switching statistic ranges by canceling stale refreshes, sampling trend data during JSON decoding, and clearing hidden panel snapshots.
- Refreshed README screenshots for the expanded panel, floating overview, and edge-bar overview.

## v0.2.3 - 2026-06-21

- Added the edge quota bar mode: the floating ball can snap to a slim vertical or horizontal quota bar near screen edges, enabled by default and configurable from the menu bar.
- Tightened drag constraints so the widget cannot disappear outside the visible area, including multi-display setups.
- Improved CPU behavior by lowering idle animation cadence, stopping liquid animation when the edge bar is active, limiting redraw regions, and adding timer tolerance.
- Improved long-running memory stability by canceling refresh tasks on stop, releasing hidden panel windows, canceling pending hover-collapse work, and removing window observers when hidden.
- Cached the Keychain token after first successful load and stored it with `kSecAttrAccessibleAfterFirstUnlock` to reduce repeated password prompts in normal use.
- Updated active subscription display details, compact time labels, weekly/total quota rendering, and current quota calculation rules.
- Refreshed README screenshots for the expanded panel, floating overview, edge-bar overview, and CPU usage in edge-bar and floating-ball modes.
- Updated Chinese and English documentation for the new edge quota bar behavior and v0.2.3 release asset.

## v0.2.2 - 2026-06-18

- Corrected the floating ball weekly availability pool to include active total-quota subscriptions whose active time range overlaps the current weekly quota window.
- Kept the liquid color alert level tied to the weekly availability remaining percentage.
- Fixed the missing-token state so the floating ball no longer renders a gray liquid wave before a token is configured.
- Sorted active subscription cards by remaining total quota from high to low, with expiry time as the tie-breaker.
- Refreshed README screenshots for the floating overview, expanded panel, floating ball, missing-token state, and token prompt.
- Updated Chinese and English documentation to describe the current quota scope.

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
