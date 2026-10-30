# 72: the 0.87.31-beta.4 release

Status: resolved
Type: task

## Problem

0.87.31-beta.3 (ticket 71) shipped the eight-row mat-vec rule with four items not covered:
the row counts between its thresholds, tensor split, 32-lane cards, and the 35B's Q8_0
DFlash drafter kernels.

## Change

- `metal/0072`: q4_K takes sixteen lanes from 12288 rows (was 8192), q6_K takes eight rows
  from 1792 (was 2048); perf cases for the gap and model shapes, eval cases at both new
  boundaries.
- Evidence for all four items: `evidence/the-four-gaps-of-0056-2026-10-30.md`.
- The version is 0.87.31-beta.4, stamped no-AVX2 with in-app updates off, as beta.3.
- The OpenCode/Mocca run for the gaps (brief 0c) exited after 2.5 h with no report and no
  source change, and Mocca then did not answer a probe; the measurements were made by the
  orchestrator. The drafter brief (0d) was not dispatched for the same reason.

## Answer

**Published at <https://github.com/SamerKharboush/toshllm/releases/tag/v0.87.31-beta.4>,
a prerelease with the DMG, `checksums.txt` and `beta31b4-notes.md`.**

- The series: 82 of 82 apply to the pin `d81235049`.
- The engine: AVX1, llama-server sha256
  `22a21a087dc2c58f0602d92563f2d28288e1ae6944ac549aec9ab2d44bec7dbe`; the bundle's signed copy
  `613f8a29f742d11adf436f3b916e4a1a2f324a5424129fa4ab32db8b8d40d9a4` has the same four code
  and data sections. 0 AVX2/FMA mnemonics.
- The gates: test-backend-ops MUL_MAT, MUL_MAT_ID, FLASH_ATTN_EXT (also `TOSH_FA_AMD=1`)
  0 FAIL on card 1; the preflight served on `-ngl 0` and `-ngl 99` and its forced-drop
  control reads 1; `assert_artifact` passes; `swift test`: 497 tests, 16 skipped, 3 failures, all in the
  pre-existing `MCPStdioTransportTests` race (as ticket 71).
- The numbers (llama-bench `-p 0 -n 128 -r 5 -fa 1`, N = 5, old = `TOSH_MV_ROWS8_DISABLE=1`):
  8B one card 8.26 -> 10.20, 4B one card 12.06 -> 13.84 (both as beta.3), 8B tensor split
  13.81 -> 16.39, 4B tensor split 16.72 -> 19.10; texts byte-identical old vs new.
- The DMG: `ToshLLM-v0.87.31-beta.4-noavx2.dmg`, sha256
  `dbe3ce7ff2d73517c5e5a651b6878e8d2c18a2a2e285101895a9382415f57343`; mounted, version
  0.87.31-beta.4, `TOSHNoAVX2` and `TOSHUpdatesDisabled` true, codesign verifies.
- The tag `v0.87.31-beta.4` is annotated, not signed (as ticket 71).

Not covered: a 32-lane card (none here), crossovers at other k, and the drafter's borrowed
host output head, the next lever for the 35B with a drafter.
