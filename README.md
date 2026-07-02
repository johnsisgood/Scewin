# Scewin — device-specific deep-knob tuning for your Tab S7

You wanted SCEWIN/IDA-style work, and you wanted it specific to your
tablet — not a generic Tab S7 profile. This kit is built around that.

## How "device-specific" actually works here

You can't write the right tuning script in advance — even two T870s on
different CSCs/firmware builds expose different knobs. Same way SCEWIN
profiles dumped from two boards of the same model aren't interchangeable.

So the loop is:

```
  [1] dump everything writable on YOUR tablet
        → produces a tarball of your actual settings/props/device_config/sysfs
  [2] catalog it
        → produces knobs.tsv: every writable key + your current value
  [3] generate tuning script FOR YOUR DEVICE
        → intersects a curated "known to affect latency" list
          with the keys that actually exist on your dump
        → emits apply.sh containing ONLY those, with your current
          values commented in for one-line revert
  [4] (optional) flip a UI toggle and re-dump → diff to discover
        keys the curated list doesn't know about
```

Your device's `apply.sh` will look different from anyone else's. That's
the point.

## What's in this repo

```
discover/
  dump-everything.sh        runs on the tablet — captures full knob surface
  catalog.sh                parses dump → per-device knobs.tsv inventory

analyze/
  known-impact-keys.tsv     curated list (key, category, source, target value)
                              sources: AOSP frameworks/native, Qualcomm vendor
                              HAL headers, Samsung One UI dumps
  generate-tuning.sh        intersects known-impact x your dump → apply.sh
                              + revert.sh, both specific to your device

diff/
  diff-state.sh             two dumps → exact list of keys a UI option flipped
                              this is how you find Samsung's undocumented knobs

reverse-engineering/
  targets.md                Tab S7 binaries worth pulling and decompiling
                              with concrete file paths, what to grep, what
                              kind of hidden setprop calls you're hunting

no-root/
  playbook.md               the full no-root deep-tuning guide: Shizuku/LADB
                              access, GOS neutering, game mode, fixed perf
                              mode, forced 120Hz, Wi-Fi low-latency mode —
                              the cmd/pm knobs apply.sh can't express
  maxout.sh                 one-shot max-aggression: re-applies apply.sh,
                              fixed perf mode, thermal override, bloat
                              freeze, kill-all — playbook §8
  restore.sh                undoes exactly what maxout.sh did

root-only/
  if-you-reroot.md          the order-of-magnitude wins that need root
                              (CPU/GPU freq pin, DDR pin, EAS off, touch IC)
```

## Quick start (no root, your stock T870/T875/T876)

```sh
# On the tablet, via Termux (or via `adb push` then `adb shell`):
sh discover/dump-everything.sh
sh discover/catalog.sh /sdcard/scewin-dump-latest
sh analyze/generate-tuning.sh /sdcard/scewin-dump-latest

# review the generated scripts — both are specific to YOUR device:
cat /sdcard/scewin-dump-latest/apply.sh
cat /sdcard/scewin-dump-latest/revert.sh

# apply when ready:
sh /sdcard/scewin-dump-latest/apply.sh
```

Then work through `no-root/playbook.md` — it covers the shell setup
(Shizuku/LADB, no PC needed) plus the `cmd`/`pm` knobs that can't be
expressed as settings lines: Samsung's GOS throttler, Android 13 game
mode, Wi-Fi low-latency mode, forced 120Hz, and what does/doesn't
survive a reboot.

## Finding knobs the curated list doesn't know about

```sh
sh discover/dump-everything.sh                  # snapshot A
# ... flip ONE thing in Game Booster, *#*#4636#*#*, dev opts, whatever
sh discover/dump-everything.sh                  # snapshot B
sh diff/diff-state.sh dump-A dump-B
# → exact list of keys that one toggle changed.
#   most are Samsung's, undocumented, and only knowable this way.
```

This is exactly the SCEWIN+IDA workflow — except instead of decompiling
SetupUtility to find suppressed setup items, you bisect them by
observing what flips.

## Honest scope

- I can't pre-bake the device-specific script from here. The toolchain
  produces it on your tablet against your firmware. That's the only way
  it's actually specific.
- The curated `known-impact-keys.tsv` is sourced from AOSP master,
  Qualcomm vendor HAL headers (`vendor.qti.hardware.perf`), and observed
  One UI 5/6 dumps on kona-platform Samsung devices. It's intentionally
  conservative — I'd rather miss a key than fabricate one. The diff
  workflow above is how you cover the gap.
- For deeper hidden knobs (the ones with no string keys, hardcoded into
  Samsung's vendor blobs), you genuinely do need to decompile.
  `reverse-engineering/targets.md` lists the binaries on your tablet to
  pull and what to grep them for in IDA/Ghidra.
