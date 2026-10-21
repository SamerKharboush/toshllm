# 59: the tiering preset

Status: blocked
Type: task
Spec: ../spec.md (Revision 8)

## Problem

"Uses the 64 GB" is untested, because every model run so far fits in one card. The test needs
a model that overflows 12 GB of VRAM, with experts in host RAM and attention on the GPUs.

## Change

A 30-35B MoE Q4, three placements: `--n-cpu-moe 0` (expected to fail or spill -- that failure
is the baseline), `--n-cpu-moe 99` (experts in RAM, attention on GPU), and the same with the
expert mmap dropped to force real residency instead of page-cache illusion.

## Blocked on

Two things, both found by inspection rather than assumed:

1. **`--no-mmap` does not exist at this pin** (0 mentions in `--help`). The engine accepts
   `--n-cpu-moe`, `-ot`, `-md`, `--draft-max` and `--split-mode`. The third placement has to be
   re-specified against a flag the engine actually accepts, or dropped.
2. **No 30-35B MoE Q4 on this machine.** The largest local model is
   `Ternary-Bonsai-2-27B-PQ2_0`; the rest are dense and fit in one card. A model that overflows
   12 GB has to be obtained first.

## Answer

