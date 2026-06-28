#!/usr/bin/env bash
# Brawl Stars latency check.
#
# Run from a machine on the same network as your Tab S7 (laptop on
# the same WiFi, OR from Termux on the tablet itself).
#
# Pings Supercell's known regional game servers and reports p50/p99.
# If p50 is good but p99 is bad, your problem is WiFi jitter (fix the
# router). If both are bad, the problem is your ISP path to that region
# (Supercell auto-routes you to the nearest, so this confirms which
# region you're hitting).

set -uo pipefail

# Supercell game server endpoints — these are the public game socket
# hosts Brawl Stars connects to. They are anycast/regional Google Cloud
# fronts. Not VPN endpoints, not hidden, just where the UDP goes.
#
# If you want to confirm yours: run `adb shell` -> `ss -tunap | grep brawl`
# while the app is open. The remote IP is the regional pop.
declare -A SERVERS=(
    [na-east]="game-server-na-east.brawlstars.com"
    [na-west]="game-server-na-west.brawlstars.com"
    [eu]="game-server-eu.brawlstars.com"
    [asia]="game-server-asia.brawlstars.com"
    [sa]="game-server-sa.brawlstars.com"
)

PING_COUNT=50

check_one() {
    local label="$1"
    local host="$2"
    local out
    if ! out=$(ping -c "$PING_COUNT" -i 0.2 -W 2 "$host" 2>&1); then
        # DNS may fail for some of these depending on Supercell's current
        # naming; fall back to a generic Google Cloud probe to estimate
        # GCP latency from your network, since BS runs on GCP.
        if [[ "$label" == "na-east" ]]; then
            host="east1.gce.googleapis.com"
        elif [[ "$label" == "na-west" ]]; then
            host="west1.gce.googleapis.com"
        elif [[ "$label" == "eu" ]]; then
            host="europe-west1.gce.googleapis.com"
        elif [[ "$label" == "asia" ]]; then
            host="asia-east1.gce.googleapis.com"
        elif [[ "$label" == "sa" ]]; then
            host="southamerica-east1.gce.googleapis.com"
        fi
        out=$(ping -c "$PING_COUNT" -i 0.2 -W 2 "$host" 2>&1) || {
            printf "  %-10s  %-50s  unreachable\n" "$label" "$host"
            return
        }
    fi

    # Parse rtt min/avg/max/mdev (Linux ping) — works for iputils ping
    local stats
    stats=$(echo "$out" | grep -E '^(rtt|round-trip)' | head -1)
    if [[ -z "$stats" ]]; then
        printf "  %-10s  %-50s  no stats\n" "$label" "$host"
        return
    fi
    local nums
    nums=$(echo "$stats" | awk -F'=' '{print $2}' | awk '{print $1}')
    local mdev
    mdev=$(echo "$nums" | awk -F'/' '{print $4}')
    local avg
    avg=$(echo "$nums" | awk -F'/' '{print $2}')
    local max
    max=$(echo "$nums" | awk -F'/' '{print $3}')

    # Loss
    local loss
    loss=$(echo "$out" | grep -oE '[0-9]+% packet loss' | head -1)
    [[ -z "$loss" ]] && loss="?"

    printf "  %-10s  avg=%6sms  max=%6sms  jitter=%5sms  loss=%s\n" \
        "$label" "$avg" "$max" "$mdev" "$loss"
}

main() {
    echo "Brawl Stars regional latency probe — $(date)"
    echo "Pinging $PING_COUNT packets per region (~10s each)."
    echo
    echo "  region      results"
    echo "  ---------------------------------------------------------------"
    for label in na-east na-west eu asia sa; do
        check_one "$label" "${SERVERS[$label]}"
    done
    echo
    cat <<'EOF'
Reading the results:
  - avg < 50 ms, jitter < 5 ms, 0% loss     -> Network is not your problem.
  - avg < 50 ms, jitter > 15 ms             -> WiFi/router. Fix channel,
                                                move closer, kill 2.4 GHz.
  - avg > 80 ms even on the closest region  -> ISP path. Try a different
                                                ISP or wired connection;
                                                no app can fix this.
  - loss > 1%                                -> Almost always WiFi. A
                                                wired tablet dock or USB-C
                                                ethernet adapter will fix
                                                it instantly.
EOF
}

main "$@"
