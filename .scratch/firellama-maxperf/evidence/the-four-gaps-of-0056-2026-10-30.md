# The four gaps of 0056: thresholds, tensor split, 32 lanes, the DFlash drafter (2026-10-30)

Patch 0071 (formerly 0056) shipped in 0.87.31-beta.3 with four items marked not covered. This file
covers them. The OpenCode/Mocca run for items 1-3 (brief 0c) exited after 2.5 h with no report and
no source change; Mocca then did not answer a probe within 60 s, so every number here was measured
by the orchestrator. Raw rows are in `rows-2026-10-30/` (files prefixed `0c-` and `0d-`).

Engine for every row: llama.cpp d81235049 with the 82-patch series (through
`metal/0072-metal-mat-vec-row-thresholds-from-the-gap-sweep.patch`), build-static, AVX1 host.
Card: FirePro D700 card 1 (`GGML_METAL_DEVICE_INDEX=1`) unless a row says both.

## 1. Threshold gaps

Method: `test-backend-ops perf -o MUL_MAT -b MTL0`, n = 1, one process per cell per round, each
process averages >= 1 s per case; 5 rounds, cells alternated inside each round (`gap0c.sh`). Forced
cells use `TOSH_SWEEP_TYPE` / `TOSH_SWEEP_NR0` / `TOSH_SWEEP_LANES`; every forced run printed the
pipeline it asked for (`0c-gap-pipelines.txt`). GB/s mean +- sd, N = 5. Shapes are k x rows.
"real" names the model that has the shape at decode on one card.

q6_K (forced r4 vs r8, both `_w64`):

| k x rows | real | r4 | r8 | rule before | rule after |
|---|---|---|---|---|---|
| 2048 x 768 | | 23.71 +- 0.16 | 18.94 +- 0.08 | r4 | r4 |
| 2048 x 1024 | | 29.76 +- 0.08 | 24.50 +- 0.11 | r4 | r4 |
| 2560 x 1024 | 4B attn_k/v | 30.67 +- 0.19 | 25.70 +- 0.04 | r4 | r4 |
| 4096 x 1024 | 8B attn_v | 36.34 +- 0.08 | 33.02 +- 0.05 | r4 | r4 |
| 5120 x 1024 | 14B attn_v | 36.97 +- 0.63 | 35.22 +- 0.11 | r4 | r4 |
| 2048 x 1280 | | 30.90 +- 0.14 | 29.35 +- 0.08 | r4 | r4 |
| 2048 x 1536 | | 34.08 +- 0.06 | 34.01 +- 0.08 | r4 | r4 |
| 2048 x 1792 | | 27.90 +- 0.04 | 38.39 +- 0.09 | r4 | **r8** |
| 4096 x 2048 | | 39.80 +- 0.02 | 46.83 +- 0.10 | r8 | r8 |
| 4096 x 2560 | 4B attn_output | 40.57 +- 0.01 | 46.94 +- 0.10 | r8 | r8 |
| 9728 x 2560 | 4B ffn_down | 41.51 +- 0.01 | 48.56 +- 0.01 | r8 | r8 |
| 2560 x 9728 | 4B ffn_gate/up | 40.04 +- 0.00 | 47.62 +- 0.02 | r8 | r8 |
| 12288 x 4096 | 8B ffn_down | 42.39 +- 0.01 | 51.95 +- 0.01 | r8 | r8 |
| 17408 x 5120 | 14B ffn_down | 42.45 +- 0.00 | 52.98 +- 0.01 | r8 | r8 |

q4_K large-matrix path (forced plain r8 vs L16r8; forced plain r4 is in the rows file and loses
everywhere, 36.5-39.0 GB/s):

| k x rows | real | r8 | L16r8 | rule before | rule after |
|---|---|---|---|---|---|
| 4096 x 4096 | 8B attn_q/output | 50.39 +- 0.02 | 45.45 +- 0.32 | r8 | r8 |
| 12288 x 4096 | 8B ffn_down | 53.56 +- 0.01 | 53.76 +- 0.39 | r8 | r8 |
| 4096 x 5120 | | 50.98 +- 0.01 | 45.19 +- 0.04 | r8 | r8 |
| 5120 x 5120 | 14B attn_q/output | 49.31 +- 0.01 | 46.90 +- 0.02 | r8 | r8 |
| 17408 x 5120 | 14B ffn_down | 53.60 +- 0.17 | 49.30 +- 0.15 | r8 | r8 |
| 4096 x 6144 | | 51.39 +- 0.01 | 46.95 +- 0.02 | r8 | r8 |
| 4096 x 7168 | | 51.58 +- 0.01 | 47.45 +- 0.02 | r8 | r8 |
| 4096 x 8192 | | 51.80 +- 0.01 | 47.95 +- 0.01 | L16r8 | **r8** |
| 4096 x 10240 | | 52.36 +- 0.00 | 48.63 +- 0.00 | L16r8 | **r8** |
| 4096 x 12288 | 8B ffn_gate/up | 52.83 +- 0.01 | 57.47 +- 0.03 | L16r8 | L16r8 |
| 5120 x 17408 | 14B ffn_gate/up | 52.73 +- 0.18 | 60.89 +- 0.02 | L16r8 | L16r8 |

Decision (patch 0072): q6_K takes r8 from 1792 rows (was 2048); q4_K takes L16r8 from 12288 rows
(was 8192). Both are the smallest measured row count where the wider kernel wins by more than 3 sd
of both cells; 1536 rows q6_K is a tie (0.07 apart, sd 0.06-0.08) and stays r4. No real decode
shape of the three models lies in either moved range, so their single-card and layer-split
pipelines are unchanged. The shapes that do move are ones these three models only reach through
tensor split (below) or that other models have (a 3072 -> 8192 FFN, for instance). Crossovers were
measured at k = 2048 (q6_K) and k = 4096 (q4_K) only; at 1024 rows the q6_K r8 deficit shrinks as
k grows (16% at k 2560, 5% at k 5120), so a larger-k model may want a lower q6_K threshold. That is
not measured.

The moved rule against the control, same method, both cells alternated (`0c-moved-*`):

| k x rows | TOSH_MV_ROWS8_DISABLE=1 | rule after 0072 | pipeline after |
|---|---|---|---|
| 2048 x 1536 | 32.78 +- 0.15 | 32.92 +- 0.15 | q6_K r4_w64 |
| 2048 x 1792 | 28.08 +- 0.06 | 38.77 +- 0.14 | q6_K r8_w64 |
| 4096 x 8192 | 37.82 +- 0.01 | 51.80 +- 0.01 | q4_K r8_w64 |
| 4096 x 10240 | 38.13 +- 0.01 | 52.36 +- 0.01 | q4_K r8_w64 |
| 4096 x 12288 | 38.36 +- 0.01 | 57.44 +- 0.23 | q4_K L16r8_w64 |

Correctness: `test-backend-ops -o MUL_MAT -b MTL0` and `-o MUL_MAT_ID`, card 1: 0 FAIL. New eval
cases at the new boundaries (q6_K 1795 x 2048, q4_K 12291 x 4096) run `r8_w64` and `L16r8_w64`
(checked with `TOSH_SWEEP_DEBUG=1`) and pass.

## 2. Tensor split

Method: `GGML_METAL_DEVICES=2 llama-bench -m <model> -ngl 99 -sm tensor -p 0 -n 128 -r 5 -fa 1`,
ctx default (tg128 only), llama-bench discards its own warmup; control `TOSH_MV_ROWS8_DISABLE=1`;
cells alternated ctl, new, two rounds; t/s mean +- sd over r = 5.

| model | round | control | rule |
|---|---|---|---|
| Qwen3-4B Q6_K | 1 | 16.71 +- 0.02 | 19.09 +- 0.02 |
| Qwen3-4B Q6_K | 2 | 16.71 +- 0.02 | 19.10 +- 0.02 |
| Qwen3-8B Q4_K_M | 1 | 13.84 +- 0.01 | 16.39 +- 0.01 |
| Qwen3-8B Q4_K_M | 2 | 13.81 +- 0.01 | 16.38 +- 0.01 |

These compare tensor split with and without the control only; they say nothing about tensor split
against layer split. `-sm tensor` loaded and ran; nothing was rejected. Both cards were busy during
decode (ioreg `Device Utilization %` of both IOAccelerators, 80-99 while serving).

Text: llama-server, same split, `-c 4096 -t 8 -fa auto --parallel 1 --cache-ram 0`, two greedy
/completion requests (temperature 0, top_k 1, n_predict 256, cache_prompt false; the BST prompt and
a lighthouse-keeper story), control vs rule: byte-identical on both models.

## 3. 32-lane GPUs

Not measurable here (no 32-lane device). From the code, `ggml-metal-device.cpp` after 0072: the
only two reads of `TOSH_MV_ROWS8_DISABLE` are at lines 1760 (q4_K) and 1814 (q6_K), and they sit
inside `if (simd_width == 64 && !q4k_small && ...)` (1753) and `if (simd_width == 64 && ...)`
(1811). With `simd_width == 32` neither block is entered, so nr0 and the suffix come from the code
before the rule and the selection is the same with and without the control. The rule also does not
touch `ggml_metal_mv_nc2_rows`, which handles n > 1. The only way to reach an r8 or L16 kernel at
32 lanes is the explicit sweep hook (`TOSH_SWEEP_*`, line 2018), which is a measurement tool. No
bug found.

## 4. The 35B's DFlash drafter

Setup: Ornith-1.0-35B Q6_K target on the host (`-ngl 0 -t 12`), DFlash Q8_0 drafter on card 1
(`-ngld all -devd MTL0`, `--spec-type draft-dflash --spec-draft-n-max 3`), `-c 16384 -fa auto
--parallel 1 --cache-ram 0`, `TOSH_FA_AMD=1`. Requests: BST prompt, greedy, n_predict 128,
cache_prompt false; 4 per server, first discarded (`0d-req.py`).

- Drafter shapes (gguf): 6 layers, n_embd 2048, all Q8_0: attn_q 2048 x 4096, attn_k/v 2048 x 1024,
  attn_output 4096 x 2048, ffn_gate/up 2048 x 6144, ffn_down 6144 x 2048 (6 each), fc 16384 x 2048
  (one). It has no output head: it borrows the target's (`src/models/dflash.cpp:837-849`), which
  under `-ngl 0` is the 2048 x 248320 Q6_K matrix on the host.
- Pipelines (`TOSH_SWEEP_DEBUG=1`, one server, 4 requests): Metal runs only Q8_0 mat-vec:
  `q8_0_f32_c4_r4` (3600), `c4_r2` (2832), `r4_w64` (1300), `c2_r8` (42). A block of n_max + 1 = 4
  tokens goes down the multi-column nc2 path (`ggml_metal_mv_nc2_rows`, Q8_0 at 4 columns takes
  nr1 = 4 on 64 lanes, line 2055); no mat-mat pipeline is involved at this size.
- Time split, from the server's own speculative statistics (`-lv 4`, `dur(b,g,a)`, cumulative,
  `0d-draft-stats.txt`): per measured request the draft calls took 1865.7, 1835.3 and 1852.8 ms
  of 11796, 11662 and 11796 ms of generation (N = 3; 29 drafts per request, 73 of 87 drafted
  tokens accepted, text identical across all requests and to the run without `-lv 4`).
- The Metal part of a draft: the drafter's Q8_0 products at n = 4, measured in isolation
  (`test-backend-ops perf`, card 1, N = 5, `0d-q8_0-n4-perf.txt`): q 455.7 us, k and v 188.8 us
  each, o 444.2 us, gate and up 717.4 us each, down 663.3 us; 3375.6 us per layer, 20.3 ms for six
  layers, plus fc 1.9 ms. That is about 22 ms of a measured ~64 ms per draft and about 0.64 s of
  an ~11.75 s request: below the brief's 15% gate. These are isolated kernel timings summed, not an
  in-situ trace, so treat 22 ms as the kernels' cost on an idle card.

Decision: no kernel change for the drafter (no `TOSH_MV_DFLASH_DISABLE`). The rest of the draft
call is host work: the borrowed 248320-row Q6_K head at 4 columns, sampling over that vocabulary,
and the handoff. That host head is the next lever (for example, a card-resident copy of the output
matrix for the drafter), not the Metal mat-vec selection. Not measured yet.
