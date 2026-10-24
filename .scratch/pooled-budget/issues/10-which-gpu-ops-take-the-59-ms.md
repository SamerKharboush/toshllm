# 10: Which GPU ops take the 59 ms

Type: task
Status: claimed
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
