# 37: the patch series is validated in CI

Status: resolved
Blocked by: none
Spec: ../spec.md (Revision 2)

## Problem

The series checker is a script someone remembers to run. The claim that this tree is
the pin plus a series is load-bearing provenance, and a patch edit can break it
silently.

## Change

A CI job that hydrates the pin, applies the full series, and fails if any hunk no
longer applies. The checker already exists and exits 0 when every patch applies
cleanly or with a three-way merge.

## Evidence

The job runs green on the current tree, and the existing checker exits 0 against the
pin. Note in the job that a non-zero exit means the provenance claim is broken, not
merely that a patch is stale.

## Answer

The `patch-series` job in `.github/workflows/build.yml` runs `scripts/check-patch-series.sh`
against the pin parsed out of `scripts/build-engines.sh`, on pull requests, with a 60 minute
timeout. Its comment says a non-zero exit is the provenance claim broken, not a stale patch.
PRs run it unfiltered because a patch edit is reviewed there; branch pushes go through the
workflow's existing `on.push.paths` filter, so it is not run on every push. The checker is
zsh, which the Linux runner image does not ship, so the job installs it when absent.

Run locally against the pin: `38 of 38 apply cleanly`, 0 three-way, 0 failed, exit 0.
