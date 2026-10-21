# 69: the 0.87.27-beta.2 release

Status: resolved
Type: task
Spec: ../spec.md (Revision 8)

## Problem

The placement rule is in the app and the rows are measured, but a rule that ships in no
artifact is a claim. The release has to carry the numbers, the digests and the
retractions, and the artifact has to be the one the rows were measured on.

## Change

- The version is bumped to 0.87.27-beta.2, and the bundle and the DMG are rebuilt.
- `assert_artifact()` passes for the engine and for the app bundle.
- The engine in the bundle is the engine the rows were measured on.
- The preflight gate passes on the shipped engine, and the gate has been seen to fail on a
  forced drop.
- The DMG's digest is published with the release, and the tag is annotated.

## Done when

- The DMG is published with its digest, its notes and the checksums, and the bundle's
  version and engine are asserted against `VERSION` and the pin.
- Every number in the release notes names the row it comes from.
- The tag is signed, or the gap is written down in the notes, the changelog and here.

## Answer

**The release is published at
<https://github.com/SamerKharboush/toshllm/releases/tag/v0.87.27-beta.2> as a prerelease
with three assets: the DMG, `checksums.txt` and `beta27b2-notes.md`.**

- The version: `VERSION` is `0.87.27-beta.2` and the bundle's `CFBundleShortVersionString`
  is the same. `assert_artifact` reads the pin `d81235049` from the engine's `--version`
  and passes on both artifacts.
- The engine: the vendor build is
  `8ebda2454b4df9ac348dc289cc44cb7e82af1885aa1c3c2ea78acbc5550b9d0d` and the bundle's copy
  is `9ee9c811e2568792398d6d960ca39e534cfa68fd6098cfe5cf59badce70b3ebf`, the same code
  ad-hoc signed. It is the engine the card cell was measured again on (R26, R27).
- The gate: the preflight passes on the shipped engine (`-ngl 0` and `-ngl 99` both served
  32 tokens) and the forced-drop control reads 1, so the check can fail.
- The DMG: `dist/ToshLLM-v0.87.27-beta.2.dmg`, sha256
  `fd8c28df0d3260746c734279379608757b68b5657494ec67b696f2cccb454c8c`, published with the
  checksums and the notes.
- The numbers: every figure in the notes names its row (R24 to R27), and those rows are in
  `../evidence/rows-2026-10-21.csv`.
- The tag: `v0.87.27-beta.2`, annotated, pointing at the commit that carries the rule and
  the rows.

**The tag is not signed.** gpg is not installed on this machine and the only SSH key is
passphrase-protected with an empty agent, so `git tag -s` cannot run unattended. The tag
is annotated, like `v0.87.24-beta.1`, `v0.87.27-beta.1` and every earlier release tag in
this fork, and the gap is written in the notes, the changelog and here. A person at the
keyboard can sign it later with
`ssh-add --apple-use-keychain ~/.ssh/id_ed25519` and `git tag -s -f v0.87.27-beta.2`.
