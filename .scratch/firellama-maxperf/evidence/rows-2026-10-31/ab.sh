#!/bin/bash
# DFlash drafter head A/B: H (TOSH_DFLASH_HEAD_HOST=1) vs D (device copy), order H D H D, then plain P.
S=/private/tmp/claude-501/-Users-sam-firellama/51472447-7400-4c91-ad80-addb9c10346b/scratchpad/e1
REPO=/Users/sam/firellama/vendor/llama.cpp
SRV=$REPO/build-static/bin/llama-server
REQ=/Users/sam/firellama/.scratch/firellama-maxperf/evidence/rows-2026-10-30/0d-req.py
TGT=/Users/sam/models/deepreinforce-ai/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf
DFT=/Users/sam/models/Qwen3.6-35B-A3B-DFlash-Q8_0.gguf

cd "$REPO" || exit 1

say() { echo "[$(date '+%H:%M:%S')] $*"; }

check_idle() {
    local p
    # -x: match the process name only, so shell wrappers that merely mention the
    # binary in their command line do not abort the run
    p=$(pgrep -x llama-server)
    if [ -n "$p" ]; then
        say "ABORT: another llama-server is running:"
        echo "$p"
        return 1
    fi
    return 0
}

wait_listen() {
    local log=$1
    local n=0
    while [ $n -lt 900 ]; do
        if grep -q "listening on" "$log" 2>/dev/null; then
            return 0
        fi
        if ! pgrep -x llama-server > /dev/null; then
            say "server process died before listening"
            return 1
        fi
        sleep 1
        n=$((n+1))
    done
    say "timeout waiting for listening"
    return 1
}

stop_server() {
    pkill -x llama-server 2>/dev/null
    local n=0
    while pgrep -x llama-server > /dev/null && [ $n -lt 60 ]; do
        sleep 1
        n=$((n+1))
    done
    pkill -9 -x llama-server 2>/dev/null
    sleep 20
}

run_cell() {
    local cell=$1 head_host=$2 plain=$3
    local log=$S/$cell.log

    say "===== cell $cell (head_host=$head_host plain=$plain) ====="
    if ! check_idle; then return 1; fi

    if [ "$plain" = "1" ]; then
        GGML_METAL_DEVICE_INDEX=1 "$SRV" \
            -m "$TGT" --port 8091 -ngl 0 -c 16384 -t 12 -fa auto \
            --load-mode none --parallel 1 --cache-ram 0 \
            -lv 4 > "$log" 2>&1 &
    elif [ "$head_host" = "1" ]; then
        TOSH_FA_AMD=1 TOSH_DFLASH_HEAD_HOST=1 GGML_METAL_DEVICE_INDEX=1 "$SRV" \
            -m "$TGT" --port 8091 -ngl 0 -c 16384 -t 12 -fa auto \
            --load-mode none --parallel 1 --cache-ram 0 \
            -md "$DFT" --spec-type draft-dflash -ngld all -devd MTL0 \
            --spec-draft-n-max 3 -lv 4 > "$log" 2>&1 &
    else
        TOSH_FA_AMD=1 GGML_METAL_DEVICE_INDEX=1 "$SRV" \
            -m "$TGT" --port 8091 -ngl 0 -c 16384 -t 12 -fa auto \
            --load-mode none --parallel 1 --cache-ram 0 \
            -md "$DFT" --spec-type draft-dflash -ngld all -devd MTL0 \
            --spec-draft-n-max 3 -lv 4 > "$log" 2>&1 &
    fi

    if ! wait_listen "$log"; then
        say "cell $cell: server failed to start"
        stop_server
        return 1
    fi
    say "cell $cell: listening"

    say "cell $cell: running 4 requests"
    python3 "$REQ" 4 "$S/$cell" 2>&1
    say "cell $cell: requests done (rc=$?)"

    say "cell $cell: head line:"
    grep -i "lm head" "$log" || echo "(no lm head line)"

    stop_server
    say "cell $cell: done"
    return 0
}

say "===== AB START ====="
rm -f "$S"/H1*.log "$S"/H2*.log "$S"/D1*.log "$S"/D2*.log "$S"/P*.log 2>/dev/null
rm -f "$S"/H1-*.txt "$S"/H2-*.txt "$S"/D1-*.txt "$S"/D2-*.txt "$S"/P-*.txt 2>/dev/null

if ! check_idle; then say "AB ABORT (pre)"; exit 1; fi

run_cell H1 1 0 || say "cell H1 failed"
run_cell D1 0 0 || say "cell D1 failed"
run_cell H2 1 0 || say "cell H2 failed"
run_cell D2 0 0 || say "cell D2 failed"
run_cell P  0 1 || say "cell P failed"

say "===== AB DONE ====="
ls -1 "$S"/H1-*.txt "$S"/H2-*.txt "$S"/D1-*.txt "$S"/D2-*.txt "$S"/P-*.txt 2>/dev/null | wc -l
