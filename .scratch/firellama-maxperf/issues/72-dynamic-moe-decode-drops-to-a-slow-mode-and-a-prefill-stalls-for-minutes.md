# 72: Dynamic MoE decode drops to a slow mode, and a prefill stalls for minutes

Status: needs-triage
Type: bug
Blocks: the expert-tier placement's numbers. Its decode figure holds only in the fast mode.

## Problem

On the 35B Q6_K with the app's launch and `--dynamic-moe on`, a server runs in one of two
modes:

| mode | short decode (tok/s) | long prompt (tok/s) |
|---|---|---|
| fast | 13.1–13.2 | about 72.8 |
| slow | 10.1–10.8 | about 63–64 |

- Within one server's life the rows are tight, and the mode can change between requests.
- The slow mode ends with one prefill that blocks for minutes:
  - 2130 s for 2402 tokens (`dm_t12_x12` r3 of the thread A/B);
  - 472 s (`dm_t4_x10` r6).

  After the stall, the server is back in the fast mode.
- The same thing showed up in the earlier sweep (`dm_t12_x12` r1, prompt 1.7 tok/s).
- In the A/B it hit 4 of 12 servers, both thread settings alike.

The 35-minute prefill is a hang as far as the app's user is concerned.

## What is ruled out

- **Threads:** the A/B (`-t 12` + 12 executor threads vs `-t 4` + 10) shows equal means and
  both modes on both sides.
- **Arena size:** all 12 A/B servers had a 1082.85 MiB arena.
- **The policy:** hit rate, host time per job (~351 µs), promotions and evictions per graph
  are the same in fast and slow servers.
- **Paging:** the 25200 MiB expert bank is mlocked in every server.
- **CPU throttling:** the host path shows no modes, and `pmset -g therm` reports no limit.

## Where the time goes

The stall is in "issuing uploads", `tosh_dmoe_note_time(1, …)`: 16 s over a fast server's
life against 2112 s and 454 s in the slow ones. "Issuing uploads" times the
`ggml_backend_tensor_set_async` call for a compact prefill bank upload
(`ggml/src/ggml-backend.cpp:2121`). On Metal that call is
`ggml_metal_dmoe_compact_upload` → `ggml_metal_dmoe_ring_flush`, which can block in one of
two places:
- `waitUntilCompleted` on a ring chunk's previous blit (timeline kind 7);
- the `dispatch_apply` memcpy into the write-combined ring (timeline kind 5).

GPU time of the uploads, summed, is about 70 s in both modes. So the GPU does not run long;
it is the host waiting, or a blit waiting on a pending event
(`ggml_metal_encode_pending_waits`) before it starts.

## Next

Reproduce with `TOSH_DMOE_TIMELINE=<file>` (scratchpad `stall.sh`) and read kinds 5 and 7
across the stalled prefill.

Evidence: `../evidence/cpu-threads-on-the-35b-host-and-dynamic-moe-2026-10-22.md`.

## Finding: the default card is the display card, and the planner silently falls back

- The first reproduction (`stall.sh`) never ran Dynamic MoE. The planner saw 3.8 GiB free
  on card 0 and chose `PLAN_CLASSIC_NCMOE` (`--n-cpu-moe 40`), which is ticket 66's path:
  - 120 requests at about 9.8 tok/s;
  - no `dmoe_init`, and no stats or timeline at exit.

  That run is not a Dynamic MoE observation.
- Dry runs on 2026-10-22, two tries each:

  | card | planner result |
  |---|---|
  | `GGML_METAL_DEVICE_INDEX=0` | `PLAN_UNSUPPORTED` (VRAM_LIMIT, available_vram=3.9GiB) |
  | `GGML_METAL_DEVICE_INDEX=1` | `PLAN_FULL_HOST_DMOE` (vram=5.0GiB) |

- ioreg reports `vramFreeBytes` of 4161716160 on one D700 and 6192537536 on the other. The
  card that drives the display holds about 2 GB.
- Across the A/B and the sweep, card 0's free VRAM at launch ranged from 4.5 to 5.0 GiB, and
  the arena size varied with it.
- App fix (uncommitted): when no card is picked, the expert tier runs on the card with the
  most free VRAM (`ServerSettings.expertTierCard`, from `VRAMMonitor.snapshot()`). Two tests
  cover it.
- Open hypothesis: the slow mode and the stalls are WindowServer contending for card 0's GPU.
  All the Dynamic MoE rows to date ran on card 0. A card-1 series (`card1.sh`, 6 servers) is
  running.
- Still to decide: should the planner's `CLASSIC_NCMOE` fallback refuse instead, given what
  ticket 66 found on that path?

## Card 1 series (2026-10-22): no slow mode, no stall

Method: the same engine, model, launch and request pattern as the thread A/B, with
`GGML_METAL_DEVICE_INDEX=1`, `-t 12` and the default executor threads. 6 fresh servers, one
after another. Warmups were discarded.

| card | short decode (tok/s) | long decode (tok/s) | long prompt (tok/s) | servers with slow mode or stall |
|---|---|---|---|---|
| 1 (this series) | 13.1324 (sd 0.1129, N = 18) | 12.4293 (sd 0.0471, N = 12) | 73.1019 (sd 0.1032) | 0 of 6 |
| 0 (thread A/B, default cell) | 12.8096 (sd 0.9347, N = 18) | 11.9366 (sd 1.0548, N = 12) | 64.7704 (sd 20.3972) | 2 of 6 |

- Every card-1 server planned `PLAN_FULL_HOST_DMOE` with a 1082.85 MiB arena.
- "Issuing uploads" took 16.2–16.5 s per server life, the same as the fast card-0 servers.
- Hit rate was 33.6–35.0%.
- All 30 answers are coherent.

Reading: across the A/B, both of its cells, card 0 showed the slow mode in 4 of 12 servers.
Card 1 showed it in 0 of 6. At a 1-in-3 rate, 0 of 6 happens by chance about 9% of the time.
So this is strong support for the display card being the cause, not proof. The app now
avoids that card. To close the ticket, the A/B needs to be repeated with the cards
alternating.
