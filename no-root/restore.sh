#!/system/bin/sh
# no-root/restore.sh — undoes exactly what maxout.sh does, nothing more.
# (For the generated apply.sh knobs, use the generated revert.sh instead —
#  it restores YOUR device's recorded prior values 1:1.)

set -u
say() { echo "[restore] $*"; }
STATE=/sdcard/scewin-maxout-state

say "fixed performance mode OFF"
cmd power set-fixed-performance-mode-enabled false 2>/dev/null

say "thermal override reset"
cmd thermalservice reset >/dev/null 2>&1

say "wifi low-latency lock off (no-op if it was never accepted)"
cmd wifi force-low-latency-mode disabled >/dev/null 2>&1

say "bluetooth back on"
cmd bluetooth_manager enable >/dev/null 2>&1 || svc bluetooth enable >/dev/null 2>&1

say "resolution back to native"
wm size reset 2>/dev/null

say "display/input settings back to framework defaults"
settings put secure refresh_rate_mode 0
settings delete system peak_refresh_rate 2>/dev/null
settings delete system min_refresh_rate 2>/dev/null
settings delete global sem_enhanced_cpu_responsiveness 2>/dev/null

say "radios/probes back to defaults"
settings put secure location_mode 3
cmd wifi set-scan-always-available enabled >/dev/null 2>&1
settings put global captive_portal_mode 1
settings put global private_dns_mode opportunistic

say "device_config sync re-enabled"
device_config set_sync_disabled_for_tests none 2>/dev/null

say "game exemptions removed"
cmd deviceidle whitelist -com.supercell.brawlstars >/dev/null 2>&1
am set-standby-bucket com.supercell.brawlstars rare 2>/dev/null

say "RAM Plus back to default 4 (reboot to take effect)"
settings put global ram_expand_size 4 2>/dev/null

if [ -f "$STATE/frozen-packages.txt" ]; then
    while read -r p; do
        [ -n "$p" ] && pm enable "$p" >/dev/null 2>&1 && say "unfroze $p"
    done < "$STATE/frozen-packages.txt"
    rm -f "$STATE/frozen-packages.txt"
fi

say "done. GOS was disabled separately — 'pm enable com.samsung.android.game.gos' if you want it back."
