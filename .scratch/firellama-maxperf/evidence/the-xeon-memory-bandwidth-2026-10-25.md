# The Xeon's sustained memory bandwidth

Date: 2026-10-25. Spec item 3a of `.scratch/pooled-budget/spec.md`.

## Method

- Benchmark: `stream_avx1.c`, next to this file. Written by OpenCode, checked here. It is a
  STREAM-style set of kernels (Copy, Scale, Add, Triad) plus a read-only sum, the closest
  match to reading weights.
- Arrays: 128 Mi doubles, 1 GiB each. pthreads with contiguous chunks; each thread
  first-touches its own chunk.
- Runs: 10 per kernel per thread count, the first discarded.
- Build: `cc -O2 -mavx -mno-avx2 -mno-fma -mf16c -pthread`, 0 AVX2/FMA mnemonics.
- Machine: Xeon E5-2697 v2 with 4 × DDR3-1866 ECC; 59.7 GB/s theoretical.
- Repeats: run 3 times back to back by OpenCode, and once more (3 internal runs) by the
  orchestrator. No llama-server was running.

## Rows (12 threads, GB/s, mean of 3 runs ± sd)

| kernel | OpenCode's run | orchestrator's run |
|---|---|---|
| Copy | 29.700 ± 0.230 | 29.5 (one run) |
| Add | 34.559 ± 0.324 | 34.4 (one run) |
| Triad | 34.211 ± 0.793 | |
| read-only sum | 50.925 ± 0.281 | 51.582 ± 0.447 |

24 threads adds under 1 GB/s on any kernel. One thread reaches about 11.5–12 GB/s.

## Reading

- The CPU experts move an estimated 570 MB per token, about 221 experts at 2.58 MB of Q6_K
  each, from ticket 01's counts. They do it in 15.9 ms, about 35.8 GB/s.
- The read-only ceiling is 51.6 GB/s. At that rate the same bytes would take about 11.0 ms.
- **So a perfect AVX1 expert kernel could save at most about 5 ms per token** on the 35B,
  if the experts are bandwidth-bound. Both the byte count and the bound are estimates,
  built from measured job counts, the quant size and this benchmark.
- Lever (a) is real but bounded, and it is smaller than the GPU's dense mat-vec (39.6 ms per
  token, ticket 10).
