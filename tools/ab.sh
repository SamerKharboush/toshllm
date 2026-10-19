#!/usr/bin/env bash
#
# ab.sh -- the A/B harness. There is no agent in this measurement path.
#
# Header, read before changing anything here:
#   * tools/calibrate/calibrate.py is NOT to be used for a verdict. It measures one
#     binary sequentially, discards warmups as invocation counts rather than tokens,
#     and shells out to a benchmark tool rather than driving the engine under test.
#     Its output may not be cited as verdict evidence.
#   * preflight() is a gate, not a report. No row is emitted until the baseline
#     binary has printed --version, produced tokens on the smoke model, and done so
#     under BOTH -ngl 0 and -ngl 99 without SIGILL. Exit 0 proves the executed path
#     is clean, not the binary: an AVX2 instruction in a kernel the smoke test never
#     reaches is invisible to it, which is why both offload settings are required.
#   * Block order is randomised, not alternating. Strict alternation confounds side
#     with drift if anything warms monotonically -- thermals, page cache, the D700s
#     downclocking. The seed is recorded so a run can be reproduced exactly.
#   * Self-test: run with --selftest and both sides are the same binary. The result
#     MUST be parity inside the noise floor. If it reports a winner, this script is
#     measuring order rather than silicon and no number it produces means anything.
#
# Usage:
#   ./tools/ab.sh --baseline BIN --fork BIN --model GGUF [--blocks N] [--out PREFIX]
#   ./tools/ab.sh --selftest --bin BIN --model GGUF [--blocks N]
#
set -uo pipefail

SMOKE_MODEL="${SMOKE_MODEL:-$HOME/models/Qwen3-0.6B-Q8_0.gguf}"
PROMPT="${PROMPT:-Explain in one paragraph why the sky appears blue.}"
WARMUP_TOKENS=200
MEASURE_TOKENS=500
MIN_BLOCKS_PER_SIDE=10
PORT="${PORT:-18765}"

die() { echo "ab.sh: $*" >&2; exit 1; }

sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# ---------------------------------------------------------------- preflight

# preflight <binary> <label>
# Prints one line per check, returns non-zero on the first failure.
preflight() {
    local bin=$1 label=$2 rc failures=0
    [ -x "$bin" ] || { echo "preflight[$label]: not executable: $bin"; return 1; }

    local ver
    ver=$("$bin" --version 2>&1 | head -1)
    echo "preflight[$label]: --version -> ${ver:-<empty>}"
    [ -n "$ver" ] || { echo "preflight[$label]: --version produced nothing"; failures=$((failures+1)); }

    local ngl
    for ngl in 0 99; do
        # 0 exercises the CPU path, 99 the offloaded path. Both must be SIGILL-free.
        local log; log=$(mktemp)
        "$bin" -m "$SMOKE_MODEL" -ngl "$ngl" -sm tensor -c 2048 -t 6 \
               --host 127.0.0.1 --port "$PORT" --no-webui >"$log" 2>&1 &
        local pid=$! ready=no
        for _ in $(seq 240); do
            curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && { ready=yes; break; }
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.5
        done
        if [ "$ready" != yes ]; then
            wait "$pid" 2>/dev/null; rc=$?
            echo "preflight[$label]: -ngl $ngl FAILED to serve, exit=$rc"
            tail -3 "$log" | sed 's/^/    /'
            [ "$rc" = 132 ] && echo "preflight[$label]: exit 132 = SIGILL, the binary executed AVX2"
            failures=$((failures+1))
        else
            local toks
            toks=$(curl -s "http://127.0.0.1:$PORT/completion" \
                     -d "{\"prompt\":\"$PROMPT\",\"n_predict\":32,\"temperature\":0}" \
                   | python3 -c 'import json,sys; print(json.load(sys.stdin)["timings"]["predicted_n"])' 2>/dev/null)
            if [ "${toks:-0}" -gt 0 ] 2>/dev/null; then
                echo "preflight[$label]: -ngl $ngl served, produced ${toks} tokens"
            else
                echo "preflight[$label]: -ngl $ngl served but produced no tokens"
                failures=$((failures+1))
            fi
            kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
        fi
        rm -f "$log"
    done
    return "$failures"
}

# ---------------------------------------------------------------- one block

# run_block <binary> <ngl> -> "tok_s pred_n therm"
run_block() {
    local bin=$1 ngl=$2 log; log=$(mktemp)
    local therm; therm=$(pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/{print $3}' | head -1)

    "$bin" -m "$MODEL" -ngl "$ngl" -sm tensor -c 8192 -t 12 \
           --host 127.0.0.1 --port "$PORT" --no-webui >"$log" 2>&1 &
    local pid=$! ready=no
    for _ in $(seq 240); do
        curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && { ready=yes; break; }
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    if [ "$ready" != yes ]; then
        wait "$pid" 2>/dev/null; local rc=$?
        rm -f "$log"; echo "ERR $rc $therm"; return 1
    fi

    # Warmup discarded by TOKENS, not by invocation count.
    curl -s "http://127.0.0.1:$PORT/completion" \
         -d "{\"prompt\":\"$PROMPT\",\"n_predict\":$WARMUP_TOKENS,\"temperature\":0,\"cache_prompt\":false}" >/dev/null

    local out
    out=$(curl -s "http://127.0.0.1:$PORT/completion" \
            -d "{\"prompt\":\"$PROMPT\",\"n_predict\":$MEASURE_TOKENS,\"temperature\":0,\"cache_prompt\":false}" \
          | python3 -c 'import json,sys; d=json.load(sys.stdin); t=d["timings"]; print(f"{t[\"predicted_per_second\"]} {t[\"predicted_n\"]}")' 2>/dev/null)

    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    rm -f "$log"
    [ -n "$out" ] || { echo "ERR parse $therm"; return 1; }
    echo "$out $therm"
}

# ---------------------------------------------------------------- main

BASELINE=""; FORK=""; SELFTEST=no; BLOCKS=0; OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --baseline) BASELINE=$2; shift 2;;
        --fork)     FORK=$2;     shift 2;;
        --bin)      BASELINE=$2; FORK=$2; SELFTEST=yes; shift 2;;
        --model)    MODEL=$2;    shift 2;;
        --blocks)   BLOCKS=$2;   shift 2;;
        --out)      OUT=$2;      shift 2;;
        --selftest) SELFTEST=yes; shift;;
        *) die "unknown argument: $1";;
    esac
done
[ -n "$BASELINE" ] || die "--baseline is required"
[ -n "${MODEL:-}" ] || die "--model is required"
[ -f "$MODEL" ] || die "model not found: $MODEL"
[ "$SELFTEST" = yes ] && FORK="$BASELINE"
BLOCKS=${BLOCKS:-$((MIN_BLOCKS_PER_SIDE * 2))}
[ "$BLOCKS" -ge $((MIN_BLOCKS_PER_SIDE * 2)) ] || \
    echo "ab.sh: warning: $BLOCKS blocks is below the ${MIN_BLOCKS_PER_SIDE}-per-side minimum" >&2

SEED=${SEED:-$(python3 -c 'import random;print(random.randrange(1,2**31))')}
OUT=${OUT:-ab-$(date +%Y%m%dT%H%M%SZ)}
CSV="${OUT}.csv"; JSON="${OUT}.json"
BASE_SHA=$(sha "$BASELINE"); FORK_SHA=$(sha "$FORK")

echo "== preflight (a gate, not a report) =="
preflight "$BASELINE" baseline || die "preflight failed: the baseline is not fit to measure"
preflight "$FORK" fork || die "preflight failed: the fork binary is not fit to measure"

{
    echo "# ab.sh schema_version=1"
    echo "# seed=$SEED blocks=$BLOCKS warmup_tokens=$WARMUP_TOKENS measure_tokens=$MEASURE_TOKENS"
    echo "# model=$MODEL"
    echo "# baseline_sha256=$BASE_SHA"
    echo "# fork_sha256=$FORK_SHA"
    echo "# selftest=$SELFTEST"
    echo "# note: thermal is the CPU_Speed_Limit reported by pmset at block start"
    echo "block,order,side,ngl,tok_s,predicted_n,thermal"
} > "$CSV"

echo "== $BLOCKS blocks, seed $SEED =="
mapfile -t PLAN < <(python3 -c "
import random,sys
r=random.Random($SEED)
p=['baseline','fork']*($BLOCKS//2)
r.shuffle(p); print('\n'.join(p))")

i=0
for side in "${PLAN[@]}"; do
    i=$((i+1))
    if [ "$side" = baseline ]; then BIN=$BASELINE; else BIN=$FORK; fi
    read -r toks n therm <<< "$(run_block "$BIN" 99)"
    if [ "${toks:-ERR}" = ERR ]; then
        echo "  block $i ($side): FAILED ($n)"; echo "$i,$i,$side,99,ERR,0,$therm" >> "$CSV"; continue
    fi
    echo "  block $i ($side): $toks tok/s (n=$n, therm=$therm)"
    echo "$i,$i,$side,99,$toks,$n,$therm" >> "$CSV"
done

python3 - "$CSV" "$JSON" <<'PY'
import csv, statistics, sys, json, re
rows, meta = [], {}
with open(sys.argv[1]) as f:
    for line in f:
        if line.startswith("#"):
            k, _, v = line[1:].strip().partition("=")
            meta[k.strip()] = v
            continue
        rows.append(line)
r = list(csv.DictReader(rows))
def vals(side):
    return [float(x["tok_s"]) for x in r if x["side"] == side and x["tok_s"] != "ERR"]
b, f = vals("baseline"), vals("fork")
out = {"meta": meta, "n": {"baseline": len(b), "fork": len(f)}}
if len(b) > 1 and len(f) > 1:
    mb, mf = statistics.mean(b), statistics.mean(f)
    sb, sf = statistics.stdev(b), statistics.stdev(f)
    se = (sb**2/len(b) + sf**2/len(f)) ** 0.5
    delta = mf - mb
    out.update(baseline_mean=mb, fork_mean=mf, delta=delta, se=se,
               sigma=(delta/se if se else None))
    print(f"\n  baseline {mb:.3f} tok/s (sd {sb:.3f}, n={len(b)})")
    print(f"  fork     {mf:.3f} tok/s (sd {sf:.3f}, n={len(f)})")
    print(f"  delta    {delta:+.3f} tok/s, se {se:.3f}"
          + (f", {abs(delta)/se:.2f} sigma" if se else ""))
    if se and abs(delta) / se < 2:
        print("  VERDICT: parity (inside the noise floor)")
        out["verdict"] = "parity"
    else:
        print(f"  VERDICT: {'fork' if delta > 0 else 'baseline'} wins outside the noise floor")
        out["verdict"] = "fork" if delta > 0 else "baseline"
    if meta.get("selftest") == "yes" and out["verdict"] != "parity":
        print("  SELF-TEST FAILED: both sides were the same binary, so any winner")
        print("  here means this harness is measuring order, not silicon.")
        out["selftest"] = "failed"
        sys.exit(9)
    if meta.get("selftest") == "yes":
        print("  SELF-TEST PASSED: identical binaries reported parity, as they must.")
        out["selftest"] = "passed"
else:
    print("  not enough valid blocks to compare"); out["verdict"] = "insufficient"
json.dump(out, open(sys.argv[2], "w"), indent=2)
print(f"\n  wrote {sys.argv[1]} and {sys.argv[2]}")
PY
