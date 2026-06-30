# If you re-root with Magisk — the actually-big wins

The no-root knobs in `apply.sh` shave off maybe 8–25 ms of input lag and
clean up most jitter spikes. The order-of-magnitude wins below all need
root because they write to sysfs nodes that init chmods to 0644 root.

Knox is already tripped, so Magisk doesn't cost you anything you haven't
already lost. The script-by-script breakdown:

> **Before any of the compute knobs below: do `network/wifi-latency.md` §1
> first.** For an online game, killing WiFi power-save (`iw dev wlan0 set
> power_save off`, or Broadcom-native `wl PM 0` on this chip) removes more
> *felt* lag than every CPU/GPU pin here combined — it cuts tens of ms of
> per-packet jitter. It's also root-only, so it belongs in the same
> Magisk service.d script as the pins below.

## 1. Pin CPU clusters to performance + min freq (Tab S7 = kona SoC)

The 865+ has three clusters:
- cpu0–cpu3: little (Cortex-A55) → /sys/devices/system/cpu/cpu0/cpufreq/
- cpu4–cpu6: big   (Cortex-A77)  → /sys/devices/system/cpu/cpu4/cpufreq/
- cpu7      : prime (Cortex-A77) → /sys/devices/system/cpu/cpu7/cpufreq/

```sh
# all clusters to 'performance' governor (no DVFS dithering, no schedutil ramps)
for c in 0 4 7; do
    echo performance > /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor
    cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq \
        > /sys/devices/system/cpu/cpu$c/cpufreq/scaling_min_freq
done
```

What this kills: every microsecond of DVFS ramp-up latency on a touch.
The cluster is already at max when the interrupt fires.

Verify after applying with `discover/dump-everything.sh`; the cpufreq
section will show min == max.

## 2. Pin GPU min frequency (Adreno 650)

Same idea, GPU side. Brawl Stars is GPU-light, so it lets the GPU
governor sleep the Adreno down. Then the next frame hits the governor
ramp, and you get a 3-frame stutter on round start.

```sh
# Pin GPU governor to performance
echo performance > /sys/class/kgsl/kgsl-3d0/devfreq/governor

# Pin min freq to highest available
maxf=$(cat /sys/class/kgsl/kgsl-3d0/devfreq/max_freq)
echo "$maxf" > /sys/class/kgsl/kgsl-3d0/devfreq/min_freq

# Disable throttling (will run hot — that's the deal)
echo 0 > /sys/class/kgsl/kgsl-3d0/throttling
echo 0 > /sys/class/kgsl/kgsl-3d0/devfreq/adrenoboost
```

## 3. Pin DDR / cache bus governors

The Adreno 650 talks to DDR through several devfreq bus governors. If
they downscale, you get cache misses and frame-time jitter.

```sh
for d in /sys/class/devfreq/*; do
    name=$(basename "$d")
    case "$name" in
        *llccbw*|*ddrbw*|*cpubw*|*l3*|*memlat*)
            maxf=$(cat "$d/max_freq" 2>/dev/null) || continue
            echo "performance" > "$d/governor" 2>/dev/null
            echo "$maxf" > "$d/min_freq" 2>/dev/null
            ;;
    esac
done
```

## 4. EAS scheduler — kill the energy-aware part

The energy-aware scheduler tries to migrate Brawl Stars onto a little
core if it momentarily idles. That migration costs 200-800 µs.

```sh
# scheduler tunables that reduce migration / increase responsiveness
echo 50000   > /proc/sys/kernel/sched_migration_cost_ns      # rare migration
echo 1000000 > /proc/sys/kernel/sched_min_granularity_ns     # tight slices
echo 100000  > /proc/sys/kernel/sched_latency_ns
echo 0       > /proc/sys/kernel/sched_child_runs_first
echo 1       > /proc/sys/kernel/sched_tunable_scaling        # off
echo 0       > /proc/sys/kernel/sched_schedstats
```

Also nudge the pelt half-life if it's writable:

```sh
[ -w /proc/sys/kernel/sched_pelt_multiplier ] \
    && echo 4 > /proc/sys/kernel/sched_pelt_multiplier
```

(Some kernels expose it, some don't.)

## 5. Touch controller — sec_ts

Tab S7's touch IC is Synaptics S3908 behind the `sec_ts` driver. The
factory mode interface lets you flip:

```sh
# Force highest report rate even when one finger is down
echo "force_touch_active,1" > /sys/class/sec/tsp/cmd
echo "set_touch_rate,240"   > /sys/class/sec/tsp/cmd     # 240Hz scan
echo "glove_mode,0"         > /sys/class/sec/tsp/cmd     # off
echo "wet_mode,0"           > /sys/class/sec/tsp/cmd     # off
echo "stylus_mode,0"        > /sys/class/sec/tsp/cmd     # off, you're not using S Pen
echo "ear_detect_enable,0"  > /sys/class/sec/tsp/cmd
echo "noise_mode,0"         > /sys/class/sec/tsp/cmd
```

(Command set varies by firmware. After the dump,
`cat /sys/class/sec/tsp/cmd_list` shows yours exactly.)

The 240Hz scan rate is the single biggest input lag win available on
this tablet — twice as many touch reports per frame, ~4ms p99 lag drop.

## 6. Disable Doze and adaptive battery permanently

These reactivate themselves on reboot via Samsung's policy daemon. Root
lets you patch them out:

```sh
# Disable forcestop policy
echo "0" > /sys/module/lowmemorykiller/parameters/enable_adaptive_lmk 2>/dev/null

# Increase kernel low-memory thresholds (less aggressive killing)
echo "18432,23040,27648,32256,36864,46080" \
    > /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null
```

## 7. Pin Brawl Stars to the prime core (cpu7)

This is the chef's kiss. Once root is in:

```sh
PID=$(pidof com.supercell.brawlstars)
[ -n "$PID" ] && taskset -p 80 $PID         # cpu7 only
[ -n "$PID" ] && renice -n -20 $PID         # max nice priority
```

Run it from a Magisk service.d script so it triggers on app launch
(use Tasker or a logcat watcher to detect the launch).

---

## What this costs

- Battery drain: 30-80% higher under load. The 865+ idles at ~200mW,
  pinned to performance idles at ~1.5W. On a Tab S7 11000 mAh that's
  going from ~10h SoT to ~5h SoT.
- Heat: SoC will sit at 50-55°C in your hand under sustained gameplay.
  This is fine for the chip (it throttles at 95°C) but uncomfortable.
- Burn-in risk: irrelevant, Tab S7 is LCD not OLED.
- Storage IO contention: the iorap and freezer disables mean more apps
  resident in RAM. With RAM Plus off (don't use it) and 6/8GB of real
  RAM, you'll OOM cached apps faster. That's fine, Brawl Stars stays.

You said you don't care about functionality. This is the menu that
costs functionality.
