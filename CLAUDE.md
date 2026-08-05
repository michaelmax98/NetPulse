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

- **Live values must ease, not snap.** This is what separates "smooth" from
  "laggy" across this app family, and NetPulse was the worst offender: the
  model publishes at 1 Hz and nothing in the panel had a transition, so every
  rate teleported between discrete states once a second. Give numbers
  `.contentTransition(.numericText())` and give bars/rings an
  `.animation(.easeOut(…), value:)`. Key the animation on a **quantised**
  value so ordinary sample jitter doesn't restart it, and reuse one
  quantisation across the panel so everything moves together.

- **Never animate with `TimelineView`.** Its schedule needs SwiftUI to
  re-evaluate the view every frame, and it does **not** tick inside a
  `MenuBarExtra(.window)` panel — the view then only redraws on the model's
  1 Hz publish, so anything time-based lurches a whole second at a time.
  (It shipped that way in BetterBattery's fan icon.) Use a render-server
  animation instead: `repeatForever` or `.animation(value:)`, handed to the
  compositor once, no per-frame SwiftUI work, no new timer.

- **Panel-only animation is free at idle.** The panel is unrendered while the
  menu bar item is closed, so easing costs nothing until someone opens it.
  That is the only reason it's allowed: never move a continuous animation into
  the glyph path, and never drive one with a repeating `Timer`.

- **Keep per-tick work out of view bodies.** A panel body re-evaluates on
  every 1 Hz publish. `windowedSamples` used to filter all 17,280 retained
  samples there, once a second, for as long as the panel was open; the history
  is append-ordered, so the window cutoff is found by bisection instead.
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
