# 60: speculative decoding with a draft model

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 8)

## Problem

Strata's published 1.6-1.8x comes from a small draft model proposing and the big model
verifying. llama.cpp has the same mechanism, and this box has both models already:
`Qwen3-0.6B-Q8_0` as the draft and `Qwen3-8B-Q4_K_M` as the target. It is the one Strata idea
that needs no new code, and it is the cheapest candidate in the whole effort.

## Change

`-md qwen3-0.6b.gguf --draft-max 8 -ngl 99` on the draft, target at 8B. Report the acceptance
rate and the net tok/s, not just the ratio.

## Done when

- Acceptance rate and net tok/s on this box, next to Strata's published 1.6-1.8x, measured the
  same way and labelled as a target to reproduce rather than a figure to cite.
- The draft model's own offload settings recorded, since the draft runs on the same two D700s.

## Answer

Two findings, one of them a flag that does not exist.

**`--draft-max` has been removed at this pin.** The engine says so:
`error while handling argument "--draft-max": the argument has been removed. use
--spec-draft-n-max or --spec-ngram-mod-n-max`. The correct flag is `--spec-draft-n-max`.

**The draft never engages, on either build.** With `-md Qwen3-0.6B-Q8_0 --spec-draft-n-max 8`:

| build | tok/s with draft | tok/s without draft |
|---|---|---|
| this branch | 8.190 / 8.193 / 8.194 | 8.184 / 8.186 / 8.191 |
| upstream@AVX1 | 2.537 / 2.553 / 2.552 | 2.546 / 2.556 / 2.554 |

Identical to the third decimal, and the only draft-related line in either log is
`common_speculative_init_result: loading draft model ...`. A verbose run adds no drafting
counters -- there is no `n_drafted` and no `n_accepted` anywhere. The model is loaded and the
sampler never calls it, on this build and on upstream's.

So there is no acceptance rate to report, because no tokens were ever drafted. Strata's
1.6-1.8x is not reachable through this path in its current state, and the reason is that the
engine's speculative path is not engaged on this machine, not that acceptance is low.

Next step for this ticket: find why. `patches/llama/spec/0028-mtp.patch` is the fork's
speculative patch and is the first place to look, along with whether the engine needs a
different flag or a `-np`/draft-parameter to point at the draft model rather than `-md`.
