# 65: the prefill kernel that does not fit in 32 KB of threadgroup memory

Status: resolved
Type: task
Spec: ../spec.md (Revision 8)

## Problem

The 64-lane prefill kernel wants more threadgroup memory than a GCN 1.0 threadgroup has, so
the driver refuses it and the 35B's prompt eval runs on the tile kernel instead. The refusal
is now quiet and named (patch 0039), which is what the release needs, but the speed is still
on the table.

The sizes, from the kernel (`kernels/fa_w64.metal`, `BQ*SQS + max(BK*SQS, DV*SVS) + BQ*SVS`
halves):

| head size | instantiation | threadgroup memory | fits in 32 KB |
|---|---|---|---|
| 64 | `BQ=64, BK=64, LG=16` | 25.5 KB | yes |
| 128 | `BQ=64, BK=64, LG=16` | 42.0 KB | no |
| 128 | `BQ=16, BK=64, LG=16` | 23.25 KB | yes |
| 256 | `BQ=32, BK=64, LG=16` | 54.5 KB | no |
| 256 | `BQ=16, BK=32, LG=16` | 27.25 KB | yes |

The smaller variants are already instantiated, and the host can already ask for them with
`TOSH_FA_PF_BQ` / `TOSH_FA_PF_BK`. What is missing is the host choosing them by the card's
threadgroup limit rather than by an environment variable, and the payoff measured.

## Change

Let the host pick the prefill variant that fits `props.max_theadgroup_memory_size`, the same
way the vector path picks its twin. Measure the 35B's prompt eval before and after.

## Done when

- The 35B's prompt eval is measured with the default variant and with the fitting one, n >= 5
  each, against the T1 spine.
- The chosen variant is the one the card's limit admits, with the arithmetic in the method
  line.
- If the payoff is not there, the ticket closes with the measurement and no code change.

## Answer

**The payoff is not there, so the code change was measured and dropped.** The evidence is
in `../evidence/the-prefill-variant-that-fits-32-kb-2026-10-20.md`.

The variant that fits 32 KB was written, instantiated and measured:

- The host picked the variant by `props.max_theadgroup_memory_size` (32768 bytes on both
  D700s), and the 256-head kernel file gained the `BQ=16, BK=32` instantiation that the
  ticket's table assumed and the file did not have.
- At head 128 (the 8B, no new kernel needed): the tile kernel 40.5129 tok/s, the wide
  kernel that fits 39.6175, the smaller one 39.4933, on five trials each with a standard
  deviation of 2.6 to 3.0. Inside the noise.
- At head 256 (the 35B, the new instantiation): the tile kernel 6.6344 and 6.6815 tok/s on
  the two warm trials, the variant that fits 6.6756 and 6.7508. The decode is 0.1533 tok/s
  in both cells and the eight generated tokens are the same string.
- The control in each cell is the engine's own log: the tile cell names the 32-lane kernel
  and logs the tile fallback, the patched cell names
  `kernel_flash_attn_ext_pf_amd_dk256_kf16_vf16_w64_lg16q16k32` and logs no fallback.

The wide prefill kernel that fits computes the same prompt eval as the tile kernel, to
inside the noise, on both head sizes. It works, and it is not faster, so the fork does not
carry it: a new kernel in the release path that buys nothing is a risk and not a feature.
The 50-patch series is what the release ships, and R1's 35B prompt eval is the tile
kernel's.

Head 512 has no variant that fits 32 KB and none was written: the 512-head default asks
for 54528 bytes and the card has 32768.

