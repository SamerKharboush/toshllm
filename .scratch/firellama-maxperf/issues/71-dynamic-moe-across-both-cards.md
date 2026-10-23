# 71: Dynamic MoE across both cards

Status: needs-triage
Type: feature
Spec: ../spec.md (Revision 8)
Blocked by: 70

## Problem

The owner's goal is the two D700s and the 64 GB working together on a model that does not fit in VRAM. With
0046 (ticket 70), Dynamic MoE runs on **one** card: attention, KV and a hot-expert arena on card 0, every
expert pinned in RAM, the host computing the misses. Card 1 sits idle, and a model whose non-expert weights
plus KV do not fit on one card cannot use Dynamic MoE at all.

The two cards cannot pool VRAM: the probe reports each as `not bridged` (no peer access). They cooperate
through a layer split, as the 8B does today (R25).

## Where the single-card assumption lives

- Metal: per device already. `ggml-metal-device.m:1225-1232` keeps the rendezvous event, stage, tables,
  observation and wide buffers per `ggml_metal_device`.
- Runtime: one global executor (`g_exec`) and one arena on the first GPU (`src/llama-tosh-dmoe.cpp:1865`,
  `ggml_backend_dev_by_type(GPU)`).
- Planner: one device's VRAM (`common/tosh-plan.cpp:363`); budgets one arena.
- Rendezvous: one publish-value sequence and one job ring (`tosh-moe/tosh-dmoe.h`). A layer split runs the
  cards in sequence for one token, so a single sequence may hold, but it must be shown, not assumed.
- App: `usesAutoPlan` requires `!isSplitting` (`Sources/Servers/Server.swift:1073`), and a two-GPU Mac
  splits by default (`defaultMultiGPU`).

## Change

1. Runtime: an arena per device, sized from that device's budget, holding experts of the layers it owns;
   publish/join scheduled on the layer's device; one host executor serving both.
2. Planner: per-device budgets under a layer split; the arena and prefill slots per device.
3. App: with Dynamic MoE planning a split, `usesAutoPlan` no longer requires one card; the 67 host rule
   steps aside for MoE models it can serve.

## What the measurements so far predict, so the result can be read honestly

- On the 35B, a larger arena did **not** speed decode: 1477 MiB (hit rate ~40%) and 788 MiB (~28%) both
  gave ~13.2 tok/s (ticket 70 evidence). The host executor sets the decode pace (~355 us per job). Two
  cards are therefore not expected to raise the 35B's decode by themselves.
- Where two cards should pay: (a) models whose non-expert weights + KV exceed one card, which one-card
  Dynamic MoE refuses; (b) longer contexts (KV split over two cards); (c) prefill, if the two cards' uploads
  overlap.
- A test for (a) needs a larger MoE model than any on this machine (the 35B is the only MoE GGUF in
  `~/models` and `/Volumes/micron`). That is a download, for the owner to approve.

## Done when

- The 35B at `-c 16384` runs Dynamic MoE across both cards with mixed execution on both, confirmed in the
  logs per device, coherent output, N >= 6 against the one-card row of ticket 70.
- A MoE model that one-card Dynamic MoE refuses runs across two cards, or the reason it cannot is recorded.
- Configurations that cannot be run are named next to the numbers.
