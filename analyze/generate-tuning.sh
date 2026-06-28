#!/system/bin/sh
# Generate apply.sh + revert.sh that are SPECIFIC to your tablet.
#
# Mechanism: intersect analyze/known-impact-keys.tsv against
# discover/.../knobs.tsv. Only keys actually present (or always-present
# AOSP keys) make it into your apply.sh. Each comes with your current
# value commented in, so revert.sh is a 1:1 restore.
#
# Usage:  sh analyze/generate-tuning.sh /sdcard/scewin-dump-<timestamp>

set -u
DUMP="${1:-/sdcard/scewin-dump-latest}"
KNOWN="$(dirname $0)/known-impact-keys.tsv"

if [ ! -f "$DUMP/knobs.tsv" ]; then
    echo "no knobs.tsv in $DUMP — run discover/catalog.sh first" >&2
    exit 1
fi
if [ ! -f "$KNOWN" ]; then
    echo "missing $KNOWN" >&2; exit 1
fi

APPLY="$DUMP/apply.sh"
REVERT="$DUMP/revert.sh"
SKIPPED="$DUMP/apply-skipped.tsv"

cat > "$APPLY" <<EOF
#!/system/bin/sh
# Auto-generated for THIS tablet.
# Source dump: $DUMP
# Generated:   $(date)
#
# Each line is ONE knob. If something breaks, comment that one line and
# re-run to bisect.

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

# Look up current value of a key in this device's dump.
# Returns empty if not in the dump.
current_value() {
    kind="$1"; key="$2"
    awk -F'\t' -v k="$kind" -v n="$key" '$1==k && $2==n {print $3; exit}' "$DUMP/knobs.tsv"
}

apply_count=0
skip_count=0

# Parse known-impact-keys.tsv (skip header)
tail -n +2 "$KNOWN" | while IFS=$'\t' read -r kind key target source notes; do
    [ -z "$kind" ] && continue
    cur=$(current_value "$kind" "$key")

    # Decision: emit if currently present OR always-present
    if [ -z "$cur" ] && ! is_always_present "$key"; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$key" "$target" "not-present-on-device" "$source" >> "$SKIPPED"
        skip_count=$((skip_count+1))
        continue
    fi
    [ -z "$cur" ] && cur='<unset, framework default>'

    # Emit the apply command, with the source noted inline
    case "$kind" in
        prop)
            printf '\n# %s    (was: %s)    [%s]\nsetprop %s %s\n' \
                "$notes" "$cur" "$source" "$key" "$(printf '%q' "$target")" >> "$APPLY"
            printf '\nsetprop %s %s\n' "$key" "$(printf '%q' "$cur")" >> "$REVERT"
            ;;
        setting_global)
            printf '\n# %s    (was: %s)\nsettings put global %s %s\n' \
                "$notes" "$cur" "$key" "$target" >> "$APPLY"
            printf 'settings put global %s %s\n' "$key" "$cur" >> "$REVERT"
            ;;
        setting_system)
            printf '\n# %s    (was: %s)\nsettings put system %s %s\n' \
                "$notes" "$cur" "$key" "$target" >> "$APPLY"
            printf 'settings put system %s %s\n' "$key" "$cur" >> "$REVERT"
            ;;
        setting_secure)
            printf '\n# %s    (was: %s)\nsettings put secure %s %s\n' \
                "$notes" "$cur" "$key" "$target" >> "$APPLY"
            printf 'settings put secure %s %s\n' "$key" "$cur" >> "$REVERT"
            ;;
        device_config)
            ns="${key%%/*}"; name="${key#*/}"
            printf '\n# %s    (was: %s)\ndevice_config put %s %s %s\n' \
                "$notes" "$cur" "$ns" "$name" "$target" >> "$APPLY"
            printf 'device_config put %s %s %s\n' "$ns" "$name" "$cur" >> "$REVERT"
            ;;
    esac
    apply_count=$((apply_count+1))
done

# tail of apply.sh — final hook for one-shot service restarts that
# make some properties take effect immediately
cat >> "$APPLY" <<'EOF'

# --- post-apply: nudge services so debug.sf.* / debug.hwui.* take effect ---
# SurfaceFlinger picks up debug.sf.* on next boot OR via service restart.
# The cleanest way without rebooting:
service call SurfaceFlinger 1008 i32 1 >/dev/null 2>&1   # repaint everything
echo "applied. some debug.sf.* take effect only after reboot — reboot for full effect."
EOF

cat >> "$REVERT" <<'EOF'

service call SurfaceFlinger 1008 i32 1 >/dev/null 2>&1
echo "reverted. reboot recommended."
EOF

chmod +x "$APPLY" "$REVERT"

echo "wrote $APPLY"
echo "wrote $REVERT"
echo "wrote $SKIPPED  (keys not present on this device)"
echo
echo "applied:  ~$(grep -c '^setprop\|^settings put\|^device_config put' "$APPLY") commands"
echo "skipped:  $(wc -l < "$SKIPPED") known-impact keys not present on this firmware"
echo
echo "Review $APPLY before running. To execute:  sh $APPLY"
echo "To revert at any time:                       sh $REVERT"
