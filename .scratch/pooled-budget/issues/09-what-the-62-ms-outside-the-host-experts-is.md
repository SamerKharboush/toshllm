# 09: What the 62 ms outside the host experts is

Type: task
Status: resolved
Blocked by: 01

## Question

On card 1 with the app's launch, a Dynamic MoE decode token takes about 78 ms. About 16 ms
of that is the CPU expert executor, on the critical path. The fit puts the rest at 62 ms.

How do those 62 ms split, measured, not modelled?
- GPU compute of attention and the resident experts;
- the GPU's wait at the join;
- the CPU's graph build and encode;
- uploads and promotions.

The timeline cannot split a decode token today. Answering this probably needs per-layer GPU
timestamps or a command-buffer split at the join, which is engine instrumentation.

## Answer

Of a 76.0 ms decode token, the GPU has command buffers running for 73.4 ms. The CPU expert
jobs (14.4 ms) sit inside that span as GPU waits, which are inferred from ticket 01's slope.
That leaves about 59 ms of GPU kernel work. Host encode takes 6.6 ms and mostly overlaps the
GPU; only 2.6 ms has no GPU work. Measured with patch 0048's timeline on card 1, 1182
tokens.

Evidence: `../../firellama-maxperf/evidence/a-dynamic-moe-decode-token-split-2026-10-25.md`.
