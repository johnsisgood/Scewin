# Network latency — the part that actually decides Brawl Stars

Read this first, because it's the honest framing the rest of the kit
doesn't give you:

**Brawl Stars latency is ~90% network, ~10% on-device.** Every knob in
`apply.sh` and `root-only/` attacks the on-device 10% (touch → render →
display). Real, worth doing, but it's milliseconds. The thing you *feel*
as "lag" — the dash that fires late, the shot that whiffs — is round-trip
time to Supercell's game server. No setting on this tablet can go below
that floor. What this file does is remove the latency this tablet *adds*
on top of the floor.

There is exactly one on-device network knob that's worth more than all
the on-device render knobs combined, and almost nobody applies it:

---

## 1. WiFi power-save — the single biggest win, and it's hidden

When WiFi power-save is on (it is, by default, always), the station tells
the access point "I'm going to sleep" and the AP **buffers your downlink
packets** until the next DTIM beacon. Beacon interval is typically 100 ms;
DTIM period 1–3. So inbound game packets can sit in the AP's buffer for
**tens to low-hundreds of ms** before the radio wakes to collect them.

For a turn-based app you never notice. For Brawl Stars it's the difference
between "this tablet feels laggy" and "this tablet feels wired."

### Tab S7 specifics

The T870/T875 uses a **Broadcom BCM4375** combo chip behind the `dhd`
(Dongle Host Driver). That gives you two ways to kill power-save, both
**root-only** (the radio's PM state isn't a userspace setting):

```sh
# A) Standard nl80211 path — works if `iw` is present (Termux: pkg install iw)
iw dev wlan0 set power_save off
iw dev wlan0 get power_save        # confirm: "Power save: off"

# B) Broadcom-native path — the dhd driver's own PM control.
#    PM 0 = off, 1 = max power-save, 2 = fast power-save.
#    The `wl` utility may already be at /vendor/bin/wl or /system/bin/wl;
#    if not, push the matching wl binary for your kernel.
wl PM 0
wl PM                              # confirm: prints 0
```

`wl PM 0` is the literal "the specifics nobody posts" knob you asked for —
it's the exact command Broadcom's own engineers use, it's not in any
Settings menu, and it's specific to this chip family. It does not survive
reboot or a WiFi off/on toggle, so run it from a Magisk `service.d` script
or re-run it when you sit down to play.

Cost: ~150–400 mW extra while the screen is on and WiFi is associated.
On an 11000 mAh tablet that's noise compared to the GPU.

---

## 2. No-root WiFi knobs (these flow through generate-tuning.sh)

These are real AOSP `Settings.Global` keys. They only land in your
`apply.sh` if they exist on your firmware — the generator skips anything
not present, so nothing here is fabricated. They're already added to
`analyze/known-impact-keys.tsv`:

| key | value | why |
|---|---|---|
| `wifi_scan_throttle_enabled` | 0 | faster recovery if the link dips |
| `wifi_scan_always_enabled` | 0 | stop always-on scans stealing airtime from your link |
| `wifi_watchdog_poor_network_test_enabled` | 0 | kill the periodic active probe that contends mid-game |
| `network_recommendations_enabled` | 0 | stop the network scorer's background scanning |
| `wifi_non_persistent_mac_randomization_enabled` | 0 | avoid per-assoc MAC randomization reassoc delay |

The scan ones matter more than they look: a background WiFi scan makes the
radio leave your channel to probe others, which **drops every in-flight
game packet for the scan window** — a classic random ~1–2 s micro-freeze.

Also, in WiFi settings for your home SSID specifically:

- **MAC address type → "Phone MAC" (device MAC)**, not randomized. A fresh
  random MAC forces a full re-DHCP/re-auth on every reconnect.
- **Metered → "Not metered"** so Android stops throttling background sync
  in a way that bursts and competes with your game traffic.
- **"Auto-reconnect" on**, **"Adaptive Wi-Fi"/"Switch to mobile data" off**
  — band/network switching mid-match is a 1–3 s stall.

Optional, security-relevant so it's *not* auto-applied — Private DNS adds a
TLS handshake on new connections:

```sh
settings put global private_dns_mode off    # marginal; revert: 'opportunistic'
```

---

## 3. Router side (off-device, but it's half the on-device-network battle)

You can't set these from the tablet, but they pair with #1:

- **DTIM = 1** on the AP. Even with station power-save off, a high DTIM
  hurts any device that *does* sleep and inflates broadcast latency.
- **Beacon interval 100 ms** (default; don't raise it).
- **5 GHz, fixed 80 MHz channel, fixed channel number.** Auto channel
  selection re-scans and can move you mid-game. Pick a clear channel
  (36/40/44/48 are usually clean) and pin it.
- **WMM / QoS on.** Game traffic is latency-class; WMM is what lets it
  jump the queue ahead of someone streaming on the same AP.
- **Band steering off** for the gaming device, or give 5 GHz its own SSID
  and connect only to that. Steering = forced roam = stall.
- **Airtime fairness:** on a clean network, leave default. On a congested
  one it actually helps your latency by stopping a slow device from hogging
  airtime.

If you can run **Ethernet via a USB-C dock** to the Tab S7, do that — it
removes the entire WiFi variable. Android supports USB Ethernet with no
root; it just works once plugged in.

---

## 4. Measure it — don't guess

Latency tuning you can't measure is cargo-culting. The floor is server
RTT; everything above is what you're removing.

```sh
# 1. find the game server's host while a match is live:
#    (Brawl Stars is UDP; you can't ping its port, but you can ping the host)
adb shell 'cat /proc/net/udp'        # note remote addrs while in a match
# or, simpler, watch active connections:
adb shell ss -u -n | grep -v 127.0.0.1

# 2. ping that host repeatedly and watch jitter (mdev), not just avg:
ping -i 0.2 -c 100 <server-ip>
#    avg = your floor; mdev/max-min = the jitter this kit kills.

# 3. before/after WiFi power-save off:
#    expect avg roughly unchanged, but mdev and max to drop hard.
```

`mdev` (mean deviation) is the number to watch. A clean wired-feeling link
has single-digit-ms mdev; power-save on, you'll often see 30–80 ms mdev
with periodic spikes. That spread is the lag you actually feel, and #1 is
what removes it.

---

## Honest ceiling

- Server RTT is physics + Supercell's datacenter placement. If your
  nearest server is 70 ms away, 70 ms is the floor. None of this beats it.
- These knobs take you *to* the floor instead of floor + WiFi jitter.
- The biggest single lever in this whole repo, for an online game, is
  `wl PM 0` / `iw ... power_save off` in section 1. If you only do one
  network thing, do that.
