# 48: sync to 0.87.26

Status: resolved
Type: task
Spec: ../spec.md (Revision 5)

## Problem

The branch is based on 0.87.23 and upstream is at 0.87.26. A performance claim tied to the
older base is obsolete on arrival, and the 0.87.26 engine moves may shift the numbers by more
than our patches do.

## Change

Merge 0.87.26 into the branch. The range touches zero ggml-metal files, so none of the 15
patches is in its path and the merge is application-layer. A merge, not a rebase: re-provenancing
the Metal work to satisfy a merge that cannot conflict is pure cost.

## Evidence

The patch-series script exiting 0 against the pin, which is the proof the sync did not break
provenance. Then re-run the A/B if the engine version moved the numbers.

## Answer

Merged as `14b76db` into the PR branch. Two parents (`7871133` and `523b814`), so the next
sync still has a correct merge base.

**Provenance holds: 39 of 39 patches apply cleanly**, exit 0, none needing a three-way merge.
No patch was edited.

Three conflicts, resolved on their merits rather than by picking a side: `VERSION` keeps the
fork's `0.87.26-beta.1` naming, `AboutTab.swift`'s version string is reconciled to match it,
and `CHANGELOG.md` is a union -- the fork's Unreleased section stays at the top with upstream's
0.87.26 and 0.87.25 entries above the fork's 0.87.24 entry, and both sides' hunks are pure
additions against the merge base, so nothing was dropped from either.

Both sides' content was checked mechanically by line presence rather than by eye. Across the
six files the fork patches, upstream's additions are 49/1/35/7/9/14 and ours are 91/15/102/4/21/20,
with **zero lines missing from either side**. The fork's three CI jobs survive alongside
upstream's new engine-test work.

**A correction worth carrying forward.** The check this ticket specified for "upstream touched
no ggml-metal files" cannot run in this repository: `d8123504938` is the llama.cpp pin, not a
commit here, and this repo contains no `ggml/` paths at all. It exits 128. The claim is true by
a stronger route -- the pin is unchanged across the merge, so the engine range is empty -- but
the original command was never runnable and was cited as evidence. Recorded in
`evidence/the-pin-check-never-worked-2026-10-19.md`.
