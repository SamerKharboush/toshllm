# 10: Which GPU ops take the 59 ms

Type: task
Status: resolved
Blocked by: 09

## Question

On card 1, with the app's launch and Dynamic MoE, a 35B decode token has about 59 ms of GPU
work. How much of it does each op kind take?
- matmul-vec by quant type;
- the delta-net / SSM ops;
- attention;
- the Dynamic MoE join;
- copies.

Metal gives command-buffer timestamps only. The measurement therefore needs a diagnostic
mode that puts each op, or each op kind, in its own command buffer and records its GPU span.
That buffer per op is extra overhead, so publish its sum next to the normal token time. The
join op's own buffer will then hold the wait on the host directly.

The answer decides whether GCN kernel work is the next lever. It applies to every model on
the cards, not only MoE: the dense 8B also decodes at only 9.0 tok/s across both cards (R25).

## 2026-10-25: first run, not a result

Patch 0049 (`TOSH_OPGPU=1`) is correct on the dense 0.6B: the greedy text is identical in
both modes. On the 35B with Dynamic MoE it **answers garbage** after the first token, for
example "Here1**gal (, s( , 1 1 …", in 8 of 8 per-op answers across two servers. So its
per-op table for the 35B is the timing of a wrong computation, and none of it is published.
The table was: q6_K matmul 39.6 ms per token, MUL_MAT_ID q6_K 12.9, the join 5.7, a total of
78.2 ms per graph, against a normal token of about 76 ms. The per-op mode decoded at
10.8–11.2 tok/s against 13.1 for the normal mode.

`TOSH_DMOE_PROMO_STOP=3000` did not stop promotions (11.8 per graph), so a race with the
promotion uploads is untested. The prime suspect is the per-op path's own node-skip filter
after fused ops. Debugging is delegated to OpenCode; 0049 must be fixed before its MoE
numbers count.

## Answer

Per 35B decode token on card 1, from the corrected per-op mode (47 graphs; the text is
identical to the normal mode):

| op | ms per token |
|---|---|
| dense Q6_K mat-vec (311 ops; non-expert weights + output head) | 39.553 |
| the Dynamic MoE join (the GPU waiting on the CPU experts) | 9.898 |
| resident-expert Q6_K MUL_MAT_ID | 9.341 |
| everything else, the largest RMS_NORM at 3.47 | about 19 |
| **total** | **77.957** |

The dense mat-vec reads 1.573 GB per token, an effective 39.8 GB/s; the D700's rated
bandwidth is 264 GB/s.

Evidence: `../../firellama-maxperf/evidence/which-gpu-ops-a-35b-decode-token-spends-2026-10-25.md`.
