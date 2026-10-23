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
