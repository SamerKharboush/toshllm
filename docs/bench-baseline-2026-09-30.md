# Baseline 2026-09-30: 2x FirePro D700, Xeon E5-2697 v2, TOSH_NO_AVX2=1, engine 0.87.11

Env: GGML_METAL_CONCURRENCY_DISABLE=1, 12 threads, -ngl 99 --load-mode none -fa 1.
FA AMD on wave64 was turned on by `TOSH_FA_AMD=1` when these rows were measured; that flag is gone
(`14f5aee`), the path is default-on, and `TOSH_FA_AMD_DISABLE=1` is the only opt-out.
**Prompt-processing figures in this table are pp512.** See the prompt-length section below: pp on this
pair is not prompt-length-invariant, so a pp figure without its prompt length does not mean anything.

| model | mode | pp512 t/s | tg t/s |
|---|---|---|---|
| Qwen3-0.6B-Q8_0 | single MTL | 368.72 | 51.06 |
| Qwen3-4B-Q6_K | single MTL | 78.70 | 12.00 |
| Qwen3-4B-Q6_K | tensor none | 141.71 | 17.50 |
| Qwen3-4B-Q6_K | tensor peer | 141.85 | 17.49 |
| Qwen3-4B-Q6_K | tensor events | 153.26 | 17.48 |
| Qwen3-4B-Q6_K | tensor peer+events | 153.36 | 17.49 |
| Qwen3-4B-Q6_K | layer dual (DEVICES=2) | 78.45 | 11.96 |
| Qwen3-14B-Q4_K_M | layer dual (DEVICES=2) | 29.24 | 5.10 |

## Prompt length matters, and the two modes peak at different lengths

Re-measured 2026-10-16 with `llama-bench -n 0 -r 2`, 4B Q6_K, dual unbridged D700. This is why the
pp512 figures above and the pp2048 figures below both looked correct and disagreed by 22%: they are
the same measurement at different prompt lengths.

| prompt length | layer pp | tensor pp |
|---|---|---|
| 512 | 78.30 | 141.37 |
| 1024 | 94.09 | 131.38 |
| 2048 | 95.62 | 115.76 |
| 4096 | 76.10 | 93.19 |

The published 2026-09-30 row is pp512: 78.30 against 78.45 for layer, 141.37 against 141.71 for
tensor, both within 0.2%. Nothing had regressed.

Prefill on this pair does not improve with prompt length. Tensor split peaks at 512 tokens and then
declines steadily to 93 tok/s at 4096. Layer split peaks around 2048. Long prompts get slower on
both, so "pp" quoted without a prompt length is not a comparable quantity.

## 2026-10-16 re-measure, llama.cpp d8123504938 + 38 fork patches, engine 0.87.24-beta.1
Dual unbridged D700, -t 12 -fa 1 -b 2048 -ub 512, pp at **-p 2048** -r 2, tg at -n 64/128 -r 3.

| model | sm | pp2048 t/s | tg t/s |
|---|---|---|---|
| Qwen3-4B-Q6_K | layer | 95.62 | 12.33 |
| Qwen3-4B-Q6_K | tensor | 115.76 | 17.90 |
| Qwen3-4B-Q4_K_M (requantized, not native) | layer | 100.65 | 14.34 |
| Qwen3-4B-Q4_K_M (requantized, not native) | tensor | 121.23 | 19.66 |
| Qwen3-14B-Q4_K_M | layer | 29.45 | 5.15 |
| Qwen3-14B-Q4_K_M | tensor | 37.84 | 8.60 |

Thread sweep at 14B tensor, -n 128 -r 3: -t 8 -> 8.60, -t 12 -> 8.60, -t 16 -> 8.58,
-t 24 -> 7.99. Prefill flat across the same sweep.

14B decode through llama-server is reported in `dist/beta24-notes.md`, not here. An earlier
N=20 measurement of it reported CVs of 0.04% and 0.02%, which is not physically plausible on dual
274 W cards in a 2013 chassis and is being re-measured with a longer, interleaved protocol before
any figure is published. Nothing from that run appears in this table.

D700 peak is 263 GB/s per card (384-bit GDDR5, 1370 MHz reference, 5480 MT/s effective); Apple
specifies 264. Paper figure. No fraction of peak is recorded anywhere in this repo.

Notes:
- Layer split needs GGML_METAL_DEVICES=2 count var; DEVICE_LIST=0,1 alone leaves MTL1 closed on layer path.
- Tensor engages both GPUs; events +8pct prefill, peer inert (cards not bridged, peer group 0).
- tg flat across sync configs (wave64 CPU decode by design).
- maxBufferLength 3.5 GiB per D700.
- Host CPU is Xeon E5-2697 v2: Ivy Bridge-E, 22nm, 12c/24t at 2.7 GHz, 30 MB L3, DDR3-1866.
  AVX and F16C only, no AVX2 and no FMA3, confirmed from machdep.cpu.features and leaf7_features.
  TOSH_NO_AVX2=1 is required; building without it SIGILLs.
- Layer split is sequential by construction at batch-1 decode. A layer split over two cards gives one
  card's throughput, not two cards' worth. It is a capacity mode, not a speed mode.

Standing guard (re-measure, do not optimise):
- layer dual must not fall below single MTL on any model that fits one card. Qwen3-4B-Q6_K is the
  witness row: 11.96 tg dual against 12.00 single, and 78.30 pp512 dual against 78.70 single. One
  card's throughput is the ceiling for a layer split, not a target to beat. If either number drops
  below the single-card figure, that is a regression to diagnose, not to re-baseline.
