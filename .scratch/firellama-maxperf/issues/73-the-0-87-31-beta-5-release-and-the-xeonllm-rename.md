# 73: the 0.87.31-beta.5 release and the XeonLLM rename

Status: resolved
Type: task

## Problem

beta.4 (ticket 72) left three items open: the drafter's borrowed output head running on the
host, threshold crossovers at matrix widths other than the two measured, and 32-lane SIMD
hardware. The user also asked for the rename from ToshLLM to XeonLLM across the fork (app,
bundle, DMG, icon, docs, repository), a README that says how the fork differs and what it
measured, and main fast-forwarded to this branch.

## Change

- `spec/0073`: a DFlash draft on a card copies the borrowed host lm head to its own device
  once at load (`TOSH_DFLASH_HEAD_HOST=1` keeps the host path). Evidence:
  `evidence/the-drafter-head-on-the-card-2026-10-31.md`.
- `metal/0074`: q6_K and q4_K mat-vec thresholds that move with k. Evidence:
  `evidence/thresholds-at-other-k-2026-10-31.md`. A delegate-proposed q4_K rule was rejected
  there (it contradicted the k 8192 rows and would have moved the 14B ffn_down).
- 32-lane: not run; both rules sit inside `simd_width == 64` checks. The delegate's 32-lane
  plan and other-engines survey were not kept (invented switches, factual errors); the
  other-engines question stays open.
- The rename: bundle id `dev.xeonllm.app`, `IdentityMigration.swift` copies ToshLLM's
  settings, Application Support folder and Keychain items once and deletes nothing (7 tests);
  `TOSH_*` env vars, `TOSH*` plist keys, the `X-ToshLLM-*` webhook headers and the
  `toshllm-settings` import stay. CITATION.cff and .zenodo.json describe upstream's Zenodo
  record and keep its title. The DMG layout template had its item and volume names changed
  byte for byte (same length); Finder automation timed out on this machine, so it was not
  regenerated.
- Delegation: Mocca (OpenCode, 9router) ran E1, E2 and the rename; 9router stopped answering
  `/v1` from 08:20 to 10:54 on 2026-10-31. Its migration had wrong constants (rewritten by its
  own sweep), a keychain query macOS rejects, and README/attribution errors; the orchestrator
  fixed those in review.

## Answer

**Published at <https://github.com/SamerKharboush/xeonllm/releases/tag/v0.87.31-beta.5>, a
prerelease with the DMG, `checksums.txt` and `beta31b5-notes.md`.** The repository was renamed
from SamerKharboush/toshllm to SamerKharboush/xeonllm (GitHub redirects the old URL), and main
was fast-forwarded to `phase1-metal-d700-optimization`.

- The series: 84 of 84 apply to the pin `d81235049`.
- The engine: AVX1, llama-server sha256
  `4bde27f80fb0a340564c82cf4b17ff48795a254578e41c2f392fc83ad5af97e8`; the bundle's signed copy
  `ed4841fc419a1b31e8f386b679cc0d675241c0f30bd3d3c68990801ac50ecbb5` has the same four code
  and data sections. 0 AVX2/FMA mnemonics.
- The gates: MUL_MAT 1760/1760, MUL_MAT_ID 873/873, FLASH_ATTN_EXT 1993/1993 (also with
  `TOSH_FA_AMD=1`) on card 1; the preflight served on `-ngl 0` and `-ngl 99` and its
  forced-drop control reads 1; `assert_artifact` passes; `swift test`: 504 tests, 16 skipped,
  3 failures, all in the pre-existing `MCPStdioTransportTests` race.
- The DMG: `XeonLLM-v0.87.31-beta.5-noavx2.dmg`, sha256
  `da7bcaf1ad34a241544017f33e60f6a1c53a1b2d7e6ef418d52383b4eeb07367`; mounted, bundle id
  `dev.xeonllm.app`, version 0.87.31-beta.5, `TOSHNoAVX2` and `TOSHUpdatesDisabled` true,
  codesign verifies.
- The tag `v0.87.31-beta.5` is annotated, not signed.

Not covered: a 32-lane GPU, the drafter and threshold numbers on the bundled engine (both were
measured on the dev tree build of the same source), an eye check of the DMG window, and the
other-engines survey.
