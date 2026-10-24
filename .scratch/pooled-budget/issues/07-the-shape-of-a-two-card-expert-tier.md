# 07: The shape of a two-card expert tier

Type: grilling
Status: resolved
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

## Answer

**(a), layer-split arenas, built by extending the fork's Dynamic MoE.** Decided by the
orchestrator on 2026-10-24, under the user's delegation ("design and guide everything").
- Each card holds the attention, KV and hot-expert arena of the layers it owns. One host
  executor serves both cards.
- 8 KiB per token crosses between the cards, at the single layer boundary. True expert
  parallelism would move about 656 KiB per token plus two syncs per layer.
- **Not (c), porting upstream's `--moe-cache-mib`.** Upstream uploads every missed expert
  over PCIe (1.69 MiB each, up to 540 MiB per token) instead of computing it on the CPU. On
  this machine the CPU computes a miss in about 64 µs. The fork's mixed execution is the
  better half to keep.
- **Gate:** state the cross-card bytes per token, and compare against the one-card expert
  tier in the same session.
