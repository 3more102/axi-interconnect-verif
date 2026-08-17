#!/bin/bash
# =============================================================================
# mutation/run_mutations.sh -- bug-injection audit (VERIF_PLAN.md section 7)
#
# For each row of mutations.txt: copy the project to a scratch tree, apply one
# single-line change to the RTL there, run the tests that are supposed to catch
# it, and record KILLED (at least one target failed) or SURVIVED (none did).
#
# A survivor means the listed tests cannot see that defect -- a verification
# hole to close, not a result to shrug at.
#
# Two guards keep this honest:
#   * the sed expression must actually change the file, otherwise the row is
#     reported as NO-OP rather than being silently counted as a survivor;
#   * the unmutated tree is run first, and every target must PASS there, so a
#     "kill" can never be a pre-existing failure taking the credit.
#
# Usage:  ./run_mutations.sh [id ...]      (default: every row)
# =============================================================================

set -u
cd "$(dirname "$0")"
ROOT=$(cd .. && pwd)
SCRATCH=$(pwd)/scratch
CATALOGUE=mutations.txt

want=("$@")

run_sim_target() {           # $1 = scratch tree, $2 = tb:test
    local tree=$1 tb=${2%%:*} test=${2##*:}
    ( cd "$tree/sim" && make --no-print-directory run TB="$tb" TEST="$test" \
        >/dev/null 2>&1 )
}

run_formal_target() {        # $1 = scratch tree, $2 = sby:task
    local tree=$1 sby=${2%%:*} task=${2##*:}
    ( cd "$tree/formal" && rm -rf "${sby}_${task}" && \
        sby -f "${sby}.sby" "$task" >/dev/null 2>&1 )
}

run_targets() {              # $1 = tree, $2 = tier, $3 = comma list
    local tree=$1 tier=$2 list=$3 t
    local nfail=0
    IFS=',' read -ra tgts <<< "$list"
    for t in "${tgts[@]}"; do
        if [ "$tier" = formal ]; then
            run_formal_target "$tree" "$t" || nfail=$((nfail + 1))
        else
            run_sim_target "$tree" "$t" || nfail=$((nfail + 1))
        fi
    done
    echo "$nfail"
}

rm -rf "$SCRATCH"
mkdir -p "$SCRATCH"

# ---- baseline: the clean tree, so a "kill" cannot be a pre-existing failure --
BASE="$SCRATCH/base"
mkdir -p "$BASE"
cp -r "$ROOT/rtl" "$ROOT/tb" "$ROOT/sim" "$ROOT/formal" "$BASE/" 2>/dev/null
rm -rf "$BASE/sim/build" "$BASE/sim/logs" "$BASE"/formal/*/ 2>/dev/null
( cd "$BASE/sim" && make --no-print-directory compile >/dev/null 2>&1 ) || {
    echo "baseline build FAILED -- aborting"; exit 1; }

killed=0; survived=0; noop=0; total=0
declare -a rows

printf '%-5s %-9s %-8s %s\n' "ID" "TIER" "RESULT" "DESCRIPTION"
printf '%s\n' "----------------------------------------------------------------------------"

while IFS='|' read -r id file sedexpr tier targets desc; do
    case "$id" in ''|\#*) continue ;; esac
    if [ ${#want[@]} -gt 0 ]; then
        found=0
        for w in "${want[@]}"; do [ "$w" = "$id" ] && found=1; done
        [ $found -eq 1 ] || continue
    fi
    total=$((total + 1))

    # baseline check: every target must pass on the clean tree
    nbase=$(run_targets "$BASE" "$tier" "$targets")
    if [ "$nbase" -ne 0 ]; then
        printf '%-5s %-9s %-8s %s\n' "$id" "$tier" "BASEFAIL" "$desc"
        rows+=("$id|$tier|BASEFAIL|$desc")
        continue
    fi

    TREE="$SCRATCH/$id"
    rm -rf "$TREE"; mkdir -p "$TREE"
    cp -r "$ROOT/rtl" "$ROOT/tb" "$ROOT/sim" "$ROOT/formal" "$TREE/" 2>/dev/null
    rm -rf "$TREE/sim/build" "$TREE/sim/logs" "$TREE"/formal/*/ 2>/dev/null

    before=$(md5sum "$TREE/rtl/$file" | cut -d' ' -f1)
    sed -i "$sedexpr" "$TREE/rtl/$file"
    after=$(md5sum "$TREE/rtl/$file" | cut -d' ' -f1)
    if [ "$before" = "$after" ]; then
        printf '%-5s %-9s %-8s %s\n' "$id" "$tier" "NO-OP" "$desc (sed matched nothing)"
        rows+=("$id|$tier|NO-OP|$desc")
        noop=$((noop + 1))
        continue
    fi

    if [ "$tier" = sim ]; then
        ( cd "$TREE/sim" && make --no-print-directory compile >/dev/null 2>&1 ) || {
            printf '%-5s %-9s %-8s %s\n' "$id" "$tier" "KILLED" "$desc (build error)"
            rows+=("$id|$tier|KILLED|$desc"); killed=$((killed + 1)); continue; }
    fi

    nfail=$(run_targets "$TREE" "$tier" "$targets")
    if [ "$nfail" -gt 0 ]; then
        printf '%-5s %-9s %-8s %s\n' "$id" "$tier" "KILLED" "$desc"
        rows+=("$id|$tier|KILLED|$desc")
        killed=$((killed + 1))
    else
        printf '%-5s %-9s %-8s %s\n' "$id" "$tier" "SURVIVED" "$desc"
        rows+=("$id|$tier|SURVIVED|$desc")
        survived=$((survived + 1))
    fi
    rm -rf "$TREE"
done < "$CATALOGUE"

echo
echo "MUTATION SCORE: $killed/$total killed  ($survived survived, $noop no-op)"
rm -rf "$BASE"
[ "$survived" -eq 0 ] && [ "$noop" -eq 0 ]
