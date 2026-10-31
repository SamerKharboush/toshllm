#!/bin/bash
# Fill the missing q6_K cell (k 8192, 2048 rows) and re-confirm the q4_K k 14336 cells.
set -u
E=/private/tmp/claude-501/-Users-sam-firellama/51472447-7400-4c91-ad80-addb9c10346b/scratchpad/e2
BIN=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/test-backend-ops
cd /Users/sam/firellama/vendor/llama.cpp || exit 1
if pgrep -x llama-server > /dev/null; then echo "ABORT: llama-server running"; exit 1; fi

echo "round,type,k,rows,variant,gbs,pipeline" > "$E/sweep2.csv"
run() {
    local r=$1 t=$2 k=$3 m=$4 v=$5; shift 5
    local out gbs pipe
    out=$(env GGML_METAL_DEVICE_INDEX=1 TOSH_SWEEP_TYPE="$t" TOSH_SWEEP_DEBUG=1 "$@" \
        "$BIN" perf -o MUL_MAT -b MTL0 -p "type_a=$t,type_b=f32,m=$m,n=1,k=$k" 2>&1)
    gbs=$(printf '%s\n' "$out" | grep -o '[0-9][0-9.]* GB/s' | head -1 | awk '{print $1}')
    pipe=$(printf '%s\n' "$out" | grep -m1 'SWEEP pipeline = ' | awk '{print $4}')
    [ -z "$gbs" ] && gbs=NA
    [ -z "$pipe" ] && pipe=NA
    echo "$r,$t,$k,$m,$v,$gbs,$pipe" >> "$E/sweep2.csv"
}
for r in 1 2 3 4 5; do
    if [ $((r % 2)) -eq 1 ]; then
        run $r q6_K 8192 2048 r4 TOSH_SWEEP_NR0=4
        run $r q6_K 8192 2048 r8 TOSH_SWEEP_NR0=8
    else
        run $r q6_K 8192 2048 r8 TOSH_SWEEP_NR0=8
        run $r q6_K 8192 2048 r4 TOSH_SWEEP_NR0=4
    fi
    for m in 6144 8192 14336; do
        if [ $((r % 2)) -eq 1 ]; then
            run $r q4_K 14336 $m r8 TOSH_SWEEP_NR0=8
            run $r q4_K 14336 $m L16r8 TOSH_SWEEP_NR0=8 TOSH_SWEEP_LANES=16
        else
            run $r q4_K 14336 $m L16r8 TOSH_SWEEP_NR0=8 TOSH_SWEEP_LANES=16
            run $r q4_K 14336 $m r8 TOSH_SWEEP_NR0=8
        fi
    done
    echo "ROUND $r done" >> "$E/sweep2.log"
done
echo "SWEEP2 DONE" >> "$E/sweep2.log"
