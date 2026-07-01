# No-root deep-tuning playbook — Tab S7 (T870/T875/T876), no PC required

Everything below runs from the tablet itself via Wireless Debugging +
Shizuku/LADB. No root, no computer. It complements the generated
`apply.sh` from the toolchain — that script covers the prop/settings/
device_config surface; this playbook covers the knobs that *can't* be
expressed as `settings put` lines: `cmd` service calls, `pm` package
state, and the UI toggles whose backing keys you capture with the diff
workflow.

Read §1 first — the shell you run this from determines whether the
commands work at all.

---

## 0. The hardware you're tuning (facts, not myths)

| Block | What's on the board | Ceiling |
|---|---|---|
| CPU | SD865+ (kona): 4×A55 @1.80GHz, 3×A77 @2.42GHz, 1×A77 prime @3.09GHz | Governors live in sysfs — root-only to pin (see `root-only/if-you-reroot.md`) |
| GPU | Adreno 650 @ up to 670MHz | Same: devfreq pinning is root-only |
| Display | 11" LTPS TFT LCD, 2560×1600, **120Hz max** | The panel TCON tops out at 120Hz. There is no secure setting, hidden or otherwise, that produces 240Hz output. Anyone selling one is selling snake oil. |
| Touch | Samsung `sec_ts` IC, **240Hz scan in active mode** | Already 240Hz while your finger is on the glass. The root-only win is *forcing* active mode (§3.2). |
| Wi-Fi | Qualcomm FastConnect 6800 (QCA6390), Wi-Fi 6 | Firmware power-save is togglable from shell (§4.1) — the biggest no-root latency win in this doc |

So the honest frame for "push it to its limits" without root: you cannot
raise any clock. What you *can* do is remove every layer that sits
between the game and the silicon — Samsung's game throttler, the
energy-aware background machinery, display mode switching, Wi-Fi
power-save polling — so the hardware spends the whole match at the state
the stock governor picks for a foreground game, with nothing dragging it
back down.

---

## 1. Access layer: a privileged shell with no PC and no root

The `shell` uid (2000) is what ADB gives you. It holds
`WRITE_SECURE_SETTINGS`, `DEVICE_POWER`, `CHANGE_CONFIGURATION`, and can
call `pm`, `cmd`, `settings`, `device_config`, `dumpsys`. It can **not**
write sysfs, set `persist.vendor.*` props, or touch sysctls — that's the
root line, documented in `root-only/if-you-reroot.md`.

### 1a. Shizuku (recommended — survives across sessions)

1. Settings → Developer options → **Wireless debugging** → on.
2. Install Shizuku (Play Store). In Shizuku: *Start via Wireless
   debugging* → *Pairing* → split-screen Shizuku with the Wireless
   debugging pairing dialog, enter the 6-digit code.
3. Tap *Start*. Status shows "running — adb".
4. For a terminal: install Termux, then in Shizuku → *Use Shizuku in
   terminal apps* → export `rish` to Termux. Now `rish` in Termux drops
   you into a shell-uid shell.

Run the toolchain under `rish`, not plain Termux — Termux's own uid
can't `settings put secure` or read most of the dump surface:

```sh
rish
sh discover/dump-everything.sh
sh analyze/generate-tuning.sh /sdcard/scewin-dump-latest
sh /sdcard/scewin-dump-latest/apply.sh
```

### 1b. LADB (simplest, one app)

LADB bundles an ADB client and pairs with the tablet's own Wireless
debugging: split-screen LADB + Settings, pair with the code, done. Same
shell uid, same capabilities. Downside: you retype commands; there's no
`rish`-style export into Termux.

### 1c. What persists across reboot — plan around this

| Change | Survives reboot? |
|---|---|
| `settings put ...` (system/secure/global) | **Yes** |
| `device_config put ...` | Yes, **unless** Google's flag sync reverts it — see below |
| `pm disable-user`, `pm grant`, doze whitelist | **Yes** |
| `setprop debug.*` (everything in `apply.sh`'s prop section) | **No** — reapply each boot |
| `cmd wifi force-low-latency-mode`, `cmd power set-fixed-performance-mode-enabled` | **No** — reapply each boot |

Freeze `device_config` against remote resync (reversible):

```sh
device_config set_sync_disabled_for_tests persistent   # freeze
device_config get_sync_disabled_for_tests              # verify → persistent
device_config set_sync_disabled_for_tests none         # undo
```

For the non-persistent set: Shizuku has *Start on boot (wireless
debugging)*; pair it with Tasker/MacroDroid's Shizuku support to rerun
`apply.sh` + the §5 preflight block automatically, or just run the
preflight by hand before a session.

---

## 2. Hardware state tuning — CPU clusters + Adreno 650

### 2.1 Neutralize GOS (Game Optimizing Service) — the single biggest one

Samsung routes every game through `com.samsung.android.game.gos`, which
applies per-title fps caps, resolution scaling, and thermal budgets —
the same mechanism as the S22 throttling scandal. On a Tab S7 it is the
main reason a game doesn't hold the clocks the stock governor would
otherwise give it.

```sh
pm disable-user --user 0 com.samsung.android.game.gos
```

Caveats, honestly:
- Game Booster's overlay/stats stop working (its policy engine is gone —
  that's the point).
- On some firmware, Game Launcher nags or a game briefly misbehaves on
  first launch. If anything breaks:

```sh
pm enable com.samsung.android.game.gos        # full revert
```

Softer alternative if you want to keep GOS: Game Booster → set the game
to performance priority, and check Galaxy Store for the *Game Plugins /
Perform+* module to raise GOS's own limits instead of removing it.

### 2.2 Android 13 game mode (One UI 5)

With GOS out of the way, the AOSP GameManager path still applies. Put
Brawl Stars in performance mode:

```sh
cmd game list-modes com.supercell.brawlstars      # check first — most games only list mode 1
cmd game set --mode 2 com.supercell.brawlstars    # 2 = performance
```

**Verified on-device**: Brawl Stars returns `Game mode: 2 not supported by
com.supercell.brawlstars` — it doesn't opt into the Android GameManager
API at all (most third-party games don't; this API needs manifest
support from the app). Check `list-modes` first and only bother with
`set --mode` if it actually lists more than the default. Not a loss —
GOS removal (§2.1) and fixed performance mode (§2.3) are the levers that
matter for a game with no GameManager support.

### 2.3 Fixed performance mode — clock *stability* over burst

```sh
cmd power set-fixed-performance-mode-enabled true
```

This is `PowerManager` MODE_FIXED_PERFORMANCE — the benchmark-stability
mode. Understand the trade before judging it: it pins clocks at the
*sustainable* level, which **caps peak burst** but eliminates DVFS
dither entirely. For a twitch game the p99 frame time usually matters
more than the p50, so test a few matches with it on, a few off, and keep
whichever feels better. Reset:

```sh
cmd power set-fixed-performance-mode-enabled false
```

(If your build rejects the verb, run `cmd power` bare — it prints the
exact subcommand list for your firmware.)

### 2.4 Samsung CPU responsiveness knob

```sh
settings put global sem_enhanced_cpu_responsiveness 1
```

One UI's own input-boost escalation (the same key performance apps
flip). Persists. `settings delete global sem_enhanced_cpu_responsiveness`
to restore default.

### 2.5 AOT-compile the game

Kill JIT warm-up stutter in the first matches after an update:

```sh
cmd package compile -m speed -f com.supercell.brawlstars
```

Takes a minute; rerun after each game update. No downside besides a bit
of storage.

### 2.6 Keep the scheduler's hands off the game

`apply.sh` already disables app standby, adaptive battery, the cached-app
freezer and phantom-process kills. Add the per-app exemptions on top:

```sh
cmd deviceidle whitelist +com.supercell.brawlstars   # doze exemption
am set-standby-bucket com.supercell.brawlstars active
```

And RAM Plus (zram-backed swap — pure latency poison on 6/8GB of real
RAM):

```sh
settings put global ram_expand_size 0    # then reboot
settings get global ram_expand_size      # verify; some CSCs floor it at 2
```

If your firmware refuses 0, use the smallest value the Settings UI
offers.

### 2.7 Thermal — the part you can't command away

The thermal engine (`thermal-engine`, `siop`) is vendor-blob territory;
no shell command moves its trip points. What actually works: max
brightness is the single biggest heat source on this LCD — every notch
down buys sustained clock headroom. Take the case off; the back panel is
the heatsink.

---

## 3. Display & touch layer

### 3.1 Force 120Hz, kill mode-switching

One UI's "Adaptive" motion smoothness drops to 60Hz on static content
and sometimes mid-game on low brightness. The mode switch itself is a
visible hitch. Pin it — all three, Samsung reads its own key *and* the
AOSP pair:

```sh
settings put secure refresh_rate_mode 2
settings put system peak_refresh_rate 120.0
settings put system min_refresh_rate 120.0
```

Verify: Developer options → *Show refresh rate* overlay — it must read
120 and never flicker to 60, including on the home screen. Revert:
`settings put secure refresh_rate_mode 0` and delete the two system
keys.

### 3.2 The 240Hz question, answered straight

- **Panel**: 120Hz is a hardware ceiling (TCON). No setting exceeds it.
- **Touch**: already scans at 240Hz whenever a finger is down. The IC
  drops to a low idle rate between touches; *forcing* permanent active
  mode (`force_touch_active` on the `sec_ts` node) is root-only —
  `root-only/if-you-reroot.md` §5. In practice Brawl Stars keeps a
  finger on the glass nearly continuously, so you're at 240Hz for the
  inputs that matter even without it.

What you *can* trim without root is the software path between the touch
IRQ and the game — that's §3.3/§3.4.

### 3.3 Render pipeline: one frame of latency back

The `debug.sf.*` block in your generated `apply.sh` is the meat here —
disable SurfaceFlinger backpressure, latch unsignaled buffers, pull the
app/SF vsync phase offsets earlier. Together they're worth roughly a
frame (~8ms at 120Hz) of input-to-photon latency, at a small tearing/
jank risk that Brawl Stars' light GPU load rarely triggers. These are
props → **gone every reboot**; they're the main reason the §5 preflight
exists.

### 3.4 Input pipeline

Also in `apply.sh`: animations to 0, input filter chain off, input-event
tracing off, `pointer_speed 7`, immersive-mode confirmation suppressed,
haptics off (the vibration wake path costs single-digit ms). On top:

- **In-game**: Brawl Stars → settings → highest FPS option your version
  offers. Even where the game renders 60fps, the 120Hz display + shorter
  scanout still cuts present-to-photon latency vs a 60Hz mode.
- **GPUWatch off** (Developer options) — it's a profiling overlay.
- **S Pen hover scanning**: if you never use the pen, disable its
  detection features (Settings → S Pen), then find your firmware's
  backing keys: `settings list secure | grep -i pen` before/after, or the
  `diff/diff-state.sh` workflow, and pin them in your own notes.
- **Touch sensitivity** (Settings → Display): only helps with a screen
  protector; it raises IC gain, not scan rate.

---

## 4. Network stack — Wi-Fi latency

### 4.1 Force low-latency mode (try this first — may be blocked on your firmware)

```sh
cmd wifi force-low-latency-mode enabled
```

In stock AOSP this forces the `WIFI_MODE_FULL_LOW_LATENCY` lock
globally: the QCA6390 firmware disables IEEE 802.11 power-save (the
doze/poll cycle that adds a spiky 20–100ms to packets while the radio
sleeps between beacons) and tightens interrupt coalescing.

**Verified finding**: on One UI (tested via Shizuku on a T870), this
throws `SecurityException: Uid 2000 does not have access to
force-low-latency-mode wifi command`. Samsung's `WifiServiceImpl` gates
this specific subcommand behind a permission the shell uid doesn't hold
on this build — it's not a typo or a missing flag, it's firmware
hardening, and there's no shell-level way around it. If it works for
you, great:

- Verify: `dumpsys wifi | grep -i latency`, then §6's ping test.
- Does **not** persist across reboot → §5 preflight.
- Revert: `cmd wifi force-low-latency-mode disabled`.

**If you get the SecurityException instead**, this drops to the root
line (kernel/driver power-save params, `root-only/if-you-reroot.md`
territory) *unless* Samsung exposes an equivalent as a Settings toggle.
Check Settings → Connections → Wi-Fi → (tap your network) → Advanced,
and any "Intelligent Wi-Fi" power-saving switch. Use the repo's own
discovery loop to find the backing key instead of guessing:

```sh
sh discover/dump-everything.sh        # snapshot A
# flip the Wi-Fi power-saving toggle in Settings
sh discover/dump-everything.sh        # snapshot B
sh diff/diff-state.sh dump-A dump-B   # → the exact key Samsung uses
```

Whatever key that surfaces is worth a PR back into
`analyze/known-impact-keys.tsv` — this is exactly the gap the curated
list can't close from outside a real device.

### 4.2 Kill the scan machinery

Every background scan steals the radio from your game for 50–150ms.
`apply.sh` already sets `wifi_scan_throttle_enabled 0` (faster recovery)
and `ble_scan_always_enabled 0`. Add the shell-level ones — on Android
13 the canonical switches are `cmd wifi`, not Settings keys:

```sh
cmd wifi set-scan-always-available disabled
```

Plus UI toggles (their backing keys are CSC-dependent — capture yours
with `diff/diff-state.sh` if you want them scripted):

- Settings → Location → Location services → **Wi-Fi scanning off**,
  **Bluetooth scanning off**
- Settings → Connections → More → **Nearby device scanning off**
- Intelligent Wi-Fi: **Switch to mobile data off** (T875/T876),
  **Detect suspicious networks off**, Wi-Fi power saving mode off if
  your firmware exposes it (Intelligent Wi-Fi hidden menu: tap
  *Intelligent Wi-Fi* version entry repeatedly)

### 4.3 Probe and DNS noise

```sh
settings put global captive_portal_mode 0     # stop periodic HTTP 204 probes
settings put global private_dns_mode off      # no DoT handshake in the path
```

Caveats: `captive_portal_mode 0` breaks hotel/café login-page detection
— set it back to 1 when you travel. `private_dns_mode off` trades DNS
privacy for removing TLS setup from lookups; if that bothers you, leave
it and eat the occasional first-lookup cost. Reverts:
`settings put global captive_portal_mode 1`,
`settings put global private_dns_mode opportunistic`.

### 4.4 The root line, and the router

TCP sysctls (`tcp_low_latency`, buffer sizes), the wlan driver module
params, and WMM tables are all root/kernel territory — no shell path.
The remaining wins are on the AP, configured from the tablet's browser:
5GHz-only SSID for the tablet, 80MHz width, WMM on, no "airtime
fairness"/"smart connect", and sit in the same room as the AP. A 5GHz
link at -50dBm beats every software tweak in this section combined.

---

## 5. Session preflight — the non-persistent block

Everything here resets on reboot. Run before a session (or automate via
Shizuku-on-boot + Tasker/MacroDroid; `rish` one-liner from Termux):

```sh
sh /sdcard/scewin-dump-latest/apply.sh            # debug.* props et al.
cmd wifi force-low-latency-mode enabled
cmd power set-fixed-performance-mode-enabled true  # if it won your A/B test
cmd game set --mode 2 com.supercell.brawlstars
```

One-time (persist across reboots): §2.1 GOS, §2.4, §2.5 (per game
update), §2.6, §3.1, §4.2, §4.3, and the settings/device_config half of
`apply.sh`.

---

## 6. Measure, don't vibe

Before/after every change — one variable at a time, like the README's
diff workflow:

```sh
# Frame timing while in a match (deltas between vsync columns = jitter):
dumpsys gfxinfo com.supercell.brawlstars framestats

# Wi-Fi latency: from Termux (plain, no rish needed), against your gateway:
ping -i 0.2 -c 100 192.168.1.1
# → compare min/avg/max/mdev with low-latency mode off vs on.
#   The improvement lives in max/mdev (the spikes), not avg.

# Wi-Fi state sanity:
dumpsys wifi | grep -iE 'latency|power save'
```

In-game ping in Brawl Stars measures the full path; the gateway ping
isolates *your* radio from the internet path so you know which half to
blame.

## 7. Revert map

| Change | Revert |
|---|---|
| generated `apply.sh` | generated `revert.sh` (1:1, your prior values) |
| GOS disabled | `pm enable com.samsung.android.game.gos` |
| game mode | `cmd game set --mode 1 com.supercell.brawlstars` |
| fixed perf mode | `cmd power set-fixed-performance-mode-enabled false` |
| `sem_enhanced_cpu_responsiveness` | `settings delete global sem_enhanced_cpu_responsiveness` |
| doze whitelist | `cmd deviceidle whitelist -com.supercell.brawlstars` |
| standby bucket | `am set-standby-bucket com.supercell.brawlstars rare` |
| RAM Plus | `settings put global ram_expand_size 4` + reboot (or Settings UI) |
| 120Hz pin | `settings put secure refresh_rate_mode 0`; `settings delete system peak_refresh_rate min_refresh_rate` (one key per call) |
| Wi-Fi low latency | `cmd wifi force-low-latency-mode disabled` |
| scan always | `cmd wifi set-scan-always-available enabled` |
| captive portal / private DNS | `settings put global captive_portal_mode 1` / `settings put global private_dns_mode opportunistic` |
| device_config freeze | `device_config set_sync_disabled_for_tests none` |

A plain `settings delete <ns> <key>` restores framework-default behavior
for any settings key here — that's always the safe exit.
