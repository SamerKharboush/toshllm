#!/usr/bin/env bash
#
# utilcard.sh -- one card per run: what the machine was actually doing.
#
# Answers the question tok/s cannot: which cores ran, how busy each GPU was, how much
# VRAM each device held, and how much of the 64 GB the process had resident.
#
# Everything here reads without root. powermetrics is not used: it needs sudo, and
# sudo is not available unattended, so a card that depends on it would not run on this
# box. The AMD drivers publish their own counters through IORegistry, and those are
# what is read here.
#
# Usage:
#   ./tools/utilcard.sh <label> [pid]
#   ./tools/utilcard.sh <label> [pid] --phase pp     (sample during prompt processing)
#
set -uo pipefail

LABEL="${1:-card}"
PID="${2:-}"
PHASE="${3:-}"

ioreg_gpu_stats() {
    # Each AMD device publishes PerformanceStatisticsAccum and VRAM,totalMB. The keys carry
    # units in the name -- "GPU Activity(%)", "Temperature(C)" -- so the closing quote is
    # deliberately not required in the pattern.
    ioreg -r -c IOAccelerator 2>/dev/null | tr ',' '\n' \
      | grep -E '"(model|GPU Activity|Device Utilization|inUseVidMemoryBytes|vramFreeBytes|VRAM,totalMB|Core Clock|Memory Clock|Temperature|Total Power)' \
      | sed 's/^[[:space:]]*//' \
      | awk -F'"' '/"model"/{d++; printf "  gpu[%d] %s\n", d, $4} !/"model"/{printf "    %s\n", $0}'
}

# --- host -------------------------------------------------------------------
HOST_CPU=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
NCPU=$(sysctl -n hw.ncpu 2>/dev/null)
NPHYS=$(sysctl -n hw.physicalcpu 2>/dev/null)
MEMG=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024/1024/1024 ))

# --- cpu --------------------------------------------------------------------
# Per-core utilisation needs root, so what is recorded is the process's own share of
# the machine and the thread count it was given. The denominator is stated on the card
# because a CPU number without one is not interpretable.
if [ -n "$PID" ] && ps -p "$PID" >/dev/null 2>&1; then
    PCPU=$(ps -p "$PID" -o %cpu= 2>/dev/null | tr -d ' ')
    RSS=$(ps -p "$PID" -o rss= 2>/dev/null | tr -d ' ')
    THREADS=$(ps -M "$PID" 2>/dev/null | wc -l | tr -d ' ')
    RSSG=$(python3 -c "print(f'{${RSS:-0}/1048576:.2f}')" 2>/dev/null || echo 0)
else
    PCPU=0; RSSG=0; THREADS=0
fi
SYSLOAD=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | tr ',' ' ')

# --- host memory ------------------------------------------------------------
PAGE_FREE=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub("\\.","",$3); print $3}')
PAGE_SIZE=$(vm_stat 2>/dev/null | awk '/page size of/{print $8}')
SWAP=$(sysctl -n vm.swapusage 2>/dev/null | sed 's/.*used = \([0-9]*\).*/\1/')

# --- output -----------------------------------------------------------------
echo "card label=$LABEL phase=${PHASE:-idle} pid=${PID:-none}"
echo "  host cpu=\"$HOST_CPU\" logical=$NCPU physical=$NPHYS ram=${MEMG}GB"
echo "  process cpu_pct=$PCPU threads=$THREADS rss=${RSSG}GB"
echo "  system load_avg=[$SYSLOAD] pages_free=${PAGE_FREE:-?} page_size=${PAGE_SIZE:-?} swap_used_mb=${SWAP:-?}"
ioreg_gpu_stats | sed 's/^/  gpu /'
echo "  thermal: $(pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/{print $3}' | head -1)"
