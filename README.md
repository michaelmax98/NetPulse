# NetPulse

**A featherweight macOS menu bar meter for live network speed — download and upload at a glance, every second.**

<p align="center">
  <a href="https://github.com/michaelmax98/NetPulse/releases/latest/download/NetPulse.dmg">
    <img src="docs/download-button.svg" width="232" alt="Download for macOS (DMG)">
  </a>
  <br>
  <sub>Direct download · macOS 13+ · free &amp; open source · <a href="https://github.com/michaelmax98/NetPulse/releases/latest">all releases</a> · <a href="https://buymeacoffee.com/michaelmaxwell">☕ buy me a coffee</a></sub>
</p>

[![Latest release](https://img.shields.io/github/v/release/michaelmax98/NetPulse?label=latest&color=2ea44f)](https://github.com/michaelmax98/NetPulse/releases/latest)
[![CI](https://github.com/michaelmax98/NetPulse/actions/workflows/ci.yml/badge.svg)](https://github.com/michaelmax98/NetPulse/actions/workflows/ci.yml)

Tiny stacked down/up numbers sit in your menu bar — blue for download, green for upload, red when you're offline. Click for the full panel: live speeds, a history chart, session totals, and per-interface detail.

## Install

1. Click the **Download** button above (it always grabs the newest DMG)
2. Open it and drag **NetPulse** into **Applications**
3. Launch it — the meter appears in your menu bar

> **First launch on a fresh download:** releases aren't notarized with a paid Apple Developer ID, so macOS may block the first open. Go to **System Settings → Privacy & Security**, scroll to the "NetPulse was blocked" notice, and click **Open Anyway** (older macOS: right-click the app → **Open**). Only needed once.

Requires macOS 13 Ventura or later. No permissions — traffic counters come from the same public interface statistics `netstat` prints. No network use except update checks.

## Features

- **Live down/up speed** — sampled once a second from the kernel's per-interface byte counters. Menu bar modes: **both** (stacked), **down only**, **up only**, or a quiet **icon** — all the same fixed width, so your menu bar never shifts.
- **Offline at a glance** — the glyph turns red the moment no interface is connected.
- **History chart** — download and upload over the last **15m / 1h / 24h**, kept in memory only.
- **Session totals** — data downloaded and uploaded since launch, plus peak speeds.
- **Interfaces** — live per-interface rates with friendly names (Wi-Fi, Ethernet…). VPN tunnels are listed separately and never double-counted in the totals.
- **Bytes or bits** — read speeds as `MB/s` or flip one switch for `Mbps` to compare against your ISP plan.
- **In-app updates** — checks this repo's Releases page; one press downloads, verifies the published sha256, swaps the app in place, and relaunches.
- Native SwiftUI, light/dark aware, no Dock icon, optional Launch at Login.

## Light by design

NetPulse is built to be invisible in Activity Monitor, not just in the menu bar:

- One `sysctl` read per second — the same counters `netstat -ib` prints, a few microseconds of work, no processes spawned.
- The menu bar glyph is re-drawn **only when the displayed number actually changes** — an idle connection costs zero rendering.
- History lives in a bounded in-memory buffer; NetPulse does **zero disk I/O** while running.
- When your displays sleep, sampling stops entirely and resumes on wake.
- Charts exist only while the panel is open.

Native Swift, no Electron, no helper daemons — a fraction of a percent of CPU and a few tens of MB of memory, most of which is Apple's UI framework baseline shared with every other Swift app.

## Build from source

```bash
git clone https://github.com/michaelmax98/NetPulse.git
cd NetPulse
swift run -c release      # run it directly
./build-app.sh            # or build build/NetPulse.app
```

Releases are built by GitHub Actions: the release workflow compiles on a macOS runner, packages the DMG, and publishes it with a stable-named `NetPulse.dmg` so the download button always serves the newest version.

## How it reads the numbers

Every second NetPulse asks the kernel's routing table for interface statistics (`sysctl NET_RT_IFLIST2` — public API, no privileges) and diffs the lifetime byte counters to get bytes/second. Totals count physical interfaces (`en*`: Wi-Fi, Ethernet, tethering). VPN tunnels (`utun*`) are shown in the Interfaces list but excluded from totals, since their traffic also crosses the physical interface and would double-count.

## Siblings

NetPulse is part of a small family of one-job menu bar apps: [BetterBattery](https://github.com/michaelmax98/BetterBattery) (live battery wattage) and [DayDial](https://github.com/michaelmax98/DayDial) (the day, burning down).

## Support

Free and open source. If it earns a spot in your menu bar, you can [buy me a coffee](https://buymeacoffee.com/michaelmaxwell) ☕

## License

[MIT](LICENSE)
