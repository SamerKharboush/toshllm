# 29 - The logit parity floor is set by stock, and stock fails the stated threshold

Status: findings recorded, disposition open
Date: 2026-10-17

## What was built

`tools/parity/logitprobe.cpp` and `tools/parity/compare_logits.py`. The probe
runs one batched forward pass and dumps raw fp32 logits for every position via
`llama_get_logits_ith`. Compiled twice, once against a CPU-only oracle and once
against the fork, from the same source.

The CPU oracle is the pristine pin (`d81235049384534c167caea52b85a694f6103d14`,
unpatched, zero porcelain) built with `-DGGML_METAL=OFF`, x86_64 Release,
sha256 `a211408fbb67711750148b1d261e204901f5d6a23ca4de4a853a0a12617f82ea`.

The oracle that was specified does not exist. `llama-bench --logits-all` and
`--logits-file` are not flags in either tree. The nearest thing,
`llama-perplexity --save-all-logits`, writes fp16 log-probabilities
(`perplexity.cpp:172`), a resolution of about 0.008 near a log-prob of -10,
which is roughly 400x too coarse to resolve the 1e-5 threshold being asked for.
Hence the probe.

## Measured, same model (Qwen3-0.6B-Q8_0), same 16-token prompt, same machine

| build                                        | max abs | cosine | top-1 flips |
|----------------------------------------------|---------|--------|-------------|
| fork, CPU path (Metal bypassed)               | 0       | 1.0000 | 0 / 16      |
| pin, Metal (falls back to CPU for matmul)     | 1.28788 | 0.9982 | 0 / 16      |
| fork, Metal (runs matmul on GPU)              | 4.63766 | 0.9389 | 1 / 16      |

14B Q4_K_M, same prompt: fork Metal 1.16017 / 0.9976 / 0 / 16.

## The finding

1. The fork's CPU path is bit-identical to the pin's CPU path. The 38 patches
   do not perturb CPU numerics at all.

2. **Stock llama.cpp fails the stated threshold on this machine.** 1.28788 and
   cosine 0.9982 against a bar of 1e-5 / 0.9999. The 1e-5 bar is not a
   bar the fork fails, it is a bar no build on this hardware passes. Reporting
   the fork's number against 1e-5 without the stock number beside it would
   attribute a hardware floor to the fork.

3. Stock achieves its number by not using the GPU. On the D700, stock Metal
   compiles zero matmul kernels and prints
   `resolve_fused_ops: layer 0 is assigned to device MTL0 but Flash Attention is
   assigned to device CPU (usually due to missing support)`.
   `ggml-metal-device.m` gates `GGML_OP_MUL_MAT` on `has_simdgroup_reduction`,
   and these cards report no Metal3 (see 30). So stock is correct because it is
   running on the CPU, not because its Metal path is right. Kernel compiles for
   the same run: stock 7, fork 19. CPU-fallback lines: stock 1, fork 0.

4. Therefore pin-Metal vs fork-Metal is **not** an attribution experiment. It
   compares a CPU-bound build against a GPU build. Any conclusion drawn from it
   would be wrong.

## Not the cause

The fork's missing `kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64` is not
the cause of the divergence. N=1 through its fallback gives 4.66038 and N=16
through the clean `_tile_` kernel gives 4.63766, the same magnitude by different
kernels. The cause is common to both paths.

## Void results

Four prefill ablations (`TOSH_MM_W64_DISABLE`, `TOSH_W64_PREFILL_DISABLE`,
`TOSH_MM_WIDE_W64_DISABLE`, `TOSH_EXT_W64_DISABLE`) all produced one distinct
sha256, `ea72a967abdfb11f`. Those flags do not reach the prefill path. The four
runs are void and are not evidence for anything.

## Open

Whether 4.64 with one top-1 flip is acceptable for the fork, given the
alternative on this hardware is not using the GPU at all. Needs a decision, not
more measurement.

## Disposition (decided)

1. Accept the divergence as the cost of GPU acceleration on this hardware.
   Record the measured floor rather than a threshold that nothing passes. The
   0.6B top-1 flip stays a tracked risk, not a blocker.
2. Park the Vulkan-on-Linux pivot. Reopening conditions: a D700 Metal path
   that cannot be made correct AND a working RADV configuration that survives
   long contexts, verified on this machine rather than reported from another.
   Note that on macOS there is no native Vulkan, MoltenVK translates to Metal.
3. The maintainer's "validated bit-for-bit" claim is not reproduced here. Kept
   in the repo, not posted upstream.

## The numbers to use from here on

| build | max abs | cosine | note |
|---|---|---|---|
| fork CPU path | 0 | 1.0000 | the patches do not touch CPU numerics |
| pin Metal | 1.28788 | 0.9982 | this is the floor a stock build sets here |
| fork Metal | 4.63766 | 0.9389 | 0.6B |
| fork Metal | 1.16017 | 0.9976 | 14B |

Report the fork against the stock Metal number, never against 1e-5.
