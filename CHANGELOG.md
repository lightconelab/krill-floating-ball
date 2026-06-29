# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

## v0.2.8 - 2026-06-29

- Renamed the usage statistic range buttons to `月卡单窗口` and `月卡`, and scoped both ranges to the earliest-started active monthly plan.
- Reduced refresh and statistic-switch memory overhead by reusing request coders, reusing the API date formatter, avoiding an extra full-file mmap for stats JSON validation, optimizing stats string scanning, and releasing the account-validation API client after the account dialog closes.
- Removed system username/password content-type hints from the Krill account dialog to avoid unnecessary macOS AutoFill and LocalAuthentication helper activation.
- Refreshed Chinese and English README screenshots for the expanded panel, monthly statistic ranges, edge progress bar, menu, account dialog, CPU, memory, and energy references.

## v0.2.7 - 2026-06-29

- Added a lightweight `_kfp` fingerprint cookie generated locally for Krill login requests, keeping data fetching on direct HTTP requests without WebKit, Safari, or JavaScriptCore.
- Reorganized the menu bar actions into clearer groups, renamed account and balance controls, merged the floating ball show/hide actions into one checked menu item, and moved credential clearing into the Krill account dialog.
- Added the balance alert range dialog to the public screenshots and moved "restore default" into that dialog.
- Fixed the menu bar capture-ball icon so the divider line no longer crosses the central `K` button.
- Fixed clearing login information so the floating ball and expanded panel immediately reset to a clean missing-account state instead of retaining stale quota, wallet, usage, cache, or subscription data.
- Changed active subscription cards to preserve the `subscription` API response order after active-time filtering.
- Refreshed Chinese and English README screenshots and updated the documented menu labels, account flow, balance alert wording, and subscription ordering rules.
- Simplified recently touched code paths around empty-state labels, HTTP status validation, stat-card drawing, and unused widget callbacks while preserving behavior.

## v0.2.6 - 2026-06-25

- Switched the public setup flow to Krill email/password login stored in macOS Keychain, with runtime API tokens kept in memory only.
- Added standard edit menu support and explicit Cmd/Ctrl editing shortcuts for the Krill account prompt, including paste in the password field.
- Made credential changes cancel stale refresh work and start a fresh fetch immediately, so the widget updates as soon as login succeeds instead of waiting for a queued refresh.
- Disabled credential prompt autofill content type, text completion, and Writing Tools affordances to reduce unnecessary system helper activation.
- Tightened network memory behavior by disabling cookies, cache, and URL credential storage, invalidating per-request URLSession instances, and releasing heap pressure after refresh and panel teardown.
- Rewrote the Chinese and English README for public open-source use, refreshed screenshots, and removed obsolete token-era README images.

## v0.2.5 - 2026-06-23

- Fixed the widget restore path so showing the hidden widget always brings back the normal floating ball unless it is actually attached to a screen edge.
- Kept the floating ball draggable while the expanded panel is open by ordering the ball window above the panel window.
- Improved expanded-panel placement so it adapts to the available side space and reduces unnecessary blank width.
- Refined usage statistic cards with centered icon/title headers, centered values, and sparklines without the extra baseline.
- Reduced memory growth when switching larger statistic ranges by requesting long ranges in 7-day chunks, parsing only the required JSON fields, limiting trend samples, and releasing heap pressure between chunks.
- Refreshed README screenshots for the expanded panel, floating overview, and edge-bar overview.

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
