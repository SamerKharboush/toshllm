# Baseline 2026-09-30: 2x FirePro D700, Xeon E5-2697 v2, TOSH_NO_AVX2=1, engine 0.87.11

Env: GGML_METAL_CONCURRENCY_DISABLE=1 TOSH_FA_AMD=1, 12 threads, -ngl 99 --load-mode none -fa 1.

| model | mode | pp t/s | tg t/s |
|---|---|---|---|
| Qwen3-0.6B-Q8_0 | single MTL | 368.72 | 51.06 |
| Qwen3-4B-Q6_K | single MTL | 78.70 | 12.00 |
| Qwen3-4B-Q6_K | tensor none | 141.71 | 17.50 |
| Qwen3-4B-Q6_K | tensor peer | 141.85 | 17.49 |
| Qwen3-4B-Q6_K | tensor events | 153.26 | 17.48 |
| Qwen3-4B-Q6_K | tensor peer+events | 153.36 | 17.49 |
| Qwen3-4B-Q6_K | layer dual (DEVICES=2) | 78.45 | 11.96 |
| Qwen3-14B-Q4_K_M | layer dual (DEVICES=2) | 29.24 | 5.10 |

## 2026-10-16 re-measure, llama.cpp d8123504938 + 38 fork patches, engine 0.87.24-beta.1
Dual unbridged D700, -t 12 -fa 1 -b 2048 -ub 512, pp at -p 2048 -r 2, tg at -n 64/128 -r 3.

| model | sm | pp t/s | tg t/s |
|---|---|---|---|
| Qwen3-4B-Q6_K | layer | 95.77 | 12.33 |
| Qwen3-4B-Q6_K | tensor | 116.18 | 17.90 |
| Qwen3-4B-Q4_K_M (requantized, not native) | layer | 100.65 | 14.34 |
| Qwen3-4B-Q4_K_M (requantized, not native) | tensor | 121.23 | 19.66 |
| Qwen3-14B-Q4_K_M | layer | 29.45 | 5.15 |
| Qwen3-14B-Q4_K_M | tensor | 37.84 | 8.60 |

14B decode at N=20 through llama-server: tensor median 8.584 (CV 0.04%), layer median 5.146
(CV 0.02%), paired difference 77.8 ms/token, se 0.01 ms.

Thread sweep at 14B tensor, -n 128 -r 3: -t 8 -> 8.60, -t 12 -> 8.60, -t 16 -> 8.58,
-t 24 -> 7.99. Prefill flat across the same sweep.

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

Standing guard (re-measure, do not optimise):
- layer dual must not fall below single MTL on any model that fits one card. Qwen3-4B-Q6_K is the
  witness row: 11.96 tg dual against 12.00 single. A layer split is sequential by construction at
  batch-1 decode, so one card's throughput is the ceiling, not a target to beat. Layer split is a
  capacity mode. If this row ever drops below single MTL, that is a regression to fix.
