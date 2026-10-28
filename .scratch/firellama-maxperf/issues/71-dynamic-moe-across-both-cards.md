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

## 2026-10-25: patches 0051 and 0052, and what a two-card load does now

- **0051:** every card registers its own Dynamic MoE rendezvous.
- **0052:** an expert arena on each card, sized by the per-card budget.
- **Two-card load of the 35B at `-c 16384`:**
  - budget: card 0 has 5285 MiB free and gets a 1705 MiB arena; card 1 has 5906 MiB free
    and gets 2555 MiB;
  - slots: 33 per layer, the minimum of the per-card 33 and 54;
  - allocated: 1705.45 MiB on device 0 and 1543.03 MiB on device 1, so card 1 is held to
    33 slots.
- **It still aborts** at the first graph, in the AMD driver:
  `Assertion failed: (cmdBufInfo->device == rsrc->_res.device), function amdMtlBronzeCmdBufUpdateRsrc`.
  That is a command buffer on one card using a resource on the other. The hypothesis, not
  yet shown: card 0's legacy uploader writing into card 1's arena. Routing uploads and the
  executor by the layer's card is 0053.
- **One card, the 35B greedy BST prompt:**
  - the first sentence and decode speed (12.7–12.8 tok/s) are unchanged;
  - the wording at word 30 is a near-tie that flips between "data structure in computer
    science" and "data structure concept in computer science": 2 of 6 runs on the 0052
    build, 0 of 2 on the pre-0051 build, 3 of 3 on 0051 before its uploader fix, 0 of 2
    after.
  - **Correction to the 0051 commit message:** these samples are too small to say the
    first 0051 version "changed one-card behaviour". The uploader fix stands for another
    reason: the eager init ran before `dev->props.device` was set, so every card registered
    as card 0.
- **The bug in OpenCode's 0052, fixed by the orchestrator:** `dmoe_init` recomputed each
  card's arena as free − reserve − overhead − prefetch without the card's model, cache and
  compute bytes. The budget's per-card arena is now passed in. Before the fix it allocated
  3152 + 2852 MiB against a budget of 1711 + 2555.

## 2026-10-28: patch 0053, the 35B runs coherent across both cards

**Method:** fork engine `d81235049` plus patches 0001–0053, built AVX1 (0 AVX2/FMA
mnemonics). Ornith-1.0-35B Q6_K, `llama-cli -t 12 -fa auto --load-mode none --dynamic-moe on`,
`TOSH_FA_AMD=1`, greedy, the BST prompt, `-n 48`, batch default. One card: `-c 4096`,
`GGML_METAL_DEVICE_INDEX=1`. Two cards: `-c 16384`, `GGML_METAL_DEVICES=2 --split-mode layer`.
Speeds are llama-cli's own generation line, one run each unless N is given, warmups not
discarded (llama-cli's own warmup ran). All in one session on 2026-10-28.

- **Two cards, gate passes:** exit 0, no driver assertion, the text matches the one-card
  reference word for word through "data structure in computer science". Arenas 1808.81 MiB
  on device 0 and 1636.54 MiB on device 1, 35 slots per layer. Hit rate 50.73%, 0 failed
  jobs. Decode 12.01 tok/s (one run). This is a split-mode pair, not a comparison with the
  one-card row: it holds a 16384 context and two arenas, under a different constraint.
- **One card:** 15 of 16 runs open "The user wants an explanation…"; 1 opens "The user asks
  to …", the same first sentence. Decode 12.1–12.9 tok/s over the 16. On the 0052 build
  in the same session: 6 of 6 "The user wants an", 12.2–12.8 tok/s. 1 in 16 against 0 in
  6 is inside the run-to-run variation already recorded below; not read as a change.
- **What crossed cards, and the fixes:**
  1. a publish placed by the scheduler on the previous layer's card reached its join as a
     copy without op params (segfault in the join): the layer's `ffn_moe_*` ops are now
     pinned to its card on a multi-card model;
  2. the scheduler offloads an expert matmul with host weights to the first GPU, whatever
     card owns the layer: same pin;
  3. the scheduler's expert prefetch backend and slots live on one card: it now serves only
     splits on that card; card 1's layers take the regular copy (no prefill overlap there);
  4. the bank upload checks that the arena and destination are on its own card.
- **The "0000" answers:** with all of that fixed, the two-card 35B still answered "0000"
  from about the second graph on, and a fresh request was wrong from its first token. It
  needed expert layers on both cards (`-ts 1,0`, `0,1` and `39,1` were coherent; the
  default split, `30,10` and `10,30` were not). It was not the arena or the policy
  (`TOSH_DMOE_MASK=all` and `TOSH_DMOE_PROMO_STOP=0` both still failed), not the hand-off
  (every one of 320 traced values was answered on the card and layer that published it),
  and not the cross-card copy, concurrency or command-buffer count. `TOSH_GDN_STATE_FUSION_DISABLE=1`
  alone fixed it, so 0053 turns that fusion off when expert layers sit on two cards. The
  dense Qwen3.5 9B split across both cards stays correct with the fusion on. **Root cause
  open:** the logged fusion decisions (gather skipped, copy folded) are consistent on both
  cards.
- **Delegation:** OpenCode (flint-40b-free, then beam-free) did the executor, policy and
  ring conversion in four sessions, two cut short by the free quota. Its build-breaking
  edits (the watchdog loop, the card list declarations, the uploader lookup) and a silent
  `return` in `set_tensor_async` that would have dropped uploads were fixed by the
  orchestrator, who also found and fixed the four crossings and the fusion.
- **Cosmetic, open:** the `mixed expert execution on device N` log line prints the model's
  40 MoE layers for each card instead of the card's own count.
