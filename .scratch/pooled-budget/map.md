# Pooled budget map

Labels: wayfinder:map

## Destination

A ranked spec for 0.87.27-beta.3, ready to hand off. It names which levers get built to run
models bigger than the cards fast on the **pooled budget** (both D700s, 64 GB RAM, the
12-core AVX1 Xeon), in what order, and the measured gate each must pass.

## Notes

- Glossary: `CONTEXT.md`. Use **pooled budget**, **display card** and **expert tier**; never
  "bridged", "unified" or "shared VRAM" for this pair.
- Planning only. Builds go as tickets in `.scratch/firellama-maxperf/issues/`. This map
  produces decisions, not code.
- Order: MoE models bigger than VRAM come first. Dense models bigger than VRAM stay in the
  fog until the MoE levers are decided.
- Gate for every lever:
  - no zeros or repeated-token tails;
  - the same opening as the host reference text;
  - measured on the non-display card;
  - method-lined per the CLAUDE.md performance rules, against the host row and the
    expert-tier baseline.
- Baseline rows (35B Q6_K, the app's launch, card 1): 13.1324 tok/s decode, 73.1019 tok/s
  prompt. Host: 11.2–11.9 tok/s decode, 27.5 tok/s prompt. Sources: ticket 72 and
  `.scratch/firellama-maxperf/evidence/cpu-threads-on-the-35b-host-and-dynamic-moe-2026-10-22.md`.
- Skills: grilling and domain-modeling for decisions; research for the research tickets.
- Already decided outside this map: the engine refuses the `--n-cpu-moe` fallback on a
  64-lane card instead of answering garbage (ticket 66's path). Delegated to OpenCode on
  2026-10-23.

## Decisions so far

## Not yet specified

- The two-card expert-tier design itself: which card holds which layers or experts, and
  what crosses per token. It waits on whether a bigger arena would help at all.
- Dense models bigger than VRAM: a draft model, or nothing. The research ticket on draft
  models feeds it.
- Prefill on both cards while the experts stay in RAM.
- Whether ticket 68 (the dense two-card split answers zeros) has to be fixed for any lever on
  this map, or stays a separate bug.

## Out of scope

- Soup (MakazhanAlpamys/Soup): a PyTorch/CUDA fine-tuning tool. Its layer streaming is a
  training technique, and for inference it repeats AirLLM's idea. Fine-tuning on this Mac
  would be its own effort.
- Making the D700s bridged or peer-linked. Hardware and driver: peer group 0 is measured.
- AirLLM-style per-token streaming of the whole model. The mmap'd host path already beats it
  (`evidence/third-party-receipts-2026-10-21.md`).
