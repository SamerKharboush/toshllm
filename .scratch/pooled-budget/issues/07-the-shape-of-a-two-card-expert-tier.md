# 07: The shape of a two-card expert tier

Type: grilling
Status: open
Blocked by: 03

## Question

If the lever ticket picks a bigger arena from the second card, which shape does ticket 71
build? Each option is costed in bytes per token for the 35B in ticket 04's answer.
- (a) **Layer-split arenas:** each card holds the attention, KV and hot experts of its own
  layers. Upstream's `--moe-cache-mib` takes this shape: 8 KiB per token crosses at the
  boundary, and nothing else goes card to card.
- (b) **Expert parallelism:** both cards hold every layer, experts are split by id, and about
  656 KiB plus two syncs per layer cross the cards.
- (c) **Port upstream's `--moe-cache-mib`** instead of extending the fork's Dynamic MoE.

Whichever shape is picked, its gate states what crosses the cards per token and is measured
against the one-card expert-tier baseline.
