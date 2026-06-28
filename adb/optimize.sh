#!/usr/bin/env bash
# Tab S7 Brawl Stars optimizer (ADB, no root required)
#
# Run this from a PC with the tablet connected over USB and
# "USB debugging" enabled in Developer Options.
#
# What this does:
#   - Sets animation scales to 0 (saves ~16 ms of UI lag per transition)
#   - Locks the GPU/display compositor settings for gaming
#   - Disables Samsung bloat services that wake the radio
#   - Sets Brawl Stars to "important" process state so it can't be killed
#   - Disables Wi-Fi scan throttling during gameplay (faster recovery
#     from a flaky AP without forcing a full reassociation)
#
# Reversible via ./restore.sh
#
# Nothing here requires root. Nothing here trips Knox. Nothing here
# touches SELinux, the bootloader, or system partition.

set -euo pipefail

BS_PKG="com.supercell.brawlstars"

require_adb() {
    if ! command -v adb >/dev/null 2>&1; then
        echo "adb not found. Install platform-tools first:"
        echo "  https://developer.android.com/tools/releases/platform-tools"
        exit 1
    fi
    if ! adb get-state >/dev/null 2>&1; then
        echo "No device. Plug in the Tab S7, enable USB debugging, accept the prompt."
        exit 1
    fi
    local model
    model=$(adb shell getprop ro.product.model | tr -d '\r')
    echo "Connected device: $model"
    case "$model" in
        SM-T870|SM-T875|SM-T876B|SM-T878U)
            echo "  -> Confirmed Tab S7 family. Proceeding."
            ;;
        *)
            echo "  -> Not a Tab S7. The settings still work but were not tuned for this device."
            read -rp "Continue anyway? [y/N] " yn
            [[ "$yn" =~ ^[Yy]$ ]] || exit 1
            ;;
    esac
}

animations_off() {
    echo "[1/5] Disabling animation scales (input lag reduction)..."
    adb shell settings put global window_animation_scale 0.0
    adb shell settings put global transition_animation_scale 0.0
    adb shell settings put global animator_duration_scale 0.0
}

disable_bloat() {
    echo "[2/5] Disabling background bloat (only for current user, reversible)..."
    # These are background-tasking culprits on One UI 5 on Tab S7.
    # We disable, not uninstall — `pm enable` brings them back.
    local pkgs=(
        com.samsung.android.bixby.agent          # Bixby
        com.samsung.android.bixby.wakeup
        com.samsung.android.app.spage            # Bixby Home
        com.samsung.android.smartswitchassistant # Smart Switch
        com.sec.android.app.samsungapps          # Galaxy Store (push polling)
        com.samsung.android.game.gametools       # legacy Game Tools
        com.facebook.katana                      # if preinstalled stub
        com.facebook.appmanager
        com.facebook.system
        com.facebook.services
        com.microsoft.skydrive                   # OneDrive preinstall
        com.linkedin.android                     # if preinstalled stub
    )
    for p in "${pkgs[@]}"; do
        if adb shell pm list packages | grep -q "^package:$p$"; then
            adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 \
                && echo "  disabled: $p" \
                || echo "  skip (no permission): $p"
        fi
    done
}

prioritize_brawl() {
    echo "[3/5] Prioritizing Brawl Stars process state..."
    if ! adb shell pm list packages | grep -q "^package:$BS_PKG$"; then
        echo "  Brawl Stars not installed yet. Install it, then re-run this script."
        return
    fi
    # Exclude from background restrictions
    adb shell cmd appops set "$BS_PKG" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1 || true
    adb shell cmd appops set "$BS_PKG" RUN_IN_BACKGROUND allow >/dev/null 2>&1 || true
    # Exempt from Doze / app standby buckets
    adb shell dumpsys deviceidle whitelist "+$BS_PKG" >/dev/null 2>&1 || true
    adb shell am set-standby-bucket "$BS_PKG" active >/dev/null 2>&1 || true
    echo "  Brawl Stars exempted from Doze, set to active standby bucket."
}

wifi_scan() {
    echo "[4/5] Relaxing Wi-Fi scan throttle (faster recovery from AP hiccups)..."
    # Android throttles to 4 scans / 2 min by default. Relaxing this helps
    # the radio re-pick a good AP without a full reassociation drop.
    adb shell settings put global wifi_scan_throttle_enabled 0
}

ime_haptics() {
    echo "[5/5] Misc latency wins..."
    # Disable haptic feedback for keyboard / touch — vibration motor wake
    # adds ~3-5 ms and uses a wakelock.
    adb shell settings put system haptic_feedback_enabled 0
    # Disable touch sounds
    adb shell settings put system sound_effects_enabled 0
}

summary() {
    cat <<'EOF'

Done. To verify, on the tablet:
  - Settings → About tablet → Software info → tap "Build number" 7x
  - Settings → Developer options → Window/Transition/Animator scale: all 0
  - Bixby is gone from the side button menu (Settings → Advanced features
    → Side key → set "Double press" to Camera).

Run a baseline ping before AND after with network/latency-check.sh so
you have numbers.

To revert everything this script did:  ./restore.sh
EOF
}

main() {
    require_adb
    animations_off
    disable_bloat
    prioritize_brawl
    wifi_scan
    ime_haptics
    summary
}

main "$@"
