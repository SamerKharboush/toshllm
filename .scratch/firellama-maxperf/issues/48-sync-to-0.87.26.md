# 48: sync to 0.87.26

Status: ready-for-agent
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
