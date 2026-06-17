# Changelog

All notable changes to this project will be documented in this file.

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
