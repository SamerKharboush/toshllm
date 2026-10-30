# The dense mat-vec gate, and what nr0 = 8 does on a D700

Date: 2026-10-30. Task 0a from spec revision 3 (the GPU dense mat-vec kernel). The study and the
gate were delegated to OpenCode (`9router/Mocca#high`, routed by 9router to
`deepseek-v4.1-flash-free`, 21 minutes). The orchestrator re-ran every number below. None is
taken from the implementer's report.

## What landed

Patch 0055 (`patches/llama/moe/0055-test-backend-ops-dense-mat-vec-decode-perf-cases.patch`):
- adds 12 MUL_MAT perf cases to `tests/test-backend-ops.cpp` and nothing else;
- the cases are n = 1, at the dense shapes the models actually have:
  - Ornith-1.0-35B Q6_K, (k, rows): 2048 × {248320, 8192, 4096, 512, 32}, 512 × 2048 and
    4096 × 2048;
  - Qwen3-8B Q4_K_M, (k, rows): 4096 × {151936, 12288, 4096, 1024} and 12288 × 4096;
- they print GB/s, not FLOPS.

The engine is unchanged. The patch series applies 60 of 60.

## Device selection is proved, not assumed

`GGML_METAL_DEVICE_INDEX=1` pins the run to the second card. The test log cannot show that,
because both cards print the same name and the same free memory.

The proof is `ioreg` per-accelerator `Device Utilization %`, sampled while one index runs the
head shape in a loop:
- a load on index 0 lights IOAccelerator entry 3 only (89–98 %);
- a load on index 1 lights entry 1 (88 %).

The implementer's own "proof" (the slot name) does not distinguish the cards.

## The gate, and its noise floor

Method:
- engine d81235049 plus 0001–0055, AVX1; test-backend-ops sha256 3475b573…;
- card 1, `test-backend-ops perf -o MUL_MAT -b MTL0`;
- N = 5 separate processes per cell. Each process averages at least 1 s of iterations. There are
  no warmups to discard, because the tool does its own;
- each cell's pipeline name was checked with `TOSH_SWEEP_DEBUG=1`, and every run compiled the
  kernel it asked for;
- the variants are forced with the existing hook: `TOSH_SWEEP_TYPE`, `TOSH_SWEEP_NR0` and, for
  `L16r8`, `TOSH_SWEEP_LANES=16`.

The cells, GB/s, mean (sd):

| type | k × rows | shipped (q6_K `r4_w64`, q4_K `L16r4_w64`) | `r8_w64` | q4_K `r4_w64` | q4_K `L16r8_w64` |
|---|---|---|---|---|---|
| q6_K | 2048 × 248320 | 42.85 (0.00) | 53.12 (0.01) | | |
| q6_K | 2048 × 8192 | 41.17 (0.01) | 50.07 (0.01) | | |
| q6_K | 4096 × 2048 | 39.82 (0.05) | 46.78 (0.10) | | |
| q6_K | 2048 × 4096 | 39.68 (0.01) | 43.44 (0.10) | | |
| q6_K | 2048 × 512 | 15.25 (0.16) | 11.86 (0.08) | | |
| q6_K | 512 × 2048 | 13.82 (0.09) | 14.64 (0.36) | | |
| q6_K | 2048 × 32 | 1.19 (0.01) | 0.86 (0.01) | | |
| q4_K | 4096 × 151936 | 39.43 (0.01) | 66.18 (0.03) | 39.74 (0.03) | 66.56 (0.04) |
| q4_K | 4096 × 12288 | 38.35 (0.01) | 52.85 (0.01) | 38.98 (0.01) | 57.50 (0.13) |
| q4_K | 12288 × 4096 | 38.27 (0.01) | 53.56 (0.03) | 36.59 (0.02) | 53.64 (0.60) |
| q4_K | 4096 × 4096 | 36.55 (0.01) | 50.39 (0.02) | 37.51 (0.01) | 45.79 (0.01) |
| q4_K | 4096 × 1024 | 28.45 (0.12) | 26.83 (0.08) | 28.14 (0.19) | 23.19 (0.08) |

Noise floor:
- on the large shapes, within one session, the sd is at most 0.13 GB/s, with one exception: 0.60
  for q4_K `L16r8` at 12288 × 4096;
- the small shapes do not repeat across sessions. The implementer's session measured
  2048 × 32 at 1.55, 2048 × 512 at 19.20, 512 × 2048 at 16.74 and q4_K 4096 × 1024 at 31.80,
  each against the values above with an in-session sd of at most 0.19. Those are two
  observations each, not one quantity (rule 3);
- below about 4096 rows the gate reads only the direction of a change, within one session.

Reading:
- `nr0 = 8` raises the large shapes of both types;
- it lowers the shapes with few rows: q6_K at 512 and at 32 rows, and q4_K at 1024 rows;
- for q4_K, most of the gain is the row count, not the kernel family. Plain `r4` is within about
  1 GB/s of the shipped `L16r4`, and both `r8` and `L16r8` move the head to about 66;
- `L16r8` is ahead at 12288 rows and behind at 4096 and at 1024 rows;
- one fixed `nr0` is wrong for both ends, so the choice has to depend on the row count.

## Correctness

`test-backend-ops -o MUL_MAT -b MTL0`, card 1, run once per variant. The forced kernel appeared
in each run's pipeline log:

| variant | q6_K OK / FAIL | q4_K OK / FAIL |
|---|---|---|
| shipped | 62 / 0 | 120 / 0 |
| q6_K `r8_w64` | 62 / 0 | 120 / 0 |
| q4_K `r8_w64` | 62 / 0 | 120 / 0 |
| q4_K `L16r8_w64` | 62 / 0 | 120 / 0 |

Only 3 of the q6_K eval cases are at n = 1. The end-to-end text below carries most of the
q6_K evidence.

## End to end, on one card

Method:
- the same engine; card 1 (`GGML_METAL_DEVICE_INDEX=1`), `-ngl 99`;
- llama-bench sha256 b55bfecb…, `-p 0 -n 128 -r 5 -fa 1`, 5 repetitions after its own warmup.
  The cells were alternated with a 10 s gap;
- text: llama-server with `-c 4096 -t 8 -fa auto --parallel 1 --cache-ram 0`, `/completion`,
  greedy, 256 tokens, `cache_prompt false`, the BST prompt and the lighthouse prompt. One request
  per prompt per cell, N = 1, so these are text checks, not rates.

| model | cell | llama-bench tg128 t/s | server t/s (BST, lighthouse) | text equals shipped |
|---|---|---|---|---|
| Qwen3-8B Q4_K_M | shipped | 8.26 (0.00), and 8.26 (0.00) on the second pass | 8.24, 8.24 | — |
| Qwen3-8B Q4_K_M | q4_K `r8_w64` | 9.99 (0.00) | 9.96, 9.96 | yes, both prompts |
| Qwen3-8B Q4_K_M | q4_K `L16r8_w64` | 9.49 (0.00) | 9.46, 9.46 | yes, both prompts |
| Qwen3-4B Q6_K | shipped | 12.08 (0.00) twice | 12.03, 12.03 | — |
| Qwen3-4B Q6_K | q6_K `r8_w64` | 13.78, 13.77 (0.00) | 13.72, 13.72 | yes, both prompts |

The shipped 8B figure agrees with `gpu-decode-vs-the-shipped-build-2026-10-20.md` (8.159).

Not run here:
- the 35B. It runs on the host under the 67 placement rule, so these kernels do not touch its
  decode;
- both hooks together. The sweep hook takes one type per process, so the 8B's q6_K tensors and
  the 4B's other types stayed on the shipped kernels in these cells;
- card 0 and the two-card modes.

## Next: task 0b

Make `nr0` depend on the row count for q6_K and q4_K at n = 1 on wave64, in
`ggml-metal-device.cpp`:
- use `r8_w64` on the large shapes;
- keep `r4` on the few-row shapes, where it measured lower above.

The gate for 0b is this file's tables:
- the per-shape cells re-run in one session;
- eval 0 FAIL;
- identical text on both models;
- llama-bench decode against the shipped figures above, with the cells alternated.

The implementer's other ranked items (aligned-dword reads, staging x in threadgroup memory,
the epilogue) wait until 0b has landed.
