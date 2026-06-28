#!/system/bin/sh
# Capture the full knob surface of THIS specific tablet.
#
# Run on the tablet:
#   - via Termux: pkg install dash; sh dump-everything.sh
#   - via adb:   adb push dump-everything.sh /data/local/tmp/ &&
#                adb shell sh /data/local/tmp/dump-everything.sh
#
# No root required for the bulk of this. Some /sys reads will be denied
# without root; the script logs them and continues.
#
# Output:  /sdcard/scewin-dump-<timestamp>/   (also symlinked as -latest)
#   fingerprint.txt          model, build, fw, kernel, SoC, modem
#   settings.global.txt      every settings global key+value
#   settings.system.txt
#   settings.secure.txt
#   getprop.txt              every system property, sorted
#   device_config.txt        every Phenotype namespace (all key=value)
#   dumpsys/SurfaceFlinger.txt
#   dumpsys/input.txt
#   dumpsys/power.txt
#   dumpsys/activity-settings.txt
#   dumpsys/gfxinfo.txt      (com.supercell.brawlstars if installed)
#   dumpsys/thermalservice.txt
#   dumpsys/jobscheduler.txt
#   dumpsys/sensorservice.txt
#   dumpsys/audio.txt
#   dumpsys/window.txt
#   services.txt             every binder service registered
#   packages.txt             every installed package + enabled state
#   sysfs/                   readable nodes from /sys/class/{kgsl,thermal,...}
#   procfs/                  /proc/cpuinfo, meminfo, interrupts, sched_debug
#
# This is your "SCEWIN /o" — the FULL writable-and-readable state of
# your specific tablet's firmware.

set -u

TS=$(date +%Y%m%d-%H%M%S)
OUT=/sdcard/scewin-dump-$TS
mkdir -p "$OUT/dumpsys" "$OUT/sysfs" "$OUT/procfs"
LOG="$OUT/dump.log"

log() { echo "[dump] $*" | tee -a "$LOG"; }

# ---------- 1. fingerprint -------------------------------------------------
log "Capturing fingerprint..."
{
    echo "=== ro.product ==="
    getprop | grep -E '^\[ro\.(product|build|hardware|board|soc|vendor|system)\.'
    echo
    echo "=== One UI / Samsung ==="
    getprop | grep -E '^\[ro\.(samsung|csc|semc|knox)\.'
    echo
    echo "=== Kernel ==="
    uname -a
    cat /proc/version 2>/dev/null
    echo
    echo "=== Modem ==="
    getprop gsm.version.baseband
    getprop ril.product_code
    echo
    echo "=== Selinux ==="
    getenforce 2>/dev/null
} > "$OUT/fingerprint.txt"

# ---------- 2. settings DB -------------------------------------------------
log "Dumping settings DB (global/system/secure)..."
for ns in global system secure; do
    settings list "$ns" 2>/dev/null | sort > "$OUT/settings.$ns.txt"
    log "  $ns: $(wc -l < "$OUT/settings.$ns.txt") keys"
done

# ---------- 3. system properties -------------------------------------------
log "Dumping all system properties..."
getprop | sort > "$OUT/getprop.txt"
log "  getprop: $(wc -l < "$OUT/getprop.txt") properties"

# ---------- 4. device_config (Phenotype) -----------------------------------
log "Dumping device_config namespaces..."
{
    # List all namespaces, then dump each
    for ns in $(device_config list_namespaces 2>/dev/null); do
        echo "=== namespace: $ns ==="
        device_config list "$ns" 2>/dev/null
        echo
    done
} > "$OUT/device_config.txt"
log "  device_config: $(grep -c '^=== namespace' "$OUT/device_config.txt") namespaces"

# ---------- 5. dumpsys (the high-value targets) ----------------------------
log "Dumping high-value dumpsys outputs..."
DUMPSYS_TARGETS="SurfaceFlinger input power activity_service thermalservice
                 jobscheduler sensorservice audio window display
                 gfxinfo deviceidle alarm meminfo procstats"
for svc in $DUMPSYS_TARGETS; do
    fname=$(echo "$svc" | tr ' /' '__')
    dumpsys "$svc" > "$OUT/dumpsys/$fname.txt" 2>&1
done
# gfxinfo for brawl stars specifically (frame timing)
if pm list packages | grep -q '^package:com.supercell.brawlstars$'; then
    dumpsys gfxinfo com.supercell.brawlstars > "$OUT/dumpsys/gfxinfo_brawlstars.txt" 2>&1
    log "  Brawl Stars gfxinfo captured"
fi

# ---------- 6. binder services ---------------------------------------------
log "Listing binder services (the cmd interface surface)..."
service list > "$OUT/services.txt" 2>&1
log "  $(wc -l < "$OUT/services.txt") services"

# ---------- 7. packages ----------------------------------------------------
log "Listing packages (enabled state matters — disabled OEM bloat = wins)..."
{
    echo "=== enabled ==="
    pm list packages -e
    echo
    echo "=== disabled ==="
    pm list packages -d
    echo
    echo "=== system ==="
    pm list packages -s
} > "$OUT/packages.txt"

# ---------- 8. sysfs latency-relevant nodes --------------------------------
log "Reading sysfs latency knobs (some may be perm-denied without root)..."
for cls in kgsl thermal devfreq sec_ts power input; do
    if [ -d "/sys/class/$cls" ]; then
        ls -la "/sys/class/$cls/" > "$OUT/sysfs/class.$cls.list" 2>&1
    fi
done

# CPU freq surface
for cpu in 0 1 2 3 4 5 6 7; do
    base="/sys/devices/system/cpu/cpu$cpu/cpufreq"
    if [ -d "$base" ]; then
        {
            echo "cpu$cpu cur:    $(cat $base/scaling_cur_freq 2>/dev/null)"
            echo "cpu$cpu min:    $(cat $base/scaling_min_freq 2>/dev/null)"
            echo "cpu$cpu max:    $(cat $base/scaling_max_freq 2>/dev/null)"
            echo "cpu$cpu gov:    $(cat $base/scaling_governor 2>/dev/null)"
            echo "cpu$cpu avail:  $(cat $base/scaling_available_frequencies 2>/dev/null)"
            echo "cpu$cpu govs:   $(cat $base/scaling_available_governors 2>/dev/null)"
        } >> "$OUT/sysfs/cpufreq.txt"
    fi
done

# GPU (Adreno 650 on Tab S7 = kgsl-3d0)
for f in /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq \
         /sys/class/kgsl/kgsl-3d0/devfreq/min_freq \
         /sys/class/kgsl/kgsl-3d0/devfreq/max_freq \
         /sys/class/kgsl/kgsl-3d0/devfreq/governor \
         /sys/class/kgsl/kgsl-3d0/devfreq/available_governors \
         /sys/class/kgsl/kgsl-3d0/devfreq/available_frequencies \
         /sys/class/kgsl/kgsl-3d0/gpubusy \
         /sys/class/kgsl/kgsl-3d0/throttling \
         /sys/class/kgsl/kgsl-3d0/temp; do
    if [ -r "$f" ]; then
        echo "$f = $(cat $f 2>/dev/null)" >> "$OUT/sysfs/kgsl.txt"
    fi
done

# DDR / cache buses (devfreq)
if [ -d /sys/class/devfreq ]; then
    for d in /sys/class/devfreq/*; do
        name=$(basename "$d")
        for k in cur_freq min_freq max_freq governor available_frequencies; do
            if [ -r "$d/$k" ]; then
                echo "$name.$k = $(cat $d/$k 2>/dev/null)" >> "$OUT/sysfs/devfreq.txt"
            fi
        done
    done
fi

# Thermal zones (Tab S7 has ~50 zones — knowing which one trips matters)
if [ -d /sys/class/thermal ]; then
    for tz in /sys/class/thermal/thermal_zone*; do
        type=$(cat $tz/type 2>/dev/null)
        temp=$(cat $tz/temp 2>/dev/null)
        trip=$(cat $tz/trip_point_0_temp 2>/dev/null)
        echo "$tz: type=$type temp=$temp trip0=$trip" >> "$OUT/sysfs/thermal.txt"
    done
fi

# Touch controller (sec_ts on Tab S7 — Synaptics)
if [ -d /sys/class/sec/tsp ]; then
    ls /sys/class/sec/tsp > "$OUT/sysfs/sec_ts.list" 2>&1
fi

# ---------- 9. procfs ------------------------------------------------------
log "Capturing procfs..."
cp /proc/cpuinfo "$OUT/procfs/cpuinfo" 2>/dev/null
cp /proc/meminfo "$OUT/procfs/meminfo" 2>/dev/null
cp /proc/interrupts "$OUT/procfs/interrupts" 2>/dev/null
cat /proc/sys/kernel/sched_latency_ns          > "$OUT/procfs/sched_latency_ns" 2>/dev/null
cat /proc/sys/kernel/sched_min_granularity_ns  > "$OUT/procfs/sched_min_gran"   2>/dev/null
cat /proc/sys/kernel/sched_migration_cost_ns   > "$OUT/procfs/sched_mig_cost"   2>/dev/null

# ---------- 10. link as -latest --------------------------------------------
rm -f /sdcard/scewin-dump-latest
ln -s "$OUT" /sdcard/scewin-dump-latest 2>/dev/null || \
    cp -r "$OUT" /sdcard/scewin-dump-latest

log "Done. Dump at: $OUT"
log "Symlink: /sdcard/scewin-dump-latest"
log ""
log "Next: sh discover/catalog.sh $OUT"
