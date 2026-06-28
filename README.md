# Brawl Stars Latency Kit — Samsung Galaxy Tab S7

A practical, no-root toolkit to drive Brawl Stars latency on a Tab S7
(SM-T870/T875/T876B) as close to the network floor as the device allows.

## What this actually does

Brawl Stars round-trip time is governed by, in order of impact:

1. **Network path** to Supercell's regional server (≈ 30–80 ms is realistic
   from a home connection; under 20 ms only if a server is in your metro).
2. **WiFi/radio jitter** — bad channel, 2.4 GHz, distance, or a noisy AP
   adds 10–60 ms of variance.
3. **Frame pacing / input lag** — 60 Hz vs 120 Hz, animation scale, dropped
   frames under thermal throttle. Worth ~8–16 ms of perceived lag.
4. **Background contention** — Samsung's bloat (Bixby, Game Launcher
   overlays, Smart Switch, Galaxy Store) stealing CPU and waking the radio.

This kit attacks #2, #3, and #4. It does **not** attempt #1 — no app or
script can route around physics.

## What this does NOT do (and why)

- **Does not disable Knox, SELinux, or system-level security.** None of
  those affect game latency. Disabling them breaks Samsung Pay, banking
  apps, Secure Folder, and OTA updates. The benefit is zero. We're not
  doing it.
- **Does not require root.** You said you uprooted, good — Knox flag
  already tripped is bad enough. Everything here works over ADB on stock.
- **Does not install VPNs, "ping boosters," or "game accelerators."** They
  add a hop and make latency worse on average. Snake oil.
- **Does not modify network buffers via sysctl.** Requires root and the
  defaults on Android 13+ are fine for a 100 Mbps link.

## Realistic expectations

On a Tab S7 in good WiFi conditions, you should see:

- p50 ping: drops by ~5–10 ms (channel + DNS + radio sleep)
- p99 ping (the spikes that get you killed): drops by ~20–80 ms
  (background app eviction + Game Booster Plus performance mode)
- Input lag: ~8 ms lower (120 Hz lock + animation scale 0)

If your home network is the bottleneck, none of this helps — fix that
first (`network/latency-check.sh`).

## How to use

1. Run `network/latency-check.sh` from any machine on the same network as
   the tablet, OR from Termux on the tablet. This tells you whether your
   problem is the network or the device.
2. Follow `device/game-mode-checklist.md` for one-time Tab S7 settings.
   ~15 minutes, all in the UI, no PC needed.
3. Optionally, run `adb/optimize.sh` from a PC with the tablet in USB
   debugging mode. This is the ADB pass — kills bloat services, sets
   animation scale to 0, raises background process priority for Brawl
   Stars. Reversible with `adb/restore.sh`.

## Tab S7 specifics

- SoC: Snapdragon 865+ (or Exynos 990 on T870 — same approach works)
- Display: 120 Hz LTPS. Must be force-locked; Samsung drops to 60 Hz under
  battery saver, low brightness, or "adaptive" mode.
- Brawl Stars is locked to 60 FPS by Supercell on Android, BUT the
  compositor still runs at 120 Hz, so touch sampling is 2x faster on
  120 Hz. This is the single biggest input-lag win.
