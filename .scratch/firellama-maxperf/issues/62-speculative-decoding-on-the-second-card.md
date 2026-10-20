# 62: speculative decoding with the draft on the second card

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 8)

## Problem

The draft fires, at 40% acceptance and a mean length of 4.2, and it is 3.5x slower than no
draft at all (2.36 vs 8.19 tok/s, ticket 60). The mechanism is not the problem: the 0.6B draft
competes with the 8B target for the one card that is already the bottleneck. Strata's
architecture puts the draft on one GPU and the target on the other, which is the one thing
this box could not do until both D700s were enrolled.

## Change

Both cards enrolled. The draft on B, the target on A, `--spec-type draft-simple
--spec-draft-n-max 8`, the draft's own placement recorded (`--spec-draft-device`,
`--spec-draft-n-cpu-moe`, `--spec-draft-n-gpu-layers`). Acceptance rate and net tok/s, not
the ratio.

## Done when

- The acceptance rate and the net tok/s, next to the one-device number, with the draft's
  placement recorded.
- Either the ratio is reproduced on two cards, or the ticket closes with "gated on
  dual-device; measured 3.5x loss on one device" and the two-card attempt.
- The draft's own memory and offload settings are in the method line.
