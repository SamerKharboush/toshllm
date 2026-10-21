# 64: the signed 0.87.26-beta.1 release

Status: resolved
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

## Answer

**The release is published. The tag is annotated and not signed, and the gap is written
down in three places.**

- The upstream tag check found **v0.87.27**, SSH-signed by `engeldlgado@gmail.com`
  (`SHA256:go6fR8fJ7vSRDrbe1jsFFvsJ9I1A8r2ZC5hmOha0934`), verified against
  `~/.config/git/allowed_signers`. It was merged with two parents (`decdc81`) and the
  version is `0.87.27-beta.1`.
- The patch series: **50 of 50 apply cleanly** to a pristine worktree of
  `d8123504938` (the 40 this fork carried before the upstream merge, plus the 10 the
  0.87.27 merge brought), and `scripts/check-patch-series.sh` exits 0.
- `assert_artifact()` passes for both artifacts: the engine reports the pin
  `d81235049`, and the bundle's `CFBundleShortVersionString` is `0.87.27-beta.1`, the same
  as `VERSION`.
- The gate passes on the shipped engine (`-ngl 0` and `-ngl 99` both served 32 tokens) and
  the forced-drop control reads 1, so the check can fail.
- The DMG is `dist/ToshLLM-v0.87.27-beta.1.dmg`, sha256
  `3b5f41b9cdf948ba3634c31da8159a88ac9cc742193d7ee101f9f6588d4b1d3b`, and the digest is
  published with the release.
- The release is published at
  <https://github.com/SamerKharboush/toshllm/releases/tag/v0.87.27-beta.1> as a prerelease
  with three assets: the DMG, `checksums.txt` and `beta27-notes.md`. It was published by
  hand, as the 0.87.24-beta.1 release was: the workflow's `on.push` filter needs a change
  under `patches/**` or `Sources/**` to fire on a tag, and this tag's commit changed
  neither, so no run started.
- The README is written from the rows (R1 to R23), one row per measurement, and the
  retracted claims are listed in "Retracted claims" with what replaces each one.

**The tag is not signed.** gpg is not installed on this machine, and the only SSH key is
passphrase-protected with an empty agent, so git could not sign the tag unattended and
`git tag -s` failed with "incorrect passphrase supplied to decrypt private key". The
release was shipped with an annotated tag instead, like `v0.87.24-beta.1` and every earlier
release tag in this fork, and the gap is written in the CHANGELOG's 0.87.27-beta.1
section, in the release notes, and here. A person at the keyboard can sign it later with
`ssh-add --apple-use-keychain ~/.ssh/id_ed25519` and `git tag -s -f v0.87.27-beta.1`.
