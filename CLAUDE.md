# NetPulse — development notes

macOS menu bar app (SwiftUI, macOS 13+, SwiftPM) showing live network
down/up throughput. Sibling of BetterBattery and DayDial — shares their
machinery and conventions.

## Conventions that must hold

- **Update controls stay at the very bottom of the panel** (with Quit) —
  explicit user preference carried across the whole app family.
- **Menu bar glyph must be rendered offscreen via ImageRenderer** to an
  NSImage — the status item pipeline mangles live layered SwiftUI views.
  The glyph keeps a **fixed width in every mode** (user preference).
- **Efficiency is a feature** (explicit user requirement): one sysctl read
  per second, re-render the glyph only when its content string changes,
  history is RAM-only (zero disk I/O), sampling pauses while displays
  sleep. Don't add timers, disk writes, or per-tick allocations casually.
- **Never change `CFBundleIdentifier`** (`com.netpulse.app`): settings are
  keyed to it.
- The in-place updater never hardcodes the bundle name — it installs
  whatever `.app` the release DMG contains.
- Releases ship via `release.yml` **workflow_dispatch** with a `version`
  input (tag created server-side); each release uploads
  `NetPulse-<version>.dmg` plus stable-named `NetPulse.dmg`. CI green first.
- Traffic totals count `en*` interfaces only; `utun*`/`ppp*` are listed as
  VPN rows but excluded from totals (double-count otherwise).
- The app source is mirrored into `michaelmax98/ClaudeCode`
  (branch `claude/macos-battery-widget-gl5ba3`, folder `NetPulse/`).
