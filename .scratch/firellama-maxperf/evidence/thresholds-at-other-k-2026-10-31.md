# Mat-vec row thresholds at other k (patch metal/0074)

## The question

0072 set two decode (n = 1) mat-vec thresholds on 64-lane cards from sweeps at one k each: q6_K
takes 8 rows per threadgroup from 1792 rows (measured at k 2048), q4_K's large path takes the
16-lane kernel from 12288 rows (measured at k 4096). Do the crossovers move with k?

## Method

- engine: llama.cpp `d81235049` plus the 83-patch series, dev tree `build-static`;
  `GGML_METAL_DEVICE_INDEX=1` (card 1, FirePro D700, simd width 64), macOS 15.8;
- per shape: `test-backend-ops perf -o MUL_MAT -b MTL0 -p 'type_a=<t>,type_b=f32,m=<rows>,n=1,k=<k>'`,
  GB/s as printed; the pipeline forced with `TOSH_SWEEP_TYPE/NR0/LANES` and confirmed on every run
  with `TOSH_SWEEP_DEBUG=1` (all runs matched);
- N = 5 separate processes per cell, the two cells of a shape alternated within a round;
- cells: q6_K A = r4, B = r8 at k {1024, 4096, 8192, 12288} x rows {1024 ... 2048}
  (4096/1024 and 4096/2048 were not in the sweep); q4_K A = r8, B = L16r8 at k {2560, 8192,
  14336} x rows {6144 ... 14336};
- sweep run by the delegate; the table below is recomputed by the orchestrator from the raw
  `sweep1.csv` and `sweep2.csv`.

## Results (GB/s, mean and sd over 5)

q6_K, r4 vs r8:

| k | rows | r4 | r8 |
|---|---|---|---|
| 1024 | 1024 | 22.88 (0.21) | 17.43 (0.03) |
| 1024 | 1280 | 25.77 (0.10) | 21.47 (0.05) |
| 1024 | 1536 | 28.46 (0.05) | 25.11 (0.04) |
| 1024 | 1792 | 24.70 (0.05) | 28.87 (0.07) |
| 1024 | 2048 | 26.91 (0.08) | 32.67 (0.08) |
| 4096 | 1280 | 37.79 (0.01) | 37.09 (0.02) |
| 4096 | 1536 | 39.49 (0.02) | 42.31 (0.00) |
| 4096 | 1792 | 36.54 (0.01) | 45.19 (0.02) |
| 8192 | 1024 | 39.91 (0.01) | 40.17 (0.01) |
| 8192 | 1280 | 39.64 (0.01) | 41.18 (0.02) |
| 8192 | 1536 | 41.07 (0.01) | 45.01 (0.01) |
| 8192 | 1792 | 38.42 (0.01) | 47.68 (0.01) |
| 12288 | 1024 | 40.70 (0.01) | 42.56 (0.01) |
| 12288 | 1280 | 40.29 (0.01) | 42.59 (0.01) |
| 12288 | 1536 | 41.55 (0.00) | 46.03 (0.00) |
| 12288 | 1792 | 38.85 (0.01) | 48.61 (0.01) |
| 12288 | 2048 | 41.71 (0.00) | 50.58 (0.01) |

The q6_K crossover moves down as k grows: r8 ahead from 1792 at k 1024, 1536 at k 4096, 1280 at
k 8192 (at 1024 rows the two are 0.26 GB/s apart, kept on r4), 1024 at k 12288.

q4_K, r8 vs L16r8:

| k | rows | r8 | L16r8 |
|---|---|---|---|
| 2560 | 6144 | 42.84 (0.01) | 43.06 (0.01) |
| 2560 | 8192 | 43.66 (0.01) | 44.07 (0.01) |
| 2560 | 10240 | 44.23 (0.01) | 44.68 (0.00) |
| 2560 | 12288 | 44.74 (0.00) | 45.14 (0.00) |
| 2560 | 14336 | 45.27 (0.01) | 45.49 (0.00) |
| 8192 | 6144 | 53.07 (0.01) | 55.28 (0.34) |
| 8192 | 8192 | 53.46 (0.22) | 58.86 (0.01) |
| 8192 | 10240 | 53.57 (0.16) | 60.29 (0.33) |
| 8192 | 12288 | 54.08 (0.15) | 61.49 (0.35) |
| 8192 | 14336 | 62.62 (0.39) | 62.14 (0.43) |
| 14336 | 6144 | 54.91 (0.58) | 58.90 (0.23) |
| 14336 | 8192 | 63.06 (0.27) | 61.30 (0.31) |
| 14336 | 10240 | 64.30 (0.31) | 62.24 (0.33) |
| 14336 | 12288 | 64.93 (0.10) | 63.52 (0.11) |
| 14336 | 14336 | 64.89 (0.16) | 64.05 (0.05) |

At k 2560 the 16-lane kernel is ahead at every row count measured. At k 8192 and 14336 the
winner flips with rows in a pattern that is not monotone (8192: L16 ahead 6144-12288, tied at
14336; 14336: L16 ahead only at 6144), so no rule was fitted there.

## The change

- q6_K: r8 from 1792 rows, or from 1536 at k >= 4096, 1280 at k >= 8192, 1024 at k >= 12288.
- q4_K large path: L16r8 from 12288 rows as before, and also from 6144 rows at k <= 2560.
  Elsewhere unchanged.
- Rejected: a delegate-proposed q4_K rule
  `ne00 <= 2560 || (ne00 > 8192 ? ne01 < 8192 : ne01 >= 12288)`. It picks r8 at k 8192 for
  6144-10240 rows, where the table has L16r8 ahead, and it would move the 14B ffn_down
  (k 17408, 5120 rows, below the rows swept) to L16r8, where beta.4 measured r8 53.60 vs L16r8
  49.30 GB/s.
- `TOSH_MV_ROWS8_DISABLE=1` still returns both types to the 4-row kernels (checked: L16r4 at
  q4_K 9728@2560, r4 at q6_K 1536@4096).
- Both rules live inside the `simd_width == 64` blocks; on 32-lane devices nothing changes.
- New eval cases one past each new boundary (q6_K 1539@4096, 1283@8192, 1027@12288; q4_K
  6147@2560); new perf cases for the sweep shapes and q4_K 9728@2560.

Which real shapes move (gguf_dump over every model in /Users/sam/models, `shapes2.txt`): only
q4_K at k 2560 with 9728 rows (Qwen3-4B-Q4_K_M ffn_gate/up) and 10240 rows (Nemotron-3.5-Bolt-E4B
Q4_K_M ffn_gate/up). No q6_K tensor in those models falls in a moved band, so the q6_K change has
no end-to-end measurement here; it rests on the table above.

## Proof the rule takes effect on a model

`TOSH_SWEEP_DEBUG=1 llama-bench -m Qwen3-4B-Q4_K_M -p 0 -n 4 -r 1 -fa 1`, pipeline counts:

| pipeline | old rule | new rule |
|---|---|---|
| q4_K r8_w64 | 720 | 360 |
| q4_K L16r8_w64 | 0 | 360 |
| q4_K r4 (small path) | 180 | 180 |
| q6_K r8_w64 | 95 | 95 |

The old-rule binary is the same tree with only the q4_K line set back to `ne01 >= 12288`.

## End to end

Method: `llama-bench -p 0 -n 128 -r 5 -fa 1`, `GGML_METAL_DEVICE_INDEX=1`, dev tree build, -c
default, models fully on card 1; old and new binaries alternated old new old new per model, two
rounds, 4 processes per cell, llama-bench's own warmup discarded. Each figure is one process's
mean of 5 (sd in brackets).

| model | old rule tg128 tok/s | new rule tg128 tok/s |
|---|---|---|
| Qwen3-4B Q4_K_M | 16.145 (0.007), 16.160 (0.007), 16.155 (0.003), 16.160 (0.004) | 16.598 (0.002), 16.608 (0.008), 16.608 (0.002), 16.601 (0.007) |
| Nemotron-3.5-Bolt-E4B Q4_K_M | 13.012 (0.008), 13.014 (0.003), 13.011 (0.005), 13.012 (0.007) | 13.522 (0.010), 13.525 (0.003), 13.526 (0.007), 13.531 (0.007) |

Text: llama-server greedy /completion, 256 tokens, the BST prompt (`req.py`), `-ngl 99 -c 4096
-fa on`: the old and new texts are byte-identical for both models (1135 and 1061 bytes).

Gate: `test-backend-ops -o MUL_MAT -b MTL0` on card 1: 1760/1760 passed. Series: 84 of 84 apply
to `d81235049`.

## 32-lane hardware

Not run: no 32-lane GPU is attached, and this Mac cannot take one (macOS dropped Thunderbolt 1/2
eGPU support in 10.13.4). The rules changed here sit inside `simd_width == 64` checks; the device
probe logs `probed SIMD-group width = N` at load. On a device that reports 32, the test is that
nothing here applies: the pipelines printed with `TOSH_SWEEP_DEBUG=1` carry no `_w64` suffix, and
`test-backend-ops -o MUL_MAT` passes. Apple Silicon is the practical such device; the gates for
it are in `docs/agents/apple-silicon-handoff.md`. Which AMD GPUs report 32 under Metal was not
established from a primary source and is not claimed.

## Other engines

The delegate was asked to survey other engines and prototype at most two ideas. It prototyped
none, and its survey had factual errors (wrong author and missing Metal support for mistral.rs,
MLC-LLM described as MLIR-based), so it is not kept as evidence. The question stays open.

Raw: `thresholds-k-2026-10-31/` (`sweep1/2.sh`, `sweep1/2.csv`, `t1-stats.txt`, `shapes2.py`,
`shapes2.txt`, `old-debug.log`, `run.sh`, `bench.log`, `req.py`, the four texts).
