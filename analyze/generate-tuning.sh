#!/system/bin/sh
# Generate apply.sh + revert.sh that are SPECIFIC to your tablet.
#
# Mechanism: intersect analyze/known-impact-keys.tsv against
# discover/.../knobs.tsv. Only keys actually present (or always-present
# AOSP keys) make it into your apply.sh. Each comes with your current
# value commented in, so revert.sh is a 1:1 restore.
#
# The generated apply.sh is split into two sections:
#   - NO-ROOT  : settings / device_config / debug.* props. These apply
#                from any shell-UID context (Shizuku rish, LADB, adb) with
#                NO root. See no-root/apply-without-root.md.
#   - ROOT-ONLY: vendor/persist/dalvik props + sysfs. Wrapped in an
#                `id -u` guard so a non-root run skips them cleanly instead
#                of erroring. See root-only/if-you-reroot.md.
#
# Usage:  sh analyze/generate-tuning.sh /sdcard/scewin-dump-<timestamp>

set -u
DUMP="${1:-/sdcard/scewin-dump-latest}"
if [ "$DUMP" = "/sdcard/scewin-dump-latest" ] && [ -f /sdcard/scewin-dump-latest.path ]; then
    DUMP=$(cat /sdcard/scewin-dump-latest.path)
fi
KNOWN="$(dirname $0)/known-impact-keys.tsv"

if [ ! -f "$DUMP/knobs.tsv" ]; then
    echo "no knobs.tsv in $DUMP — run discover/catalog.sh first" >&2
    exit 1
fi
echo "[generate] using dump: $DUMP"
if [ ! -f "$KNOWN" ]; then
    echo "missing $KNOWN" >&2; exit 1
fi

APPLY="$DUMP/apply.sh"
REVERT="$DUMP/revert.sh"
SKIPPED="$DUMP/apply-skipped.tsv"

# Section buffers (assembled into APPLY/REVERT after the loop).
APPLY_NR="$DUMP/.apply-noroot.$$"; APPLY_R="$DUMP/.apply-root.$$"
REVERT_NR="$DUMP/.revert-noroot.$$"; REVERT_R="$DUMP/.revert-root.$$"
: > "$APPLY_NR"; : > "$APPLY_R"; : > "$REVERT_NR"; : > "$REVERT_R"

cat > "$APPLY" <<EOF
#!/system/bin/sh
# Auto-generated for THIS tablet.
# Source dump: $DUMP
# Generated:   $(date)
#
# Run as shell UID (no root needed for the NO-ROOT section):
#   Shizuku:  rish -c "sh $APPLY"
#   LADB:     sh $APPLY
#   PC:       adb shell sh ${APPLY##*/}   (after adb push)
#
# Each line is ONE knob. If something breaks, comment that one line and
# re-run to bisect. The ROOT-ONLY section auto-skips unless you're root.

set -u
EOF

cat > "$REVERT" <<EOF
#!/system/bin/sh
# Auto-generated revert — restores the exact prior values from your dump.
set -u
EOF

: > "$SKIPPED"

# "always-present" set: AOSP base properties + settings + device_config
# keys that exist on every modern Android. We emit these even if not in
# the dump (they're recognized at default by the framework).
is_always_present() {
    case "$1" in
        debug.sf.*|debug.hwui.*|debug.choreographer.*|debug.egl.*) return 0 ;;
        debug.atrace.*|debug.power.*)                              return 0 ;;
        dalvik.vm.*)                                                return 0 ;;
        window_animation_scale|transition_animation_scale|animator_duration_scale) return 0 ;;
        haptic_feedback_enabled|sound_effects_enabled|show_touches) return 0 ;;
        peak_refresh_rate|min_refresh_rate)                        return 0 ;;
        wifi_scan_throttle_enabled|low_power|low_power_sticky)     return 0 ;;
        app_standby_enabled|adaptive_battery_management_enabled)   return 0 ;;
        ble_scan_always_enabled|device_idle_constants)             return 0 ;;
        immersive_mode_confirmations|pointer_speed)                return 0 ;;
        activity_manager/*|activity_manager_native_boot/*)          return 0 ;;
        runtime_native_boot/*|input/*|latency_tracker/*)            return 0 ;;
        interaction_jank_monitor/*|jobscheduler/*|media_native/*)   return 0 ;;
    esac
    return 1
}

# Does this knob need root? return 0 = needs root, 1 = no-root (shell uid).
#   - settings/device_config: shell uid holds WRITE_SECURE_SETTINGS /
#     WRITE_DEVICE_CONFIG → no root.
#   - debug.* props: live in debug_prop, settable by the shell SELinux
#     domain → no root. (Take effect on reboot for SurfaceFlinger/hwui.)
#   - everything else (persist.*/vendor.*/dalvik.vm.*, sysfs): root.
needs_root() {
    case "$1" in
        prop)
            case "$2" in
                debug.*) return 1 ;;
                *)       return 0 ;;
            esac ;;
        setting_global|setting_system|setting_secure|device_config) return 1 ;;
        *) return 0 ;;
    esac
}

# POSIX-safe tab. $'\t' is a bash-ism; Termux's sh evaluates it literally.
TAB=$(printf '\t')

# Look up current value of a key in this device's dump.
current_value() {
    awk -F"$TAB" -v k="$1" -v n="$2" '$1==k && $2==n {print $3; exit}' "$DUMP/knobs.tsv"
}

# Live fallback for getprop: in case the prop wasn't captured into
# knobs.tsv but is actually set on the device right now.
live_prop_value() {
    getprop "$1" 2>/dev/null
}

# Avoid pipe-to-while subshells — counters were getting lost AND
# function inheritance is flaky across pipes in posix sh-mode bash.
TMP="$DUMP/.gen-known.$$"
tail -n +2 "$KNOWN" > "$TMP"

apply_count=0
skip_count=0
noroot_count=0
root_count=0

while IFS="$TAB" read -r kind key target source notes; do
    [ -z "$kind" ] && continue

    case "$kind" in
        prop)            cur=$(live_prop_value "$key") ;;
        *)               cur=$(current_value "$kind" "$key") ;;
    esac

    # Decision: emit if currently present OR always-present
    if [ -z "$cur" ] && ! is_always_present "$key"; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$key" "$target" "not-present-on-device" "$source" >> "$SKIPPED"
        skip_count=$((skip_count+1))
        continue
    fi
    # Distinguish "was unset" from a real prior value. The revert for a
    # previously-unset key is a delete/clear, NOT a put of a literal — the
    # old code emitted `settings put <key> <unset...>`, whose unquoted `<`
    # is a shell redirect (syntax error) and otherwise writes garbage.
    if [ -z "$cur" ]; then was_unset=1; cur_disp='<unset, framework default>'
    else                   was_unset=0; cur_disp="$cur"; fi

    # Route to the no-root or root-only section buffer.
    if needs_root "$kind" "$key"; then
        af="$APPLY_R"; rf="$REVERT_R"; root_count=$((root_count+1))
    else
        af="$APPLY_NR"; rf="$REVERT_NR"; noroot_count=$((noroot_count+1))
    fi

    # Emit the apply command, with the source noted inline.
    # Target values in known-impact-keys.tsv are simple tokens (no spaces);
    # revert values come from the device, so they're quoted to be safe.
    case "$kind" in
        prop)
            printf '\n# %s    (was: %s)    [%s]\nsetprop "%s" "%s"\n' \
                "$notes" "$cur_disp" "$source" "$key" "$target" >> "$af"
            if [ "$was_unset" = 1 ]; then
                printf '\nsetprop "%s" ""\n' "$key" >> "$rf"   # was unset; full reset on reboot
            else
                printf '\nsetprop "%s" "%s"\n' "$key" "$cur" >> "$rf"
            fi
            ;;
        setting_global|setting_system|setting_secure)
            ns=${kind#setting_}
            printf '\n# %s    (was: %s)\nsettings put %s %s %s\n' \
                "$notes" "$cur_disp" "$ns" "$key" "$target" >> "$af"
            if [ "$was_unset" = 1 ]; then
                printf 'settings delete %s %s\n' "$ns" "$key" >> "$rf"
            else
                printf 'settings put %s %s "%s"\n' "$ns" "$key" "$cur" >> "$rf"
            fi
            ;;
        device_config)
            ns="${key%%/*}"; name="${key#*/}"
            printf '\n# %s    (was: %s)\ndevice_config put %s %s %s\n' \
                "$notes" "$cur_disp" "$ns" "$name" "$target" >> "$af"
            if [ "$was_unset" = 1 ]; then
                printf 'device_config delete %s %s\n' "$ns" "$name" >> "$rf"
            else
                printf 'device_config put %s %s "%s"\n' "$ns" "$name" "$cur" >> "$rf"
            fi
            ;;
    esac
    apply_count=$((apply_count+1))
done < "$TMP"
rm -f "$TMP"

# ---- assemble apply.sh: no-root section, then guarded root-only section ----
{
    echo ''
    echo "# ========================= NO-ROOT =========================="
    echo "# Applies from any shell-UID context (Shizuku/LADB/adb). No root."
} >> "$APPLY"
cat "$APPLY_NR" >> "$APPLY"

{
    echo ''
    echo "# ======================== ROOT-ONLY ========================="
    echo '# Auto-skipped unless you are root. See root-only/if-you-reroot.md.'
    echo 'if [ "$(id -u)" = 0 ]; then'
    echo '    :'   # no-op keeps the block valid even if it is empty
} >> "$APPLY"
cat "$APPLY_R" >> "$APPLY"
{
    echo 'else'
    printf '    echo "skipped %s root-only knob(s) — not root. See root-only/."\n' "$root_count"
    echo 'fi'
} >> "$APPLY"

cat >> "$APPLY" <<'EOF'

# --- post-apply notes -------------------------------------------------------
service call SurfaceFlinger 1008 i32 1 >/dev/null 2>&1   # force a repaint
echo "applied (no-root section)."
echo "  settings + device_config : persist across reboot — done."
echo "  debug.hwui/choreographer/egl : per-app. Force-stop and REOPEN Brawl"
echo "      Stars to apply them. (Cleared on reboot — re-run, then reopen.)"
echo "  debug.sf.* : read only when SurfaceFlinger restarts, which needs"
echo "      root. Without root setprop succeeds but they stay INERT, and a"
echo "      reboot just clears them. Treat debug.sf.* as root-only-effective."
EOF

# ---- assemble revert.sh the same way ----
cat "$REVERT_NR" >> "$REVERT"
{
    echo ''
    echo 'if [ "$(id -u)" = 0 ]; then'
    echo '    :'
} >> "$REVERT"
cat "$REVERT_R" >> "$REVERT"
{
    echo 'else'
    echo '    echo "reverted no-root knobs; root-only knobs need root to revert."'
    echo 'fi'
} >> "$REVERT"

cat >> "$REVERT" <<'EOF'

service call SurfaceFlinger 1008 i32 1 >/dev/null 2>&1
echo "reverted. reboot recommended."
EOF

rm -f "$APPLY_NR" "$APPLY_R" "$REVERT_NR" "$REVERT_R"
chmod +x "$APPLY" "$REVERT"

# Stable convenience copies. The per-run apply.sh lives in a timestamped
# dir, and "scewin-dump-latest" is only a pointer FILE (sdcard can't hold
# symlinks), so `sh /sdcard/scewin-dump-latest/apply.sh` never works. These
# fixed-name copies always point at the most recent generation. apply.sh is
# self-contained, so a plain copy runs fine.
PARENT=$(dirname "$DUMP")
APPLY_STABLE="$PARENT/scewin-apply-latest.sh"
REVERT_STABLE="$PARENT/scewin-revert-latest.sh"
cp "$APPLY" "$APPLY_STABLE" 2>/dev/null && chmod +x "$APPLY_STABLE" 2>/dev/null
cp "$REVERT" "$REVERT_STABLE" 2>/dev/null && chmod +x "$REVERT_STABLE" 2>/dev/null

echo "wrote $APPLY"
echo "wrote $REVERT"
echo "wrote $SKIPPED  (keys not present on this device)"
echo
# Use grep -E for POSIX alternation; toybox grep on Android treats \| as
# literal under default BRE, returning 0 for everything.
applied_n=$(grep -cE '^(setprop|settings put|device_config put)' "$APPLY")
echo "total knobs emitted:  ~$applied_n commands"
echo "  apply WITHOUT root:  $noroot_count   (settings, device_config, debug.* props)"
echo "  need root (guarded): $root_count   (vendor/persist/dalvik props, sysfs)"
echo "skipped:               $(wc -l < "$SKIPPED") known-impact keys not present on this firmware"
echo
echo "Review, then apply — use these stable paths (no need to chase the timestamp):"
echo "    cat $APPLY_STABLE       # review first"
echo "    sh  $APPLY_STABLE       # apply  (root-only knobs auto-skip if not root)"
echo "    sh  $REVERT_STABLE      # revert anytime"
