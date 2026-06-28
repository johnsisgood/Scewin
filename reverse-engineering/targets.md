# Tab S7 — binaries worth pulling and decompiling

When the dump+diff workflow doesn't surface a knob, the knob has no
string key. It's hardcoded as a constant inside a vendor blob, set via
a private binder call or a sysfs node whose name isn't a property. To
find those, you decompile — same as IDA on `SetupUtility.efi`.

Below are the specific binaries on a Tab S7 (kona platform, One UI
5/6) that have produced findings in field. Pull, decompile, grep for
the listed needles.

## Pulling binaries off your tablet

```sh
# from a PC over ADB:
adb pull /system_ext/priv-app/SemGameTools/SemGameTools.apk
adb pull /system_ext/priv-app/SemPerfManager/SemPerfManager.apk
adb pull /vendor/lib64/libqti-perfd-client.so
adb pull /vendor/lib64/libqti-perfd.so
adb pull /vendor/lib64/vendor.qti.hardware.perf@2.2.so
adb pull /vendor/lib64/libqdMetaData.so
adb pull /vendor/lib64/hw/vendor.qti.hardware.display.composer@3.0-impl.so
adb pull /vendor/lib64/hw/gralloc.kona.so
adb pull /vendor/etc/perf/                       # full perf config dir
adb pull /vendor/etc/thermal-engine.conf
adb pull /vendor/etc/thermal-engine-kona.conf
adb pull /vendor/etc/init/hw/init.kona.rc
adb pull /system/etc/init/                       # for samsung init scripts

# game-mode policy lives in:
adb pull /system_ext/etc/permissions/sysconfig_for_GED.xml
adb pull /system_ext/etc/sysconfig/

# touch controller config:
adb pull /vendor/firmware/tsp_synaptics/
```

## Target 1 — `SemGameTools.apk` (Samsung's Game Booster Plus)

```sh
jadx-gui SemGameTools.apk
```

Grep targets in the decompiled source:

```
SystemProperties.set\(                  ← every prop the app writes
Settings\.(System|Global|Secure)\.put   ← every settings key it flips
DeviceConfig\.set                       ← every device_config key
service.call("                          ← raw binder transactions
sec_ts                                  ← touch IC tuning calls
DvfsHelper|SemDvfsManager               ← Samsung's hidden DVFS API
SemGameManager.set                      ← Samsung-only game mode API
```

What you find: the explicit list of "performance mode" knobs Samsung
flips that are NOT exposed in Settings. Some examples seen in past
versions (verify yours via decompile, names change between One UI
revisions):

- `SemDvfsManager` calls with type `TYPE_CPU_MIN_FREQ`, `TYPE_GPU_MIN_FREQ`
- `SemPerfManager.requestPerformanceLock(scenario, timeout)` with
  scenario IDs ≥ 0x1000 for game-mode locks
- Raw `service call SurfaceFlinger` transactions toggling smooth motion

These ARE the SCEWIN-hidden tokens — public API but never invoked
outside the privileged game launcher.

## Target 2 — `libqti-perfd-client.so` (Qualcomm perf HAL)

```sh
ghidra-headless libqti-perfd-client.so
# or
ida64 libqti-perfd-client.so
```

Grep targets:

```
perf_hint_acq_rel                       ← hint codes
PERF_HINT_DISP_FREQ_VOTE_MIN_LITTLE     ← named hint constants
VENDOR_HINT_FIRST_LAUNCH_BOOST          ← undocumented hint codes
prop_                                    ← properties read at init
SetParameter / GetParameter             ← runtime tunables
```

These hint codes are passed to the perf HAL via a binder call. The
hint codes are what Samsung's game-mode actually invokes. Many are
NOT documented anywhere public; their numeric value is enough to call
them from a privileged script.

Example calls you'll be able to construct:

```
service call vendor.perfservice 4 i32 <hint_id> i32 <duration_ms>
```

The hint_id comes from the decompile. Boost durations of -1 mean
"until released".

## Target 3 — `/vendor/etc/perf/` config

This isn't a binary — it's a set of XML configs read by the perf HAL.
These are pure data. Knobs include:

- `perfboostsconfig.xml`: lists every named scenario → hint sequence
- `perfconfigstore.xml`: feature gates per build variant
- `targetconfig.xml`: per-SoC frequency tables
- `commonresourceconfigs.xml`: cross-cutting CPU/GPU policy

You can read these directly (no IDA needed). Search for scenarios
named `LAUNCH`, `GAME`, `INTERACTION`, `DRAG`. The hint sequences they
trigger are the actual contents of what "Performance mode" does.

## Target 4 — `/vendor/etc/thermal-engine-kona.conf`

The thermal trip points and throttling actions. Reading this tells you
which sensor will trigger your throttle and at what temperature. You
can then watch that specific zone (`/sys/class/thermal/thermal_zone*`)
and know when you're about to throttle.

Example pattern:

```
[VIRTUAL-CPU-SS]
algo_type        ss
sampling         65
sensor           cpuss-2
device           cpu4
set_point        85000
set_point_clr    75000
```

Means: when virtual sensor `cpuss-2` reads 85°C, throttle `cpu4`
(prime core). Clear at 75°C. This is the actual cause of the mid-game
FPS dip you feel.

## Target 5 — `init.kona.rc` and Samsung init scripts

These run as `init` and can `write` to sysfs nodes that are
permission-denied later to userspace. Grep for:

```
write /sys/                              ← every sysfs write at boot
on property:                              ← property triggers
chmod 0220 /sys/                          ← nodes locked after boot
```

What you'll find: there are sysfs nodes (touch IC sample rate, GPU min
freq, DDR floor) that init writes once at boot, then chmods to root-
only. With root you can rewrite them. Without root you'd need to find
a property that triggers `init` to do it — sometimes one exists.

## Workflow recap

```
  decompile target
    → find SystemProperties / Settings / service-call writes
    → cross-reference with discover/dump-everything.sh output
       (does the key exist on YOUR build?)
    → add to apply.sh manually, or extend
       analyze/known-impact-keys.tsv
    → use diff/diff-state.sh to confirm the knob actually flipped
```

That's the loop. It's tedious. It's also the only way to get past the
generic "Tab S7 tweaks" lists.
