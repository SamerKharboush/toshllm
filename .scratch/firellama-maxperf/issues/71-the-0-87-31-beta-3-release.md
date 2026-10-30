# 71: the 0.87.31-beta.3 release

Status: resolved
Type: task

## Problem

Upstream ToshLLM moved to 0.87.31, and this fork's D700 work (0051-0056: Dynamic MoE on
every card, per-layer DFlash causality, the dense mat-vec gate and its eight-row rule)
shipped in no artifact.

## Change

- Upstream v0.87.31 is merged. Its 24 llama patches join the series. Three upstream hunks
  are rebased onto this fork's earlier patches (`metal/0052` `am_measure`, `metal/0054` the
  FA-AMD guard, `moe/0064` the dmoe pick next to the ticket-66 legacy guard). This fork's six
  newest patches move to 0066-0071.
- The version is 0.87.31-beta.3. The bundle is stamped no-AVX2 and has in-app updates off,
  because the updater reads upstream's releases.

## Answer

**Published at <https://github.com/SamerKharboush/toshllm/releases/tag/v0.87.31-beta.3>,
a prerelease with the DMG, `checksums.txt` and `beta31b3-notes.md`.**

- The series: 81 of 81 apply to the pin `d81235049`.
- The engine: the AVX1 build, `4f87c3d8aa817826643962a409b6e7cae0d8af9960dc32570a47179201858dd3`.
  The bundle's ad-hoc-signed copy is `a26b6f937c8c5f600c0e184fa64378fe96579eb683999a7f1166dd451ef09aca`,
  with its `__TEXT,__text`, `__TEXT,__const`, `__DATA,__data` and `__DATA_CONST,__const`
  identical to the build. 0 AVX2/FMA mnemonics.
- The gates:
  - `test-backend-ops` MUL_MAT, MUL_MAT_ID and FLASH_ATTN_EXT (also with `TOSH_FA_AMD=1`):
    0 FAIL on card 1;
  - the preflight: `-ngl 0` and `-ngl 99` each served 32 tokens, and the forced-drop control
    reads 1;
  - `assert_artifact`: engine commit == pin, bundle == VERSION;
  - `swift test`: 497 tests, 16 skipped, 3 failures, all in the pre-existing
    `MCPStdioTransportTests.testAnswersRacingTheirDeadlinesResolveEachRequestOnce` race.
- The numbers: the notes' tables were measured on this engine.
  - llama-bench `-p 0 -n 128 -fa 1`, old = `TOSH_MV_ROWS8_DISABLE=1`:
    - 8B Q4_K_M, one card, N = 5: 8.26 -> 10.20;
    - 4B Q6_K, one card, N = 5: 12.06 -> 13.84;
    - 14B Q4_K_M, layer split on both cards, N = 3: 5.08 -> 6.61.
  - 35B host, N = 3: plain 9.95 (sd 0.22), with the DFlash drafter on card 1 10.84 (sd
    0.04), 73/87 accepted.
  - All texts are byte-identical to the pre-merge engine.
- The DMG: `ToshLLM-v0.87.31-beta.3-noavx2.dmg`, sha256
  `b0cbdd89050c577f4620421eb693cc26d38a293ba50fed16c93e0ae4ca2ccc20`. Mounted, it carries
  version 0.87.31-beta.3, `TOSHNoAVX2` true and `TOSHUpdatesDisabled` true, the same engine
  code, and `codesign --verify --deep` passes.
- The tag: `v0.87.31-beta.3`, annotated, not signed (no gpg; the SSH key is locked). This
  is the same gap as ticket 69.

Not covered, and the subject of the next beta: the row counts between the thresholds,
tensor split, 32-lane cards (unchanged by construction, not measured), and the 35B's Q8_0
drafter kernels.
