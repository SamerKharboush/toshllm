# 65: the prefill kernel that does not fit in 32 KB of threadgroup memory

Status: ready-for-agent
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
