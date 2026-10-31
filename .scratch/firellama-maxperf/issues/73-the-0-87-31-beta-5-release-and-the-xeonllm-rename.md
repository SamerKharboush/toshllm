# 73: the 0.87.31-beta.5 release and the XeonLLM rename

Status: in progress
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

Pending publication.
