# 70: Dynamic MoE never ran mixed execution on a 64-lane card

Status: ready-for-human
Type: bug
Spec: ../spec.md (Revision 8)

## Problem

Dynamic MoE is this engine's version of Strata's design: hot experts in a VRAM arena, every expert in
RAM, and the host computes the misses while the card computes the hits (`tosh-moe/tosh-dmoe.h:1-4`). On
the D700 it never ran. The planner promised a 1.3 GiB arena, the runtime granted 727 MiB, under its 788
MiB minimum, and logged `mixed execution stays off`. The plan line the user sees did not change.

Cause: on a 64-lane card the loader fuses each layer's expert gate and up into one tensor
(`src/llama-model.cpp:3720-3726`), and the runtime sizes the three prefill slots from it
(`src/llama-tosh-dmoe.cpp:1781`). The planner sized them from the GGUF's separate tensors
(`common/tosh-plan.cpp:195`), 630 MiB short. Every GCN and Vega card is affected; RDNA is not.

## Change (done, not committed)

`patches/llama/moe/0046-the-plan-counts-a-fused-gate-and-up-as-one-prefill-slot.patch`: the planner applies
the loader's fusion condition. Series 51 of 51 clean. Engine `21e642e5...` built with `TOSH_AVX1=1`.

## Evidence

`../evidence/dynamic-moe-on-the-d700-smoke-2026-10-21.md`. On the 0046 engine, the 35B Q6_K with
`--dynamic-moe on` decodes 13.2231 tok/s (sd 0.1428, N=6), against 10.8932 (sd 0.3934, N=6) at `-ngl 0`
in the same alternating session. Ranges do not overlap. Output is coherent but not deterministic between
greedy requests.

Two inert controls were caught on the way, and are recorded there: `TOSH_DMOE_RESERVE_MIB` (the planner
overwrites it) and `GGML_METAL_DEVICES=2` (Dynamic MoE takes the first GPU only, `common/tosh-plan.cpp:352`).

## Open, for the owner

- Whether the placement rule (ticket 67) should send a MoE model that does not fit in VRAM to Dynamic MoE
  instead of `-ngl 0`. Trade: about 2.3 tok/s more decode against an answer that is not repeatable.
- Before that: the app's own launch (`-c 16384`, `--load-mode none`, `--cache-ram 2048`), a long-prompt
  prefill row, and at least one other MoE model.
- Next engine lever: the host executor sets the pace (~355 us per job, gate/up ~235 us). A larger arena
  (hit rate 28% -> 40%) changed nothing measurable.
