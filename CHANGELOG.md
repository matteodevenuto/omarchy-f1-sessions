# Changelog

## 0.3.0 — 2026-08-25

- Persist display and alert settings when the widget is hosted inside another
  bar container.
- Add a compact, Omarchy-native checkered-flag display mode while retaining
  the wide F1 logo mode, and use the compact icon by default.
- Add an instant-startup and offline schedule cache with visible refresh and
  failure status.
- Deduplicate session alerts across monitors and shell restarts.
- Add alert filters for all sessions, competitive sessions (no practice), or
  Grand Prix and Sprint races.
- Combine notification and sound state into one panel action and add a separate
  alert-filter action.
- Add a panel refresh action and keyboard-accessible footer controls.
- Add the `status` IPC method for cache, source, error, and alert diagnostics.

## 0.2.0

- Add session alerts with an optional radio-style sound.
- Add OpenF1-to-Jolpica fallback and automatic season rollover.
