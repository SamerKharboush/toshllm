# 46: A/B the fork against the installable build

Status: ready-for-agent
Type: task
Blocked by: 45, 48
Spec: ../spec.md (Revision 6)

## Problem

No comparison that decides anything has been run, and the fork has never been built as a
bundle to compare.

## Change

Build our side as a bundle, not a development tree: a packaged artifact against a dev tree is a
category error. Then run both bundles' engine binaries alternating in one session -- fresh
process per block, 200-token warmup discarded, 500 measured, N at least 20, thermal idle
first, tensor split, same model files. Let the existing calibration harness carry it; it
already records cells, reps and a versioned CSV with per-cell sigmas.

## Evidence

Per-block tok/s with sigma for 8B-Q4_K_M and 14B-Q4_K_M, with both sha256 values on every row
and the per-side kernel-compile, refused-pipeline and CPU-fallback counts in the same file.
0.6B is the smoke test and does not enter the verdict.

## Revision 7 note

Re-scoped by Revision 7: the harness is the deliverable and its output is the only evidence the verdict may cite. An independent review reached the same conclusion about the existing harness, which measured one binary sequentially, counted warmups as invocations, and benchmarked a tool rather than the engine.
