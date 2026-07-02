#!/system/bin/sh
# no-root/maxout.sh — everything at once, maximum aggression, no root.
#
# Run from a SHELL-UID shell (Shizuku `rish` or LADB), not plain Termux:
#     rish
#     sh no-root/maxout.sh
#
# Optional flags (env vars):
#     MAXOUT_FREEZE=1   freeze background bloat packages (biggest jitter win here)
#     MAXOUT_RES=1      drop render resolution to 1920x1200 for GPU headroom
#     MAXOUT_BT=1       turn Bluetooth off for the session
#     e.g.:  MAXOUT_FREEZE=1 MAXOUT_BT=1 sh no-root/maxout.sh
#
# Everything is reversible:  sh no-root/restore.sh
# Costs: battery, background app freshness, captive-portal detection,
# DNS privacy, find-your-tablet conveniences. You said you don't care.

set -u
say() { echo "[maxout] $*"; }

STATE=/sdcard/scewin-maxout-state
mkdir -p "$STATE" 2>/dev/null

# ---- 0. re-apply the generated per-device knobs --------------------------
# The debug.* props (SF backpressure, phase offsets — the render-latency
# meat) DIE ON EVERY REBOOT. If you rebooted since last apply, you lost
# them without noticing. This re-applies unconditionally.
LATEST=/sdcard/scewin-dump-latest
[ -f /sdcard/scewin-dump-latest.path ] && LATEST=$(cat /sdcard/scewin-dump-latest.path)
if [ -f "$LATEST/apply.sh" ]; then
    say "re-applying $LATEST/apply.sh (props reset on every boot)"
    sh "$LATEST/apply.sh" >/dev/null 2>&1
else
    say "WARNING: no generated apply.sh — run the discover/analyze toolchain first."
    say "         You are missing the whole debug.sf.* render-latency block."
fi

# ---- 1. session block (non-persistent, rerun before every session) ------
say "fixed performance mode ON (playbook 2.3 — pins sustained clocks, no DVFS dither)"
cmd power set-fixed-performance-mode-enabled true 2>/dev/null \
    || say "  -> not supported on this build (cmd power for verb list)"

say "framework thermal status override -> NONE (stops thermal 120->60Hz drops)"
cmd thermalservice override-status 0 >/dev/null 2>&1 \
    || say "  -> not permitted on this build"
# Note: vendor thermal-engine still protects the silicon; this only mutes
# the framework signal that downgrades refresh rate / brightness.

say "killing all cached background processes"
am kill-all >/dev/null 2>&1

if cmd wifi force-low-latency-mode enabled >/dev/null 2>&1; then
    say "wifi low-latency lock ON"
else
    say "wifi low-latency blocked by firmware (known on One UI — playbook 4.1)"
fi

if [ "${MAXOUT_BT:-0}" = "1" ]; then
    cmd bluetooth_manager disable >/dev/null 2>&1 || svc bluetooth disable >/dev/null 2>&1
    say "bluetooth OFF for this session"
fi

if [ "${MAXOUT_RES:-0}" = "1" ]; then
    wm size 1920x1200 && say "render resolution -> 1920x1200 (wm size reset to undo)"
fi

# ---- 2. persistent block (idempotent, survives reboot) ------------------
say "pinning 120Hz + One UI input boost"
settings put secure refresh_rate_mode 2
settings put system peak_refresh_rate 120.0
settings put system min_refresh_rate 120.0
settings put global sem_enhanced_cpu_responsiveness 1

say "silencing radios/probes: location, scan-always, captive portal, private DNS"
settings put secure location_mode 0
cmd wifi set-scan-always-available disabled >/dev/null 2>&1
settings put global captive_portal_mode 0
settings put global private_dns_mode off

say "freezing device_config against Google flag resync"
device_config set_sync_disabled_for_tests persistent 2>/dev/null

say "game exemptions (doze whitelist, active bucket)"
cmd deviceidle whitelist +com.supercell.brawlstars >/dev/null 2>&1
am set-standby-bucket com.supercell.brawlstars active 2>/dev/null

say "RAM Plus -> 0 (takes effect after a reboot; some CSCs floor at 2)"
settings put global ram_expand_size 0 2>/dev/null

# ---- 3. optional: freeze the background bloat ----------------------------
# These wake periodically (sync, telemetry, ML profiling) and each wake is
# a scheduler theft + potential frame hitch. All reversible via restore.sh,
# which reads the list recorded below.
if [ "${MAXOUT_FREEZE:-0}" = "1" ]; then
    : > "$STATE/frozen-packages.txt"
    for p in \
        com.samsung.android.bixby.agent \
        com.samsung.android.bixby.wakeup \
        com.samsung.android.bixbyvision.framework \
        com.samsung.android.app.spage \
        com.samsung.android.rubin.app \
        com.samsung.android.mdx \
        com.microsoft.skydrive \
        com.facebook.services \
        com.facebook.system \
        com.facebook.appmanager \
        com.samsung.android.voc \
        com.sec.android.diagmonagent \
        com.samsung.android.app.omcagent \
        com.samsung.android.smartswitchassistant \
        com.samsung.android.game.gamehome \
    ; do
        if pm list packages --user 0 -e 2>/dev/null | grep -qxF "package:$p"; then
            if pm disable-user --user 0 "$p" >/dev/null 2>&1; then
                echo "$p" >> "$STATE/frozen-packages.txt"
                say "froze $p"
            fi
        fi
    done
    say "frozen list saved to $STATE/frozen-packages.txt"
fi

say "done. force-stop Brawl Stars and relaunch. undo everything: sh no-root/restore.sh"
