# 64: the signed 0.87.26-beta.1 release

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 8)

## Problem

Everything else in this round is a measurement, and a measurement that ships in no artifact
is a claim. The release has to carry the numbers, the digests and the retractions, and it has
to be signed so that the artifact and the evidence can be tied together later.

## Change

- Weekly upstream tag check; merge the newest tag with two parents.
- The 40-patch series applies to the pinned commit (`scripts/check-patch-series.sh` exits 0).
- `assert_artifact()` passes for the engine and for the app bundle.
- `make dmg`, sha256 of the image, a GPG-signed tag, the evidence attached.
- The README is written last, one sentence per row of the CSV, with the retractions listed.

## Done when

- A signed tag, a published sha256, and an artifact whose own `--version` and bundle version
  are asserted against `VERSION`.
- Every README number cites a row in the evidence, and every claim that was withdrawn is
  still listed as withdrawn.
- The preflight gate passes on the shipped artifact, and the gate has been seen to fail on a
  forced drop.
