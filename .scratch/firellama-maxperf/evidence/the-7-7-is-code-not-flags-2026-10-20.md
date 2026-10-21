# The 7.7% is code, not compiler flags

## The three-way comparison

Qwen3-8B-Q4_K_M, `-ngl 99`, `-c 4096`, `-t 8`, `temperature 0`, 128 tokens predicted, **ten
interleaved trials with all three servers resident at once**, one session.

| build | mean | sd | n |
|---|---|---|---|
| this branch, AVX1+F16C (`fce9e70e`) | 8.156 tok/s | 0.0326 | 10 |
| **this branch, SSE4.2 (`b8ef1158`)** | **8.175 tok/s** | 0.0155 | 10 |
| shipped 0.87.26 (`c232e476`, SSE4.2) | 7.588 tok/s | 0.0145 | 10 |

| comparison | delta | sigma |
|---|---|---|
| ours@AVX1 vs shipped | +0.568 tok/s (+7.48%) | 50.4 |
| **ours@SSE2 vs shipped** | **+0.587 tok/s (+7.74%)** | **87.5** |
| ours@SSE2 vs ours@AVX1 | −0.019 tok/s | within noise |

## What that settles

The shipped build is SSE4.2 -- that is what "noavx2" means -- and this branch is AVX1. So
before this run, the 7.7% could have been the compiler flags and nothing else.

**It is not.** This branch compiled to the *same* SSE4.2 baseline as the shipped build still
decodes at 8.175 tok/s, 7.74% faster at 87.5 sigma. The ISA changes nothing (ours@SSE2 and
ours@AVX1 are 0.019 tok/s apart, inside their own noise), so the difference is the code.

This is the opposite of the CPU lane, and both results now stand together:

- **CPU path (`-ngl 0`)**: the ISA is the whole difference. 5.7% faster, and upstream gets the
  same 6.0% by rebuilding. A packaging claim.
- **GPU decode (`-ngl 99`)**: the ISA is nothing. 7.7% faster, and upstream does not get it by
  rebuilding. A code claim.

## The caveats that still stand, and belong in the release note

1. **This build is missing a kernel.** It drops
   `kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64` and the shipped build does not. So 7.7%
   is what this branch delivers *while degraded*. When ticket 56 lands the number may move, and
   a rise then is a defect removed, not a discovery. That sentence should be written down now,
   before the number changes, so nobody later reads recovery as improvement.
2. **Output fidelity is unestablished for this build.** The 0.9389-versus-0.9982 cosine was
   measured on the stale 0.87.24 bundle and does not describe these binaries. A decode win with
   degraded output is a trade, and the release note has to say which it is. The fidelity row is
   still owed.
3. **The model fits in one card.** 8B-Q4 is 4.7 GB on a 6 GB card. The 35B-A3B MoE is the case
   where the second D700 and the 64 GB matter, and that measurement is in
   `the-35b-moe-serves-2026-10-20.md`.

## The sentence this supports, and the one it does not

Supported: *7.7% faster than the shipped build at `-ngl 99` decode on an 8B Q4 model, measured
on a build that is missing the AMD vector flash-attention kernel; the ISA is controlled by an
SSE2 build of the same source; output fidelity is [outstanding].*

Not supported: any statement about the second D700, about the 64 GB, about tensor splitting
across two cards, or about models larger than one card. Those are separate cells with separate
numbers, and the second D700 has been idle in every measurement so far.

## Method

- Engines: this branch at two ISA variants, and the shipped `ToshLLM-v0.87.26-noavx2` DMG's
  `llama-server`. All three report llama.cpp commit `d81235049`.
- Model: Qwen3-8B-Q4_K_M, local file, 4.7 GB.
- Offload `-ngl 99`; context 4096; 8 threads; `temperature 0`; 128 tokens predicted; one fixed
  prompt for every trial.
- N = 10 per side, **interleaved**, all three servers resident, so drift is shared.
- Statistic: mean and sample sd; sigma from the difference of means against the standard error
  of that difference.
- Quantity: the engine's own `timings.predicted_per_second`.
