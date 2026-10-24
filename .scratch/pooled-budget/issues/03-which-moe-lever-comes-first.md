# 03: Which MoE lever comes first

Type: grilling
Status: resolved
Blocked by: 01, 02, 04

## Question

For MoE models bigger than the cards, which lever goes first in the beta.3 spec?
- (a) a faster AVX1 (no AVX2, no FMA) host expert kernel;
- (b) a bigger expert arena from the second card (ticket 71), with what crosses the cards
  per token stated;
- (c) more overlap between the host executor and the GPU at the join.

Each needs a gate and a ceiling taken from ticket 01's breakdown.

## Context added 2026-10-23

Tickets 01, 02 and 04 are resolved. Levers (a), (b) and (c) all attack the same ~16 ms of
host expert time per token, which sits fully on the critical path:
- (a) makes each job faster;
- (b) raises the hit rate, so fewer experts go to the host;
- (c) hides the jobs behind GPU work.

Together they are bounded near 16.1 tok/s on this launch (62 ms intercept). Anything past
that needs ticket 09's breakdown of the other 62 ms.

## Answer

Decided by the user on 2026-10-24: **(b) first, then (a); (c) last.**
- (b) puts both cards' VRAM in use, and it is the only lever that shrinks the CPU work
  instead of speeding it up.
- (a) helps every MoE model, on one card or two.
- (c) needs a design change at the join, and it gives nothing past what (a) and (b) leave.

Expectation recorded with the decision. Ticket 71's own evidence says a bigger arena barely
moved the 35B's decode: 1477 MiB (40% hit rate) and 788 MiB (28%) both gave about 13.2 tok/s.
A host expert costs about 64 µs, and raising the hit rate removes few experts per token. So
(b) is mainly a **capacity** lever: both cards in use, longer contexts, and MoE models one card
refuses. Its decode gain on the 35B is estimated at a couple of ms per token, from the
measured per-expert cost; that is an estimate, not a measurement.
