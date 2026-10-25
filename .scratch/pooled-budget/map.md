# Pooled budget map

Labels: wayfinder:map

## Destination

A ranked spec for 0.87.27-beta.3, ready to hand off. It names which levers get built to run
models bigger than the cards fast on the **pooled budget** (both D700s, 64 GB RAM, the
12-core AVX1 Xeon), in what order, and the measured gate each must pass.

## Notes

- **Spec written:** `spec.md` (revision 1, 2026-10-24), the destination. Ticket 09 is still running; its answer may re-rank the spec.

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

- Spec revision 3 (the user, 2026-10-25): the GPU dense mat-vec kernel goes to the top of the beta.3 spec; the two-card tier finishes after it
- [Which GPU ops take the 59 ms](issues/10-which-gpu-ops-take-the-59-ms.md): the dense Q6_K mat-vec is 39.6 ms of a 78 ms token, at an effective 39.8 GB/s against a rated 264; the join (CPU-expert wait) is 9.9 ms and the resident experts 9.3 ms
- [What the 62 ms outside the host experts is](issues/09-what-the-62-ms-outside-the-host-experts-is.md): the GPU is busy 73.4 of 76.0 ms per token; the CPU experts (14.4 ms) are waits inside that, which leaves about 59 ms of GPU kernel time, the largest share
- [Which MoE lever comes first](issues/03-which-moe-lever-comes-first.md): (b) the second card's arena first, then (a) the AVX1 kernel, (c) overlap last; (b) is mainly a capacity lever on the 35B
- [The shape of a two-card expert tier](issues/07-the-shape-of-a-two-card-expert-tier.md): layer-split arenas extending the fork's Dynamic MoE, 8 KiB/token across the cards; not upstream's --moe-cache-mib, which uploads misses instead of computing them
- [Where a Dynamic MoE decode token spends its time](issues/01-where-a-dynamic-moe-decode-token-spends-its-time.md): the host experts are fully on the critical path (slope 0.976), about 16 ms of a 78 ms token; CPU-side levers are bounded near 16 tok/s, and 62 ms sits outside the executor
- [Close the display-card question with an alternating A/B](issues/02-close-the-display-card-question.md): not reproduced with the display asleep (0 slow servers in 12); card 0 is 0.09 tok/s behind card 1 and gets a smaller arena; the slow mode stays open as an awake-display effect (ticket 72)
- [The Qwythos-9B draft trial](issues/08-the-qwythos-draft-trial.md): the draft makes the dense 27B slower (1.33 against 1.94 tok/s) despite 64% acceptance; each verify round costs about four host tokens
- [Which draft to try for the dense 27B](issues/06-which-draft-to-try-for-the-dense-27b.md): quantise Qwythos-9B to Q3_K_M and run a measured trial, target on the host, draft on the non-display card
- [Expert parallelism across GPUs that cannot see each other](issues/04-expert-parallel-across-gpus-that-cannot-see-each-other.md): no engine has a no-peer-link expert-parallel path; layer-split arenas cost 8 KiB/token across the cards against about 656 KiB for true expert parallelism; vLLM, SGLang and kt-kernel cannot run here (AVX2, no Metal)
- [A draft model for the dense 27B on the host](issues/05-a-draft-model-for-the-dense-27b.md): nothing small on disk shares its vocabulary (Qwen3 small models do not); Qwythos-9B BF16 matches exactly, a Qwen3.5 0.8B would need a download; the engine can put a draft on a card with the target at -ngl 0 (source only)

## Not yet specified

- Dense models bigger than VRAM: no lever left after the draft trial. A Qwen3.5 0.8B draft (download) or splitting a draft round's cost are the only open threads.

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
