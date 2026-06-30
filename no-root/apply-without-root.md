# Using every setting you can WITHOUT root

Short version: you can apply a large, genuinely useful slice of this kit
with no root at all — but not from a normal app. The trick is **shell
UID** (uid 2000), which on a Tab S7 you can get **without root and
without a PC**.

## The one concept that matters: app UID vs shell UID

| | app UID (bare Termux) | shell UID (uid 2000) | root (uid 0) |
|---|---|---|---|
| `settings put global/system/secure` | ❌ blocked | ✅ | ✅ |
| `device_config put` | ❌ | ✅ | ✅ |
| `setprop debug.*` | ❌ | ✅ | ✅ |
| `setprop persist.* / vendor.* / dalvik.vm.*` | ❌ | ❌ | ✅ |
| `dumpsys`, `pm disable-user`, `cmd …` | ❌ | ✅ | ✅ |
| write `/sys/...` (CPU/GPU pin, touch 240Hz) | ❌ | ❌ | ✅ |
| WiFi power-save off (`iw` / `wl PM 0`) | ❌ | ❌ | ✅ |

So "no root" really means **"run as shell UID."** Bare Termux is app UID
and will throw `SecurityException` on almost everything here. You need one
of the three contexts below.

## First: put the kit where shell UID can read it

The shell user (uid 2000) **cannot read Termux's private home**
(`/data/data/com.termux`, mode 700). So the kit must live on `/sdcard`,
which both Termux and the rish/shell context can read. Get it there from a
normal Termux prompt (not rish):

```sh
# No token — download the branch ZIP from GitHub in your browser
# (repo → branch claude/... → Code → Download ZIP), then:
termux-setup-storage          # tap Allow
pkg install unzip
cd /sdcard
unzip ~/storage/downloads/scewin-*.zip
mv scewin-* Scewin            # extracted folder → /sdcard/Scewin

# OR with git + a Personal Access Token:
pkg install git
git clone -b <branch> https://<user>:<token>@github.com/<owner>/scewin.git /sdcard/Scewin
```

`/sdcard` is mounted noexec, so always invoke scripts with `sh script.sh`
(the kit already does this everywhere). Dumps land in `/sdcard/scewin-dump-*`
which shell UID can also write.

## How to get shell UID with NO root and NO PC

Your Tab S7 is on One UI 5/6 (Android 13/14), which has **Wireless
Debugging** — that's the key. It lets the device authorize ADB to itself.

### Option A — Shizuku (recommended)

1. Install **Shizuku** (Play Store).
2. Settings → Developer options → enable **Wireless debugging**.
3. In Shizuku, tap **"Start via Wireless debugging"** and follow the
   pairing prompt (it walks you through the pair-code step once).
4. Shizuku is now running as shell UID. `rish` is not a separate app — it
   is two files shipped inside the Shizuku APK (`rish` + `rish_shizuku.dex`)
   that you run from a terminal like Termux. Install it once:

   ```sh
   # In Termux, with Shizuku running. APKs are world-readable, so no root:
   cp "$(pm path moe.shizuku.privileged.api | sed 's/package://')" ~/shizuku.apk
   unzip -o ~/shizuku.apk 'assets/rish*' -d ~/
   mv ~/assets/rish ~/assets/rish_shizuku.dex ~/     # both must sit together
   chmod +x ~/rish
   # tell rish which app calls it (Termux = com.termux):
   echo 'export RISH_APPLICATION_ID=com.termux' >> ~/.bashrc
   export RISH_APPLICATION_ID=com.termux
   ~/rish
   id        # must print uid=2000(shell) — that's your no-root power level
   ```

   (Some Shizuku versions also expose a save/extract button under
   "Use Shizuku in terminal apps" — either way you need those two files.)

5. From the `~/rish` shell, run the kit:
   ```sh
   sh /sdcard/Scewin/discover/dump-everything.sh
   sh /sdcard/Scewin/discover/catalog.sh /sdcard/scewin-dump-latest
   sh /sdcard/Scewin/analyze/generate-tuning.sh /sdcard/scewin-dump-latest
   cat /sdcard/scewin-apply-latest.sh    # review (stable path, written by generate)
   sh  /sdcard/scewin-apply-latest.sh    # apply
   ```
   Note: `scewin-dump-latest` is a pointer FILE, not a dir — use the stable
   `scewin-apply-latest.sh` copy (or resolve it:
   `D=$(cat /sdcard/scewin-dump-latest.path); sh "$D/apply.sh"`).

Shizuku stops when the device reboots (no root to persist it). Re-tap
"Start via Wireless debugging" after each reboot, then `~/rish` works
again — takes 5 seconds.

### Option B — LADB (single self-contained app)

LADB bundles its own adb client and connects it to `127.0.0.1` over
Wireless Debugging. You get a shell-UID terminal with no companion app and
no PC. Same commands, just type them in LADB's terminal:
```sh
sh /sdcard/Scewin/analyze/generate-tuning.sh /sdcard/scewin-dump-latest
sh /sdcard/scewin-apply-latest.sh
```

### Option C — PC once over USB

```sh
adb push . /data/local/tmp/Scewin
adb shell sh /data/local/tmp/Scewin/discover/dump-everything.sh
adb shell sh /data/local/tmp/Scewin/discover/catalog.sh /sdcard/scewin-dump-latest
adb shell sh /data/local/tmp/Scewin/analyze/generate-tuning.sh /sdcard/scewin-dump-latest
adb shell sh /sdcard/scewin-apply-latest.sh
```
(You can switch to wireless with `adb tcpip 5555` and unplug.)

## What the generator does for you

`generate-tuning.sh` now splits `apply.sh` into two sections:

- **NO-ROOT** — every `settings` / `device_config` / `debug.*` knob. Runs
  as shell UID, no errors.
- **ROOT-ONLY** — vendor/persist/dalvik props and anything sysfs, wrapped
  in an `if [ "$(id -u)" = 0 ]` guard. Running as shell UID **skips these
  cleanly** and prints how many it skipped, instead of erroring out.

The run summary tells you the split, e.g.:
```
  apply WITHOUT root:  41   (settings, device_config, debug.* props)
  need root (guarded): 6    (vendor/persist/dalvik props, sysfs)
```

So you apply everything in your reach in one run, and you can see exactly
what you're leaving on the table by staying unrooted.

## Persistence without root

- `settings` and `device_config` values are stored in the settings DB —
  **they survive reboot.** Set once, done.
- `debug.*` props are **not** persisted — they reset on reboot. Re-run
  `apply.sh` after each reboot (one `rish -c "sh .../apply.sh"`), or
  trigger it from Tasker's Shizuku plugin on boot.
- This is the only no-root downside: the prop knobs need re-applying. The
  big-ticket persistent ones (settings/device_config) stick.

## Bonus no-root wins (shell UID, beyond the TSV)

These don't fit the key=value catalog but are real, reversible, and
no-root from a shell-UID context:

```sh
# Exempt Brawl Stars from Doze / standby so it never gets throttled idle:
cmd deviceidle whitelist +com.supercell.brawlstars
am set-standby-bucket com.supercell.brawlstars active
cmd appops set com.supercell.brawlstars RUN_ANY_IN_BACKGROUND allow

# Kill OEM background wakers that steal CPU (reverse with enable):
pm disable-user --user 0 com.samsung.android.bixby.agent
pm disable-user --user 0 com.samsung.android.app.spage      # Samsung Free feed
# list candidates first:  pm list packages | grep -iE 'bixby|spage|samsungapps'

# Stop the freezer/compaction from churning your game's pages:
settings put global cached_apps_freezer disabled
```

Revert anything: `pm enable <pkg>`, `am set-standby-bucket <pkg> 10`,
`cmd deviceidle whitelist -<pkg>`, or `sh revert.sh` for the generated set.

## The honest limit

Without root you are leaving the *biggest* wins on the table:
- WiFi power-save off (the #1 online-game knob) — needs root.
- CPU/GPU/DDR frequency pinning — needs root.
- 240 Hz touch sample rate (`sec_ts`) — needs root.

What you *do* get no-root: 120 Hz lock, animations off, freezer/standby/
doze defeated for the game, input-tracing/jank-monitor overhead off, and
the `debug.sf.*`/`debug.hwui.*` latency path. That's a real, measurable
chunk — just not the order-of-magnitude stuff in `root-only/`.
