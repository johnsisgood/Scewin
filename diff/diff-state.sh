#!/system/bin/sh
# Diff two dumps. This is how you find knobs nobody documents.
#
# Workflow:
#   1. sh discover/dump-everything.sh        → dump-A
#   2. toggle ONE thing on the tablet (Game Booster, *#*#4636#*#*, dev opt)
#   3. sh discover/dump-everything.sh        → dump-B
#   4. sh diff/diff-state.sh dump-A dump-B
#
# Output: every key whose value changed between the two snapshots.
# Most will be uninteresting (timestamps, counters). The signal hides
# in there — usually 3-10 keys that the toggle actually flips.
#
# This is the SCEWIN bisection method 1:1.
#
# Portability: pure POSIX. No process substitution (dash has none), no
# bash-only $'\t'. Works under Android /system/bin/sh (mksh), Termux
# dash, and bash. All intermediate joins go through temp files.

set -u
A="${1:?usage: diff-state.sh dump-A dump-B}"
B="${2:?usage: diff-state.sh dump-A dump-B}"

[ -d "$A" ] || { echo "no $A"; exit 1; }
[ -d "$B" ] || { echo "no $B"; exit 1; }

# Make sure both sides have been cataloged.
for d in "$A" "$B"; do
    if [ ! -f "$d/knobs.tsv" ]; then
        echo "[diff] cataloging $d ..."
        sh "$(dirname $0)/../discover/catalog.sh" "$d" >/dev/null
    fi
done

# POSIX-safe tab — $'\t' is a bash-ism.
TAB=$(printf '\t')

# Drop columns we don't want to diff on (current-value matters; category
# is derived from key, kind is key prefix). Keep: kind \t key \t value.
extract() {
    awk -F'\t' '{print $1 "\t" $2 "\t" $3}' "$1" | LC_ALL=C sort
}

TMP=/data/local/tmp/scewin-diff.$$
mkdir -p "$TMP"
extract "$A/knobs.tsv" > "$TMP/a"
extract "$B/knobs.tsv" > "$TMP/b"

# Build join-ready files keyed on the composite "kind::key":
#   <kind::key> \t <kind> \t <key> \t <value>
# join + comm both need C-collated input or they silently drop rows, so
# every sort here is LC_ALL=C to match join's byte comparison.
mkjoin() {
    awk -F'\t' '{print $1 "::" $2 "\t" $1 "\t" $2 "\t" $3}' "$1" | LC_ALL=C sort
}
mkjoin "$TMP/a" > "$TMP/a.j"
mkjoin "$TMP/b" > "$TMP/b.j"

# 1) keys whose value changed
# -o 1.1,1.3,1.4,2.4  → composite, key, A-value, B-value.
# (The old version selected 2.3 = the key again, so the value comparison
#  below always saw key==key and printed nothing. This is the fix.)
echo "=========================================================="
echo "  changed values (most likely the knob you toggled flipped)"
echo "=========================================================="
join -t "$TAB" -j 1 -o 1.1,1.3,1.4,2.4 "$TMP/a.j" "$TMP/b.j" 2>/dev/null \
    | awk -F'\t' '$3 != $4 {printf "%-52s\n  was: %s\n  now: %s\n\n", $1, $3, $4}' \
    | head -200

# Projected key sets for appeared/disappeared (sort -u, C collation).
awk -F'\t' '{print $1 "::" $2}' "$TMP/a" | LC_ALL=C sort -u > "$TMP/a.k"
awk -F'\t' '{print $1 "::" $2}' "$TMP/b" | LC_ALL=C sort -u > "$TMP/b.k"

# 2) keys that appeared
echo
echo "=========================================================="
echo "  keys that APPEARED in B (created by the toggle)"
echo "=========================================================="
LC_ALL=C comm -13 "$TMP/a.k" "$TMP/b.k" | head -100

# 3) keys that disappeared
echo
echo "=========================================================="
echo "  keys that DISAPPEARED in B (removed by the toggle)"
echo "=========================================================="
LC_ALL=C comm -23 "$TMP/a.k" "$TMP/b.k" | head -100

# 4) noise filter hint
echo
echo "=========================================================="
echo "  to add a noise filter (timestamps, sample counters):"
echo "    sh diff-state.sh \$A \$B | grep -vE 'last_|_count|_ts\$|_uptime'"
echo "=========================================================="

rm -rf "$TMP"
