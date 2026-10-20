# The CPU lane: a clean 2x2, and the delta is the ISA, not this fork

## Result

Prompt-processing throughput, `-ngl 0`, Qwen3-8B-Q4_K_M, five repeats per cell.

| | SSE4.2 build | AVX1+F16C build |
|---|---|---|
| **upstream @ pin** | 18.61 pp tok/s (sd 0.04) | **19.73 pp tok/s** (sd 0.08) |
| **this branch** | 18.62 pp tok/s (sd 0.03) | **19.68 pp tok/s** (sd 0.09) |

Raw samples:

```
baseline   (upstream, SSE2):  18.57 18.63 18.62 18.67 18.57
ours-sse2  (ours,     SSE2):  18.62 18.66 18.63 18.57 18.63
ours-avx1  (ours,     AVX1):  19.55 19.69 19.80 19.68 19.69
upstream-avx1 (upstream, AVX1): 19.61 19.77 19.68 19.75 19.81
```

## The decomposition

| comparison | delta | sigma | reading |
|---|---|---|---|
| ours@AVX1 vs ours@SSE2 | +1.06 tok/s (+5.7%) | 23.7 | the ISA |
| upstream@AVX1 vs upstream@SSE2 | +1.12 tok/s (+6.0%) | 31.1 | the ISA |
| ours@SSE2 vs upstream@SSE2 | +0.01 tok/s | 0.35 | parity |
| ours@AVX1 vs upstream@AVX1 | -0.05 tok/s | -1.0 | parity |

Two things fall out, and they are the same thing:

1. **This fork's patch series contributes nothing to this path.** At matched ISA the two
   branches are identical to within noise (0.35 sigma, 1.0 sigma).
2. **Upstream gets the same 5.7-6.0% if it is built with AVX1.** The speedup is the compiler
   flags, and it is available to anyone who rebuilds.

So the honest sentence is a packaging sentence, and now it has a number attached:

> This fork ships a build tuned for the machine it targets -- AVX1 and F16C, which is exactly
> this Xeon E5 v2's ISA -- while the shipped release is compiled to a generic SSE4.2 baseline so
> it runs on any x86-64. On prompt processing at `-ngl 0` with an 8B Q4 model, the tuned build
> is **5.7% faster (19.68 vs 18.61 pp tok/s)**. The same 6.0% is available to upstream by
> rebuilding with `-DGGML_AVX=ON -DGGML_F16C=ON`.

That is a real, useful, and modest number, and it is the only claim in this effort that has
never been challenged. It is also not a code differentiator and the release note must not
present it as one.

## Method

- Engines: this branch and upstream, both from pinned llama.cpp commit `d81235049`; the pin is
  asserted by `assert_artifact()` in `tools/ab.sh`.
- ISA variants: SSE4.2 via `TOSH_NO_AVX2=1`; AVX1+F16C via `TOSH_AVX1=1`. Verified by
  disassembly, not by intent: `ours-sse2` has 0 AVX1 mnemonics, `ours-avx1` has 2842, and
  neither has an AVX2/FMA mnemonic.
- Model: Qwen3-8B-Q4_K_M, local file. Offload: `-ngl 0`, so the CPU path only -- no Metal is
  touched, which is why this lane is valid while the flash-attention kernel is broken.
- Context 4096, 8 threads, `temperature 0`, `cache_prompt false`, `n_predict 1`.
- Prompt: the sentence "The history of computing begins with the abacus." repeated 220 times.
- N = 5 per cell, no warmup discarded, first sample included. The first sample is the lowest
  in three of the four cells, so any warmup effect would make the reported deltas conservative.
- Statistic: mean and sample sd per cell; sigma computed from the difference of cell means
  against the standard error of that difference.

## Two things this lane also settled

**The flash-attention defect is ours alone.** The upstream@AVX1 build was run in the same
session and logged **zero** pipeline failures, while both of this branch's builds log one. That
confirms the bisect: the defect is in this branch's build, not in the source and not in a
shipped product.

**A caveat worth stating plainly.** All four cells are x86-64 builds of the same source with
different ISA flags, and upstream's shared build is not byte-comparable to ours' static build.
That does not affect the measurement, because the cells that carry the claim are compared
like-for-like within a build configuration.
