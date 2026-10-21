# The prefill variant that fits 32 KB, and whether it is worth anything

Ticket: `../issues/65-the-prefill-kernel-that-does-not-fit-in-32-kb.md`. Spec: `../spec.md`
(Revision 8). Date: 2026-10-20.

## The question

The wide prefill kernel asks for more threadgroup memory than a GCN 1.0 threadgroup has, so
the driver refuses it and the prompt eval runs on the tile kernel. The host can already ask
for a smaller instantiation by name (`TOSH_FA_PF_BQ` / `TOSH_FA_PF_BK`); what it cannot do is
pick the one the card can hold. The ticket asks for the host to pick it by
`props.max_theadgroup_memory_size`, and for the payoff to be measured.

## The arithmetic

From the kernel (`ggml/src/ggml-metal/kernels/fa_w64.metal`): the threadgroup arrays are
`sq[BQ*SQS]`, `skv[max(BK*SQS, DV*SVS)]` and `sp[BQ*SVS]` in halves, with `SQS = DK+4` and
`SVS = BK+4`. The bytes are twice that sum. The card's limit is 32768 bytes on both D700s
(measured in `threadgroup-memory-2026-10-18.md`).

| head | instantiation | bytes | fits 32 KB |
|---|---|---|---|
| 64 | `BQ=64, BK=64, LG=16` | 26112 | yes |
| 128 | `BQ=64, BK=64, LG=16` (the default) | 43008 | no |
| 128 | `BQ=32, BK=64, LG=16` | 30208 | yes |
| 128 | `BQ=16, BK=64, LG=16` | 23808 | yes |
| 256 | `BQ=32, BK=64, LG=16` (the default) | 55808 | no |
| 256 | `BQ=16, BK=64, LG=16` | 45312 | no |
| 256 | `BQ=16, BK=32, LG=16` | 27904 | yes |
| 512 | `BQ=16, BK=32, LG=16` (the default) | 54528 | no |

The 256-head fitting variant did not exist: the ticket's table listed `BQ=16, BK=32` as if it
were instantiated, and the .metal file did not have it. It does now (patch 0040).

## The measurement, head 128

The 8B (Qwen3-8B-Q4_K_M, head 128) can run every variant that fits, so it needs no new
kernel and no code change to answer the question: does the wide prefill kernel beat the tile
kernel on this card?

| cell | prompt eval | n | the kernel that ran |
|---|---|---|---|
| the tile kernel (the default) | 40.5129 tok/s (sd 2.6303) | 5 | `kernel_flash_attn_ext_pf_amd_dk128_kf16_vf16` + the tile kernel |
| the wide kernel, `BQ=32, BK=64` (29.5 KB) | 39.6175 tok/s (sd 3.0234) | 5 | `..._w64_lg16q32k64` |
| the wide kernel, `BQ=16, BK=64` (23.25 KB) | 39.4933 tok/s (sd 2.8193) | 5 | `..._w64_lg16q16k64` |

The two wide kernels are 0.90 and 1.02 tok/s behind the tile kernel, against a standard
deviation of 2.6 to 3.0 on five trials. The difference is inside the noise: at head 128 the
wide prefill kernel buys nothing on this card.

The control for each cell is the engine's own log, which names the kernel the path took
(`TOSH_FA_PF_DEBUG=1`): the default cell logs the tile fallback twice, and the two override
cells log the wide kernel and no fallback at all. A cell that silently kept the tile kernel
would have shown the fallback line.

## The measurement, head 256 (the 35B)

The 35B (Ornith-1.0-35B Q6_K) has head 256, and no variant that fits 32 KB existed for it,
so the code change and a new instantiation were needed before the question could be asked.
Both were written (patch 0040: the host picks the variant that fits
`props.max_theadgroup_memory_size`, and the kernel file gained the `BQ=16, BK=32` 256-head
instantiation), the engine was rebuilt, and the 35B was measured on both paths.

| cell | prompt eval, all five trials | mean | sd | the kernel that ran |
|---|---|---|---|---|
| the tile kernel (`TOSH_FA_PF_W64_DISABLE=1`) | 4.9438, 3.6545, 5.3093, 6.6344, 6.6815 | 5.4447 | 1.2668 | `kernel_flash_attn_ext_pf_amd_dk256_kf16_vf16`, tile fallback in the log |
| the variant that fits 32 KB (the default path with the patch) | 4.1756, 6.6448, 6.6015, 6.6756, 6.7508 | 6.1697 | 1.1160 | `..._w64_lg16q16k32`, no tile fallback |

The first trial of each cell is the page cache filling: the model is 27 GB and the disk
reads it at a few hundred MB/s, and the first two trials of the tile cell are still paying
for it. The warm trials are the last two of each cell, and they are the comparison:

| cell | warm prompt eval | the decode | the text |
|---|---|---|---|
| the tile kernel | 6.6344, 6.6815 | 0.1533 tok/s | `'\n\n<think>\nHere\'s a thinking process'` |
| the variant that fits 32 KB | 6.6756, 6.7508 | 0.1533 tok/s | `'\n\n<think>\nHere\'s a thinking process'` |

The two cells are 0.055 tok/s apart in the warm state, 0.8%, while the trials inside a cell
spread 0.7%. The decode is identical to four decimals and the eight generated tokens are
the same string in both. **There is no payoff**: the wide prefill kernel that fits 32 KB
computes the same prompt eval as the tile kernel, to inside the noise.

The controls, from the engine's own log in each cell (`TOSH_FA_PF_DEBUG=1`): the tile cell
names the 32-lane kernel and logs the tile fallback once, the patched cell names
`kernel_flash_attn_ext_pf_amd_dk256_kf16_vf16_w64_lg16q16k32` and logs no fallback at all.
A cell that silently kept the tile kernel would have shown the fallback line and the 32-lane
name.

## The outcome

**The patch was measured and dropped.** The ticket says: "If the payoff is not there, the
ticket closes with the measurement and no code change." The 8B says the same at head 128
(40.5129 against 39.6175 and 39.4933, inside a standard deviation of 2.6 to 3.0) and the
35B says it at head 256 (6.6344 and 6.6815 against 6.6756 and 6.7508). The variant works:
the host can pick it, the driver accepts it, the text is the same, the decode is the same.
It is not faster, so the fork does not carry it, and a new kernel in the release path that
buys nothing is a risk rather than a feature.

The 50-patch series is what the release ships, and the 35B's prompt eval in the rows
(R1) is the tile kernel's.

## What the record does not establish

- Nothing here says the wide prefill kernel is useless. It says it is not faster than the
  tile kernel on this card, at head 128 and at head 256, with the model in the page cache.
- The warm-up trials are not discarded in the tables above; they are the disk reading the
  model, and they are the reason the two means are further apart than the two warm pairs.
- Head 512 has no variant that fits 32 KB, and none was written: the 512-head default asks
  for 54528 bytes and the card has 32768.

## Method line

- Machine: `Sams-Mac-Pro`, Intel Mac Pro x86_64, Intel Xeon E5-2697 v2 (12 physical, 24
  logical), 64 GB RAM, two AMD Radeon HD FirePro D700 (GCN 1.0, wave64, 6 GB each). The
  headless card is device 1 (`GGML_METAL_DEVICE_INDEX=1`).
- Engine: `vendor/llama.cpp/build-static/bin/llama-server`, built by
  `scripts/build-engines.sh` at the pin `d81235049384534c167caea52b85a694f6103d14` with the
  fork's patch series. The 8B cells ran on the 40-patch engine, the 35B cells on the
  41-patch engine that carried the candidate patch, which the release does not. Apple clang 17, 0 AVX2/FMA mnemonics.
- Models: Qwen3-8B-Q4_K_M (head 128) and Ornith-1.0-35B Q6_K (head 256).
- Flags: `-ngl 99 -sm tensor -c 4096 -t 8`, temperature 0, seed 1234 for the text check.
  The prompt is "Explain what a binary search tree is." repeated 24 times (about 190 tokens)
  with `cache_prompt: false`, and `n_predict: 1`; the engine's own `prompt_per_second` is the
  quantity.
- N: 5 per cell. Warmups: none discarded; the first trials are the disk reading the model
  and are reported.
- What could not be run: the wide kernel at head 256 before the candidate patch, because
  the driver refused every variant that existed for that head size.

