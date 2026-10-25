# Which GPU ops a 35B decode token spends its time on

Date: 2026-10-25. Map ticket: `.scratch/pooled-budget/issues/10-which-gpu-ops-take-the-59-ms.md`.

## Method

- Engine: fork engine `d81235049` plus 54 patches. 0049 is the per-op GPU mode
  (`TOSH_OPGPU=1`), in its corrected form (see below). Built AVX1: 0 AVX2/FMA mnemonics.
- Model: Ornith-1.0-35B Q6_K.
- Launch: `llama-cli -c 4096 -t 12 -fa auto --load-mode none --dynamic-moe on`, greedy,
  `-n 48`, the BST prompt, with `TOSH_FA_AMD=1` on card 1 (`GGML_METAL_DEVICE_INDEX=1`).
- Sample: one run, 47 decode graphs of 3818 nodes each. N is small, so the shares below are
  from a single 48-token run.
- In the per-op mode every op runs in its own command buffer, and the time is
  `GPUEndTime − GPUStartTime` per buffer.
- **Correctness:** the per-op mode's 48-token greedy text is identical to the normal mode's
  on the 35B, and on the dense 0.6B.
- **Overhead per buffer:** the cheapest ops measure 2.7–8 µs (DUP 2.73, CLAMP 6.96), which
  bounds it. The per-op total, 77.957 ms per graph, compares with the expert-tier token of
  about 76 ms.

## Rows (GPU ms per decode graph, which is per token)

| op | n per token | ms per token | µs per op |
|---|---|---|---|
| MUL_MAT/q6_K (non-expert weights and output head) | 311 | 39.553 | 127.18 |
| TOSH_DMOE_JOIN (includes the wait on the CPU experts) | 40 | 9.898 | 247.45 |
| MUL_MAT_ID/q6_K (experts resident in the arena) | 80 | 9.341 | 116.76 |
| RMS_NORM+fused | 191 | 3.470 | 18.17 |
| MUL_MAT/f32 | 80 | 2.290 | 28.63 |
| SOFT_MAX+fused | 40 | 2.247 | 56.17 |
| GATED_DELTA_NET | 30 | 1.523 | 50.77 |
| FLASH_ATTN_EXT | 10 | 1.162 | 116.15 |
| 18 other op kinds | | 8.47 | |
| **total** | | **77.957** | |

## Bytes behind the largest row

From the GGUF tensor table:
- non-expert q6_K weights: 310 tensors, 1102.3 MiB;
- output head: q6_K, 397.9 MiB;
- token_embd is a gather, and is not in this row.

So the 311 MUL_MAT/q6_K ops read about 1500.2 MiB = 1.573 GB per token, in 39.553 ms: an
effective **39.8 GB/s**. The D700's rated memory bandwidth is 264 GB/s. That is a vendor
figure, given here for scale, not as a denominator.

## Reading

- **Half of a 35B decode token's GPU time is the dense Q6_K mat-vec,** which reads the
  non-expert weights at an effective 39.8 GB/s.
- **The join, 9.9 ms, is the GPU waiting on the CPU experts,** now measured directly.
- **The resident experts take 9.3 ms.**
- Every model on the cards decodes through this kind of kernel; R25's 8B Q4_K_M across both
  cards decodes at only 9.0 tok/s. That is the case for a GCN mat-vec lever. Its size has
  not been measured on its own.

## The per-op mode's defect, and the fix in 0049

- **Symptom:** the first version answered garbage on the 35B, from the second token on. It
  was right on the 0.6B.
- **Bisection (by OpenCode):** splitting the command buffer before node 45, a
  GATED_DELTA_NET, breaks it.
- **Cause (found here):** the gated-delta-net state fusion. An encoder folds the GET_ROWS
  gather before a GDN and the state CPY after it, deciding by looking across neighbouring
  nodes; for the CPY it looks back up to 16 nodes. A per-op encoder that started at the CPY
  could not see the GDN behind it, so it ran the copy. That overwrote the state the GDN had
  already written directly.
- **Fix:** every per-op encoder now spans the whole graph and encodes one op of it, so each
  fusion is decided exactly as on the normal path. No op is special-cased.
- **Rejected along the way:**
  - full serialisation (`waitUntilCompleted` per buffer): still garbage;
  - an exact node cursor: still garbage;
  - one buffer for the whole Dynamic MoE zone: correct, but it timed nothing;
  - a "must share" list hardcoded to 3818-node graphs: it never split by default, and every
    op showed the same 73.9 ms.
