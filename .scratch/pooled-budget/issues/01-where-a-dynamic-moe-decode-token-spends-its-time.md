# 01: Where a Dynamic MoE decode token spends its time

Type: task
Status: open
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
