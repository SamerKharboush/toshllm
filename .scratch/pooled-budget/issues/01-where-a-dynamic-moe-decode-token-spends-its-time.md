# 01: Where a Dynamic MoE decode token spends its time

Type: task
Status: resolved
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

## Answer

**The host experts are fully on the critical path. They take about 16 ms of a 78 ms token; the
other 62 ms is outside the CPU executor.**

Method:
- Engine: fork engine `d81235049` + 52 patches (AVX1).
- Model and launch: Ornith-1.0-35B Q6_K, the app's launch (`-c 16384 -t 12 -fa auto
  --load-mode none --cache-ram 2048 --cache-reuse 256 --parallel 1 --dynamic-moe on`) on
  card 1, with `TOSH_DMOE_STATS=1`.
- Cells: `TOSH_DMOE_THREADS` = 12, 6, 3 and 1, two rounds, the second in reverse order.
- Per server: 1 warmup + 3 measured 200-token short decodes, which are the rows used here.
- The thread count took effect in every server (`dmoe_init … N host threads`). All 8 planned
  `PLAN_FULL_HOST_DMOE`, and 0 of 56 answers are degenerate.
- Script `exec_sens.sh`, written and run by OpenCode; the analysis was done by the
  orchestrator.

| threads | short decode (tok/s) | token ms | host time per job (µs) | host ms per token (40 × job) |
|---|---|---|---|---|
| 12 | 12.8689 / 12.8571 | 77.71 / 77.78 | 395.6 / 398.9 | 15.82 / 15.96 |
| 6 | 12.3486 / 12.2832 | 80.98 / 81.41 | 481.2 / 497.5 | 19.25 / 19.90 |
| 3 | 10.4032 / 10.4610 | 96.12 / 95.59 | 874.6 / 859.8 | 34.98 / 34.39 |
| 1 | 6.7027 / 6.7511 | 149.19 / 148.12 | 2248.7 / 2181.8 | 89.95 / 87.27 |

- **Fit** (OLS, token ms against host ms per token, all 8 servers): slope **0.9760**,
  intercept 62.125 ms.
  - Residuals: +0.14, +0.08, +0.07, −0.14, −0.15, −0.10, −0.72, +0.82 ms.
  - Noise floor, the per-cell sd of token ms across the two rounds: 0.050 (x12), 0.305 (x6),
    0.376 (x3), 0.756 (x1). The largest ratio of residual to its cell's sd is 2.8, at x12.
  - Without x1: slope 0.9654, intercept 62.358 ms, residuals at most 0.16 ms.
- **Reading:** every ms of CPU expert time adds about 1 ms to the token. Nothing overlaps
  it.
- **Bound on the CPU levers:** at the default of 12 threads, the host experts are 15.8–16.0
  ms of a 77.7 ms token. A faster AVX1 kernel, or full overlap at the join, can remove at
  most those 16 ms. That bounds decode at about 1000 / 62 ≈ 16.1 tok/s on this launch. The
  62 ms is the fit's intercept, an extrapolation, not a measurement of a token without host
  work.
- **The rest:** the 62 ms outside the executor is the larger share. Its makeup is not known:
  GPU attention and resident experts, the join, uploads and promotions, and encode.
