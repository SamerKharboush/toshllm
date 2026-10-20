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

