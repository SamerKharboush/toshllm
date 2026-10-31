#!/bin/bash
# q6_K forced r4 vs r8 and q4_K forced r8 vs L16r8, as a function of k, rows fixed per family.
# One process per cell per variant per round; variants alternate inside each round.
set -u
E=/private/tmp/claude-501/-Users-sam-firellama/51472447-7400-4c91-ad80-addb9c10346b/scratchpad/e2
BIN=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/test-backend-ops
cd /Users/sam/firellama/vendor/llama.cpp || exit 1

if pgrep -x llama-server > /dev/null; then
    echo "ABORT: llama-server running"; exit 1
fi

echo "round,type,k,rows,variant,gbs,pipeline" > "$E/sweep1.csv"
: > "$E/sweep1.log"

run() { # round type k rows variant extra-env...
    local r=$1 t=$2 k=$3 m=$4 v=$5; shift 5
    local out
    out=$(env GGML_METAL_DEVICE_INDEX=1 TOSH_SWEEP_TYPE="$t" TOSH_SWEEP_DEBUG=1 "$@" \
        "$BIN" perf -o MUL_MAT -b MTL0 -p "type_a=$t,type_b=f32,m=$m,n=1,k=$k" 2>&1)
    local gbs pipe
    gbs=$(printf '%s\n' "$out" | grep -o '[0-9][0-9.]* GB/s' | head -1 | awk '{print $1}')
    pipe=$(printf '%s\n' "$out" | grep -m1 'SWEEP pipeline = ' | awk '{print $4}')
    [ -z "$gbs" ] && gbs=NA
    [ -z "$pipe" ] && pipe=NA
    echo "$r,$t,$k,$m,$v,$gbs,$pipe" >> "$E/sweep1.csv"
    echo "$r,$t,$k,$m,$v,$gbs,$pipe" >> "$E/sweep1.log"
}

ROUNDS=5
for r in $(seq 1 $ROUNDS); do
    for k in 1024 4096 8192 12288; do
        for m in 1024 1280 1536 1792 2048; do
            if [ $((r % 2)) -eq 1 ]; then
                run $r q6_K $k $m r4 TOSH_SWEEP_NR0=4
                run $r q6_K $k $m r8 TOSH_SWEEP_NR0=8
            else
                run $r q6_K $k $m r8 TOSH_SWEEP_NR0=8
                run $r q6_K $k $m r4 TOSH_SWEEP_NR0=4
            fi
        done
    done
    for k in 2560 8192 14336; do
        for m in 6144 8192 10240 12288 14336; do
            if [ $((r % 2)) -eq 1 ]; then
                run $r q4_K $k $m r8 TOSH_SWEEP_NR0=8
                run $r q4_K $k $m L16r8 TOSH_SWEEP_NR0=8 TOSH_SWEEP_LANES=16
            else
                run $r q4_K $k $m L16r8 TOSH_SWEEP_NR0=8 TOSH_SWEEP_LANES=16
                run $r q4_K $k $m r8 TOSH_SWEEP_NR0=8
            fi
        done
    done
    echo "ROUND $r done $(date +%H:%M:%S)" >> "$E/sweep1.log"
done
echo "SWEEP1 DONE" >> "$E/sweep1.log"
