#!/bin/bash
# =============================================================================
# sim/report.sh -- regression result table for the AXI4 interconnect project
# Implements VERIF_PLAN.md section 5.
#
# Reads every logs/*.log produced by `make regress`, prints one row per run,
# aggregates the functional-coverage lines, and exits non-zero if any run did
# not print "=== TEST PASSED".
#
# A log with no verdict at all (crash, or watchdog before the summary) counts
# as a failure -- absence of a PASS is never treated as success.
# =============================================================================

set -u
cd "$(dirname "$0")"

LOGDIR=logs
if [ ! -d "$LOGDIR" ]; then
    echo "report.sh: no $LOGDIR directory -- run 'make regress' first" >&2
    exit 1
fi

shopt -s nullglob
logs=("$LOGDIR"/*.log)
if [ ${#logs[@]} -eq 0 ]; then
    echo "report.sh: no logs in $LOGDIR -- run 'make regress' first" >&2
    exit 1
fi

pass=0
fail=0

printf '%-34s %-11s %-5s %s\n' "TESTBENCH" "TEST" "SEED" "RESULT"
printf '%s\n' "----------------------------------------------------------------------"

for log in "${logs[@]}"; do
    base=$(basename "$log" .log)
    tb=${base%%__*}
    rest=${base#*__}
    case "$rest" in
        *__s*) test=${rest%%__s*}; seed=${rest##*__s} ;;
        *)     test=$rest;         seed=1 ;;
    esac

    if grep -q '=== TEST PASSED' "$log"; then
        result=PASS
        pass=$((pass + 1))
    else
        result=FAIL
        fail=$((fail + 1))
    fi
    printf '%-34s %-11s %-5s %s\n' "$tb" "$test" "$seed" "$result"
done

total=$((pass + fail))

echo
echo "---- functional coverage (per run) ----"
grep -h '^COVERAGE ' "${logs[@]}" | sort -u || true

# Union coverage: a bin counts as hit if any run in the regression hit it.
echo
echo "---- functional coverage (regression union) ----"
awk '
    /^\[[A-Z0-9]+\][ \t]+[A-Za-z0-9_]+ = [0-9]+$/ {
        name = $2; count = $4
        seen[name] = 1
        if (count > 0) hit[name] = 1
    }
    END {
        n = 0; h = 0
        for (b in seen) {
            n++
            if (b in hit) h++
            else printf "  MISS  %s\n", b
        }
        if (n > 0)
            printf "COVERAGE UNION: %d/%d bins hit (%d%%)\n", h, n, (h * 100) / n
        else
            print "COVERAGE UNION: no coverage lines found"
    }
' "${logs[@]}"

echo
if [ "$fail" -eq 0 ]; then
    echo "REGRESSION: $pass/$total PASSED"
    exit 0
else
    echo "REGRESSION: $pass/$total PASSED ($fail FAILED)"
    exit 1
fi
