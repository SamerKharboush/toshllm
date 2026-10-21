# GPU decode: this branch is 7.7% faster than the shipped 0.87.26 build

## The measurement

Qwen3-8B-Q4_K_M, `-ngl 99`, `-c 4096`, `-t 8`, `temperature 0`, 128 tokens predicted, ten
interleaved trials, both servers resident at the same time so the comparison is between builds
and not between moments.

| | mean | sd | n |
|---|---|---|---|
| this branch (`fce9e70e`, AVX1) | **8.159 tok/s** | 0.0054 | 10 |
| shipped `ToshLLM-v0.87.26-noavx2` (`c232e476`) | 7.573 tok/s | 0.0431 | 10 |

```
delta = +0.586 tok/s (+7.74%), se 0.0137, 42.7 sigma
```

Raw trials, ours / shipped:

```
8.160/7.454  8.166/7.581  8.164/7.571  8.163/7.578  8.163/7.594
8.158/7.598  8.157/7.595  8.153/7.595  8.152/7.568  8.152/7.595
```

## The baseline correction, which is the whole point

The same comparison against **pristine upstream llama.cpp at the pin** gives 2.55 tok/s, so
this branch is 3.2x faster than that. That number must not be published, because pristine
upstream is not the baseline.

The baseline is the **shipped 0.87.26 ToshLLM build**, and it already logs
`wave64 decode ON: quantized/f16/bf16 mat-vec on GPU`. So the wave64 decode work is in the
vendor's product, and it was never this fork's differentiator -- the earlier reading that
"wave64 is ours" was wrong, and the shipped build settles it. The honest delta is **7.7%**,
not 3.2x.

## Two caveats that belong in the method line, not a footnote

1. **This branch is faster while degraded.** It drops
   `kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64` (ticket 56) and the shipped build does
   not. So 7.7% is what this branch delivers with a missing kernel, and fixing that kernel may
   move the number. A rise after the fix is the removal of a defect, not a discovery.
2. **The ISA is not controlled.** The shipped build is SSE4.2 (that is what "noavx2" means) and
   this branch is AVX1+F16C. At `-ngl 99` decode is GPU-bound and the CPU-side share is small,
   but it is not zero, and `ours@SSE2` has not been run through this comparison. Until it is,
   7.7% is the gap between *two builds as shipped*, not a clean branch-vs-branch delta.

## Output fidelity is not established for this build

The 0.9389-versus-0.9982 cosine was measured on the stale 0.87.24 bundle. It does not describe
this build and cannot be quoted next to 7.7%. A speedup is not a win until the output is
checked, and the fidelity lane is still open.

## What this does say

This is the first number in this effort that is measured against the correct baseline, on the
path the fork actually changed, with a proper sample and an interleaved protocol. It is
modest, it is real, and it is the honest size of the advantage.

## Method

- Engines: this branch and the shipped DMG's `llama-server`, both reporting llama.cpp commit
  `d81235049`. The DMG's engine is `c232e476`, 26,466,352 B; ours is `fce9e70e`, 27,056,432 B.
- Model: Qwen3-8B-Q4_K_M, local file, 4.7 GB.
- Offload: `-ngl 99`. Context 4096, 8 threads, `temperature 0`, `cache_prompt` default.
- Prompt: one fixed sentence about Rayleigh scattering, identical for every trial.
- N = 10 per side, **interleaved** (ours, shipped, ours, shipped, ...) with both servers
  resident, so thermal drift and page-cache state are shared rather than confounded.
- Statistic: mean and sample sd per side; sigma from the difference of means against the
  standard error of that difference.
- The engine's own timing line, `timings.predicted_per_second`, is the quantity, not a
  wall-clock wrapper.
