# 51: third-party feasibility and the Colibri oracle

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 6)

## Problem

Three projects were proposed as ways to use more of this hardware. The verdicts exist in
conversation and nowhere in the repo, and two of the three gates settle in a single grep.

## Change

Commit the receipts at file:line for all three: Strata's Apple-Silicon and macOS-version gate,
AirLLM's macOS device selection, Colibri's macOS build path and minimum RAM. Then benchmark
Colibri CPU-only on this machine against Qwen3.6-35B-A3B using the same protocol as the fork
A/B, and run our own build on the same model at -ngl 99 and -ngl 0. Colibri is an oracle, not a
dependency: if it wins, the gap is architectural and worth understanding; if it loses, the
question closes.

## Evidence

The receipts file and the benchmark table with a verdict of colibri faster (naming the gap),
parity, or colibri slower. No porting decision without that table.
