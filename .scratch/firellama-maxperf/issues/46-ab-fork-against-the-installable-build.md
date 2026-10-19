# 46: A/B the fork against the installable build

Status: ready-for-agent
Type: task
Blocked by: 45
Spec: ../spec.md (Revision 5)

## Problem

No comparison that decides anything has been run. The question is what a user gets from this
fork over the build they can download.

## Change

Alternating blocks in one session so thermal drift cancels: fresh process per block, 200-token
warmup discarded, 500 measured tokens, N at least 20, thermal idle first. Both binaries, same
model files, same prompt, pp512 and tg128. Let the existing calibration harness do the work --
it already records cells, reps and a versioned CSV with per-cell sigmas -- extended to take a
binary path rather than a new harness written alongside it.

## Evidence

Per-binary tok/s with sigma, pp512 and tg128, and the per-binary kernel and fallback counters
in the same file. If the delta is inside the noise floor, that is the result.
