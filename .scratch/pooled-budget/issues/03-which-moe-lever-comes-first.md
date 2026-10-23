# 03: Which MoE lever comes first

Type: grilling
Status: open
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
