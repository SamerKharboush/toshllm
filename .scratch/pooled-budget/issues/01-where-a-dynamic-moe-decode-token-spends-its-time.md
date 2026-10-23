# 01: Where a Dynamic MoE decode token spends its time

Type: task
Status: claimed
Blocked by:

## Question

On card 1 with the app's launch (35B Q6_K, `--dynamic-moe on`), what share of one decode
token is spent in each of these?
- the CPU executor computing non-resident experts;
- the GPU computing attention and resident experts;
- the GPU waiting on the host at the join (`MTLSharedEvent`);
- uploads and promotions.

Use `TOSH_DMOE_TIMELINE` and `TOSH_DMOE_STATS`. First confirm the timeline is on, by finding
its events in the dump.

The facts that matter:
- fused gate/up (hit rate 28%) and unfused (hit rate 40%) decode at the same 13.2 tok/s, so
  hit rate alone does not set the speed;
- a host job takes about 351 µs.

This needs both cards free: HITL only for stopping the user's own server.

## Method (2026-10-23)

The timeline records host jobs only for prefill, and the GPU's join wait sits inside its
compute command buffer, so the timeline cannot split a decode token. Instead, this is a
sensitivity run (scratchpad `exec_sens.sh`, delegated to OpenCode):
- slow the host executor (`TOSH_DMOE_THREADS` 12, 6, 3, 1) on card 1;
- regress token time against the measured host time per token (40 × host time per job).

Readings:
- a slope near 1 means the CPU experts are on the critical path;
- a slope near 0 means the GPU side is.

The existing stats already bound the host share: about 40 × 351 µs ≈ 14 ms of a 76 ms token.
