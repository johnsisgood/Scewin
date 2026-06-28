#!/system/bin/sh
# Turn a raw dump into a flat inventory of writable knobs that exist on
# THIS specific tablet. This is the SCEWIN /o equivalent — a single
# table, every key, every current value, ready to grep.
#
# Usage:  sh catalog.sh /sdcard/scewin-dump-<timestamp>
# Output: $DUMP/knobs.tsv  — tab-separated:
#           kind  key  current_value  category
#
#   kind ∈ { prop  setting_global  setting_system  setting_secure
#            device_config  sysfs_cpufreq  sysfs_kgsl  sysfs_devfreq }

set -u
DUMP="${1:-/sdcard/scewin-dump-latest}"
if [ ! -d "$DUMP" ]; then
    echo "no such dump dir: $DUMP" >&2; exit 1
fi

OUT="$DUMP/knobs.tsv"
: > "$OUT"

# --- categorizer -----------------------------------------------------------
# Pure-shell pattern match → category tag. Used to rank importance.
categorize() {
    case "$1" in
        debug.sf.*|debug.hwui.*|debug.choreographer.*) echo display ;;
        debug.egl.*|ro.opengles.*)                     echo display ;;
        persist.vendor.qti.sf.*|vendor.display.*)      echo display ;;
        *animation_scale*)                              echo display ;;
        *touch*|*input*|persist.vendor.qti.inputopts.*) echo input ;;
        *haptic*|*vibrat*)                              echo input ;;
        *wifi*|*wlan*|persist.vendor.wifi.*)            echo radio ;;
        *radio*|*ril*|*modem*|persist.vendor.radio.*)   echo radio ;;
        *bluetooth*|*bt_*)                              echo radio ;;
        debug.perf*|persist.vendor.qti.perfd.*)         echo perf ;;
        vendor.perf.*|persist.vendor.qti.gameopt.*)     echo perf ;;
        *cpu*|*cluster*|*little*|*big*|*prime*)         echo perf ;;
        *gpu*|kgsl*|adreno*)                            echo perf ;;
        *thermal*|*throttle*|*temp_*)                   echo thermal ;;
        *doze*|*idle*|*standby*|app_standby*)           echo power ;;
        *cached*|max_phantom*|max_cached_processes*)    echo power ;;
        sem_*|samsung*|knox*|csc_*|game_*)              echo samsung ;;
        *)                                              echo other ;;
    esac
}

# POSIX-safe tab — $'\t' is bash-only and breaks under Termux sh.
TAB=$(printf '\t')

# Strip tab/newline from values so col-4 stays "category" in the TSV.
sanitize() { printf '%s' "$1" | tr '\t\n\r' '   '; }

# --- 1. settings (global/system/secure) -----------------------------------
for ns in global system secure; do
    f="$DUMP/settings.$ns.txt"
    [ -f "$f" ] || continue
    while IFS= read -r line; do
        key=${line%%=*}
        val=${line#*=}
        cat=$(categorize "$key")
        val=$(sanitize "$val")
        printf "setting_%s\t%s\t%s\t%s\n" "$ns" "$key" "$val" "$cat" >> "$OUT"
    done < "$f"
done

# --- 2. system properties --------------------------------------------------
PARSED=/data/local/tmp/.scewin-getprop.$$
awk -F'\\]: \\[' '
    /^\[/ {
        k = substr($1, 2)
        v = substr($2, 1, length($2)-1)
        gsub(/\t/, " ", v); gsub(/\r/, "", v)
        print k "\t" v
    }' "$DUMP/getprop.txt" > "$PARSED"

while IFS="$TAB" read -r key val; do
    [ -z "$key" ] && continue
    cat=$(categorize "$key")
    printf "prop\t%s\t%s\t%s\n" "$key" "$val" "$cat" >> "$OUT"
done < "$PARSED"
rm -f "$PARSED"

# --- 3. device_config ------------------------------------------------------
PARSED=/data/local/tmp/.scewin-dc.$$
awk '
    /^=== namespace: / { ns = $3; next }
    /=/ {
        i = index($0, "=")
        key = substr($0, 1, i-1)
        val = substr($0, i+1)
        gsub(/\t/, " ", val); gsub(/\r/, "", val)
        print ns "/" key "\t" val
    }' "$DUMP/device_config.txt" 2>/dev/null > "$PARSED"

while IFS="$TAB" read -r key val; do
    [ -z "$key" ] && continue
    cat=$(categorize "$key")
    printf "device_config\t%s\t%s\t%s\n" "$key" "$val" "$cat" >> "$OUT"
done < "$PARSED"
rm -f "$PARSED"

# --- 4. sysfs (CPU/GPU/devfreq) -------------------------------------------
# These are lines like:  /sys/.../min_freq = 300000
for f in "$DUMP/sysfs/cpufreq.txt" \
         "$DUMP/sysfs/kgsl.txt" \
         "$DUMP/sysfs/devfreq.txt"; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
        case "$line" in
            *=*)
                key=$(echo "$line" | sed 's/ *=.*//')
                val=$(echo "$line" | sed 's/^[^=]*= *//')
                kind=$(basename "$f" .txt)
                cat=perf
                printf "sysfs_%s\t%s\t%s\t%s\n" "$kind" "$key" "$val" "$cat" >> "$OUT"
                ;;
        esac
    done < "$f"
done

# --- summary --------------------------------------------------------------
total=$(wc -l < "$OUT")
echo "wrote $OUT ($total knobs)"
echo
echo "by category:"
awk -F'\t' '{c[$4]++} END {for (k in c) printf "  %-10s %6d\n", k, c[k]}' "$OUT" | sort -k2 -n -r
echo
echo "by kind:"
awk -F'\t' '{k[$1]++} END {for (n in k) printf "  %-20s %6d\n", n, k[n]}' "$OUT" | sort -k2 -n -r
echo
echo "next: sh analyze/generate-tuning.sh $DUMP"
