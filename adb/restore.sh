#!/usr/bin/env bash
# Undo everything optimize.sh did. Safe to run anytime.

set -euo pipefail

BS_PKG="com.supercell.brawlstars"

require_adb() {
    if ! command -v adb >/dev/null 2>&1; then
        echo "adb not found."; exit 1
    fi
    if ! adb get-state >/dev/null 2>&1; then
        echo "No device. Plug in and enable USB debugging."; exit 1
    fi
}

restore_animations() {
    echo "Restoring animation scales to default (1.0)..."
    adb shell settings put global window_animation_scale 1.0
    adb shell settings put global transition_animation_scale 1.0
    adb shell settings put global animator_duration_scale 1.0
}

restore_bloat() {
    echo "Re-enabling Samsung / preinstalled packages..."
    local pkgs=(
        com.samsung.android.bixby.agent
        com.samsung.android.bixby.wakeup
        com.samsung.android.app.spage
        com.samsung.android.smartswitchassistant
        com.sec.android.app.samsungapps
        com.samsung.android.game.gametools
        com.facebook.katana
        com.facebook.appmanager
        com.facebook.system
        com.facebook.services
        com.microsoft.skydrive
        com.linkedin.android
    )
    for p in "${pkgs[@]}"; do
        if adb shell pm list packages -d | grep -q "^package:$p$"; then
            adb shell pm enable "$p" >/dev/null 2>&1 \
                && echo "  enabled: $p" \
                || echo "  skip: $p"
        fi
    done
}

restore_brawl() {
    echo "Removing Brawl Stars Doze exemption..."
    adb shell dumpsys deviceidle whitelist "-$BS_PKG" >/dev/null 2>&1 || true
}

restore_wifi() {
    echo "Restoring Wi-Fi scan throttle..."
    adb shell settings put global wifi_scan_throttle_enabled 1
}

restore_haptics() {
    echo "Restoring haptics and touch sounds..."
    adb shell settings put system haptic_feedback_enabled 1
    adb shell settings put system sound_effects_enabled 1
}

main() {
    require_adb
    restore_animations
    restore_bloat
    restore_brawl
    restore_wifi
    restore_haptics
    echo "Done. Reboot recommended."
}

main "$@"
