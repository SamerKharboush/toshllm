# 62: speculative decoding with the draft on the second card

Status: resolved
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

## Answer

**The draft fires on the second card and loses.** The evidence is in
`../evidence/speculative-decoding-on-the-second-card-2026-10-20.md`.

| placement | decode tok/s | drafted | accepted |
|---|---|---|---|
| the draft on the second card | 2.6250 | 138 | 45 (32.6%) |
| the draft on the target's card | 2.5168 | | |
| no draft at all | 8.3239 | 0 | 0 |

The draft on the second card is 4.3% better than the draft on the target's card, and both
are 3.17x worse than not drafting. The acceptance rate is 32.6%, so the draft is not
free, and the second card cannot make it pay: the target is the bottleneck, not the
draft.

The 35B could not be speculated at all on this machine: the engine logs "the target and
draft vocabs are not compatible" and "failed to initialize speculative decoding context",
and the server continues without a draft. The ticket's fallback clause applies: the
dual-device attempt was made and measured, and the loss is on one device as well as on
two.

`--spec-draft-device` takes device names (`MTL0` / `MTL1`), not indices: `--spec-draft-device 1`
is rejected with "invalid device: 1".