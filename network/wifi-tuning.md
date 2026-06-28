# Network tuning — the actual high-impact stuff

## Use ethernet if you can

USB-C → Gigabit Ethernet adapter ($10–15) plugs into the Tab S7's USB-C
port. Tablet detects it automatically. This eliminates 100% of WiFi
jitter and is the single biggest latency win available. If you have a
desk setup, just do this and skip the rest of this file.

## WiFi, if you must

The Tab S7 has WiFi 6 (802.11ax). Most home routers are still WiFi 5.
That's fine for Brawl Stars — it needs about 200 kbps. Bandwidth is not
the issue; **jitter** is.

### Router-side (do these on your router, not the tablet)

1. **5 GHz only** for the tablet. Either:
   - Disable 2.4 GHz entirely, OR
   - Give 5 GHz a different SSID and connect the tablet only to that SSID.
   - Band steering ("smart connect") on consumer routers is unreliable
     and causes mid-game roams. Turn it off.

2. **Pick a clean channel manually**. Install "WiFi Analyzer" on the
   tablet (open source one by VREM Software). Look at 5 GHz. Pick the
   channel with the lowest signal from neighbors. Typically 36, 40, 44,
   48 (low band) or 149, 153, 157, 161 (high band). On most routers:
   Settings → Wireless → 5 GHz → Channel → set manually.

3. **80 MHz channel width**. 160 MHz sounds better but on a crowded band
   it causes more retries. 80 MHz is the sweet spot.

4. **Disable 802.11k/v/r** (fast roaming) if you only have one AP. These
   features can cause spurious reassociations on a single-AP network.

5. **QoS / traffic prioritization**: if your router supports it, give the
   Tab S7's MAC address highest priority. If it supports DSCP, mark UDP
   traffic to Supercell's ASN (AS200449) as EF (voice). Most consumer
   routers don't, that's fine.

6. **Disable IPv6 if it's flaky on your ISP**. Brawl Stars uses IPv4.
   Misconfigured IPv6 can add 100–500 ms DNS lookup delays as the OS
   races A/AAAA records. If unsure, leave it on; only disable as a test.

7. **MTU**: leave at default (1500). Lowering it is cargo-cult; for UDP
   game traffic it makes no difference and breaks other things.

### Tablet-side

Most "WiFi tweaks" you find online for Android are myths or
root-required:

- "Set WiFi sleep policy to never" — not a setting on Android 10+
  anyway, and the radio already stays on under load.
- "Use a static IP" — adds zero ms, and on DHCP networks causes conflicts
  when leases expire.
- "Disable WiFi power save with `iw`" — root only, and the Tab S7's
  modem already disables power save when the screen is on and an app
  has the WiFi lock (Brawl Stars holds one).

The one thing that does help on the tablet, included in `adb/optimize.sh`:

```
settings put global wifi_scan_throttle_enabled 0
```

This lets the WiFi stack do background scans when it detects a weak
signal, instead of waiting for the next throttle window. The result is
faster recovery from a flaky AP without a full reassociation drop.

## DNS

Set Private DNS on the tablet to `dns.cloudflare.com` (One UI:
Settings → Connections → More connection settings → Private DNS →
Private DNS provider hostname).

Why this matters for Brawl Stars even though it's a game:

- Brawl Stars re-resolves `game-server-*.brawlstars.com` on every cold
  start and on some reconnects. Slow DNS = slow connect.
- Many ISPs route DNS queries through a centralized resolver in a
  different city. Cloudflare DNS-over-TLS uses your nearest anycast POP.
- DNS-over-TLS is also encrypted; your ISP can't see or rate-limit it.

Cloudflare is typically the fastest in NA/EU. In Asia, `dns.google` is
often slightly faster — test both with `kdig` or the dnsperf benchmark.

## What does NOT work

- **Gaming VPNs (ExitLag, NoPing, WTFast, etc.)**: they add a hop. They
  can occasionally help if your ISP has bad peering to GCP — that's
  rare. On a typical residential connection in NA/EU, they make latency
  worse 80% of the time. The 20% they help, the help is 5–10 ms which
  is below the jitter floor anyway.
- **"Game accelerator" Android apps**: every single one is either a VPN
  in disguise (see above) or just sets the same animation scales
  `adb/optimize.sh` sets, then charges you for it.
- **Changing TCP buffer sizes via sysctl**: Brawl Stars uses UDP. TCP
  buffers are irrelevant. Also requires root.
- **Disabling SELinux / Knox**: zero impact on networking. Don't.
